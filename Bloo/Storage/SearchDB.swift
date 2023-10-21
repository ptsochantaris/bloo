import Algorithms
import Foundation
@preconcurrency import NaturalLanguage
import SQLite

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

    private final actor SetenceEmbeddingRental {
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

    private let setenceEmbeddingRental = SetenceEmbeddingRental()

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
        let embedSentences = Task<[Vector], Never>.detached { [setenceEmbeddingRental] in
            let sentences = contentText.split(separator: Self.sentenceRegex, omittingEmptySubsequences: true).map {
                $0.trimmingCharacters(in: .alphanumerics.inverted)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard sentences.isPopulated else {
                return []
            }

            let sentenceEmbedding = await setenceEmbeddingRental.reserve()
            defer {
                Task {
                    await setenceEmbeddingRental.release(embedding: sentenceEmbedding)
                }
            }

            return sentences.compactMap { sentence in
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > 2, trimmed.contains(" "), let vector = sentenceEmbedding.vector(for: sentence) {
                    // Log.crawling(id, .info).log("Embedding [\(newRowId)]: '\(sentence)'")
                    return Vector(coords: vector, rowId: newRowId)
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

    func textQuery(_ text: String, limit: Int) throws -> [Search.Result] {
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
                          terms: searchTerms)
        }
    }

    func items(at searchVector: Vector, limit: Int) -> [Vector] {
        vectorIndex.max(count: limit) { e1, e2 in
            let d1 = searchVector.similarity(to: e1)
            let d2 = searchVector.similarity(to: e2)
            return d1 < d2
        }
    }
}
