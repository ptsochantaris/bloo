import Algorithms
import Foundation
@preconcurrency import NaturalLanguage
import SQLite

final actor SetenceEmbeddingRental {
    static let shared = SetenceEmbeddingRental()

    private var embeddings = [NLEmbedding]()

    func reserve() -> NLEmbedding {
        if let existing = embeddings.popLast() {
            return existing
        }
        return NLEmbedding.sentenceEmbedding(for: .english)!
    }

    func release(embedding: NLEmbedding) {
        embeddings.append(embedding)
    }
}

final actor SearchDB {
    static let shared = SearchDB()

    private let textTable = VirtualTable("text_search")
    private let vectorIndex: MemoryMappedCollection<Vector>
    private let indexDb: Connection

    init() {
        let file = documentsPath.appending(path: "index.sqlite3", directoryHint: .notDirectory)
        let fm = FileManager.default
        if !fm.fileExists(atPath: documentsPath.path) {
            try! fm.createDirectory(atPath: documentsPath.path, withIntermediateDirectories: true)
        }
        let c = try! Connection(file.path)
        try! c.run(DB.pragmas)

        let fts5Config = FTS5Config()
        fts5Config.column(DB.domainRow, [.unindexed])
        fts5Config.column(DB.urlRow, [.unindexed])
        fts5Config.column(DB.titleRow)
        fts5Config.column(DB.descriptionRow)
        fts5Config.column(DB.contentRow)
        fts5Config.column(DB.keywordRow)
        fts5Config.column(DB.thumbnailUrlRow, [.unindexed])
        fts5Config.column(DB.lastModifiedRow, [.unindexed])
        try! c.run(textTable.create(.FTS5(fts5Config), ifNotExists: true))

        indexDb = c

        let embeddingFile = documentsPath.appending(path: "index.embeddings", directoryHint: .notDirectory)
        vectorIndex = MemoryMappedCollection(at: embeddingFile.path, minimumCapacity: 1000)
    }

    private static let sentenceRegex = try! Regex("[\\.\\!\\?\\:\\n]")

    func insert(id: String, url: String, content: IndexEntry.Content) async throws {
        let newRowId = try indexDb.run(
            textTable.insert(or: .replace,
                             DB.domainRow <- id,
                             DB.urlRow <- url,
                             DB.titleRow <- content.title,
                             DB.descriptionRow <- content.description,
                             DB.contentRow <- content.content,
                             DB.keywordRow <- content.keywords,
                             DB.thumbnailUrlRow <- content.thumbnailUrl,
                             DB.lastModifiedRow <- content.lastModified))

        guard let contentText = content.content, contentText.isPopulated else {
            return
        }

        // free this actor up while we produce the vectors
        let embedSentences = Task<[Vector], Never>.detached {
            let sentences = content.indexableText.split(separator: Self.sentenceRegex, omittingEmptySubsequences: true).map {
                $0.trimmingCharacters(in: .alphanumerics.inverted)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard sentences.isPopulated else {
                return []
            }

            let sentenceEmbedding = await SetenceEmbeddingRental.shared.reserve()
            defer {
                Task {
                    await SetenceEmbeddingRental.shared.release(embedding: sentenceEmbedding)
                }
            }

            return sentences.compactMap { sentence in
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > 2, trimmed.contains(" "), let vector = sentenceEmbedding.vector(for: sentence) {
                    // Log.crawling(id, .info).log("Embedding [\(newRowId)]: '\(sentence)'")
                    return Vector(coords: vector, rowId: newRowId, sentence: sentence)
                }
                return nil
            }
        }

        let newVectors = await embedSentences.value
        vectorIndex.append(contentsOf: newVectors)
        Log.crawling(id, .info).log("Added \(newVectors.count) embeddings")
    }

    func purgeDomain(id: String) throws {
        try indexDb.run(textTable.filter(DB.domainRow == id).delete())
    }

    func keywordQuery(_ text: String, limit: Int) throws -> [Search.Result] {
        let searchTerms = text.split(separator: " ").map { String($0) }
        let terms = searchTerms.map { $0.lowercased().sqlSafe }.joined(separator: " AND ")
        return try indexDb.prepareRowIterator(
            """
            select
            url,
            snippet(text_search, 2, '#[BLU', 'ULB]#', '...', 64) as title,
            snippet(text_search, 3, '#[BLU', 'ULB]#', '...', 64) as description,
            snippet(text_search, 4, '#[BLU', 'ULB]#', '...', 64) as content,
            keywords,
            thumbnailUrl,
            lastModified

            from text_search

            where text_search match '\(terms)'

            order by bm25(text_search, 0, 0, 20, 10, 5, 5), lastModified desc

            limit \(limit)
            """).map {
            Search.Result(id: $0[DB.urlRow],
                          title: $0[DB.titleRow] ?? "",
                          descriptionText: $0[DB.descriptionRow] ?? "",
                          contentText: $0[DB.contentRow],
                          displayDate: $0[DB.lastModifiedRow],
                          thumbnailUrl: URL(string: $0[DB.thumbnailUrlRow] ?? ""),
                          keywords: $0[DB.keywordRow]?.split(separator: ", ").map { String($0) } ?? [],
                          terms: searchTerms,
                          manuallyHighlight: nil)
        }
    }

    func sentenceQuery(_ text: String, limit: Int) async throws -> [Search.Result] {
        let nl = await SetenceEmbeddingRental.shared.reserve()
        defer {
            Task {
                await SetenceEmbeddingRental.shared.release(embedding: nl)
            }
        }

        guard let sv = nl.vector(for: text) else {
            return []
        }

        let searchVector = Vector(coords: sv, rowId: 0, sentence: text)

        let vectors = vectorIndex.max(count: limit) { e1, e2 in
            let d1 = searchVector.similarity(to: e1)
            let d2 = searchVector.similarity(to: e2)
            return d1 < d2
        }

        let idList = vectors.reversed().map(\.rowId)
        let rowIds = idList.map { String($0) }.joined(separator: ",")
        let termList = text.split(separator: " ").map { String($0) }

        return try indexDb.prepareRowIterator(
            """
            select
            rowid,
            url,
            title,
            description,
            content,
            keywords,
            thumbnailUrl,
            lastModified

            from text_search

            where rowid in (\(rowIds))
            """
        ).map { element in
            Self.createResults(element, terms: termList, vectors: vectors)
        }.sorted {
            (idList.firstIndex(of: $0.0) ?? 0) < (idList.firstIndex(of: $1.0) ?? 0)
        }.map(\.1)
    }

    static func createResults(_ element: RowIterator.Element, terms: [String], vectors: [Vector]) -> (Int64, Search.Result) {
        let id = element[DB.rowId]
        let relevantPhrase = vectors.first(where: { $0.rowId == id })?.sentence

        return (
            id,

            Search.Result(id: element[DB.urlRow],
                          title: element[DB.titleRow] ?? "",
                          descriptionText: element[DB.descriptionRow] ?? "",
                          contentText: element[DB.contentRow],
                          displayDate: element[DB.lastModifiedRow],
                          thumbnailUrl: URL(string: element[DB.thumbnailUrlRow] ?? ""),
                          keywords: element[DB.keywordRow]?.split(separator: ", ").map { String($0) } ?? [],
                          terms: terms,
                          manuallyHighlight: relevantPhrase)
        )
    }
}
