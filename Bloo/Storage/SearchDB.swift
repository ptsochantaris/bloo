import Accelerate
import Algorithms
import Foundation
import SQLite

final actor SearchDB {
    static let shared = SearchDB()

    private let textTable = VirtualTable("text_search")
    private let indexDb: Connection

    private var documentIndex: MemoryMappedCollection<Vector>

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

        documentIndex = MemoryMappedCollection(at: documentsPath.appending(path: "document.embeddings", directoryHint: .notDirectory).path,
                                               minimumCapacity: 1000)

        Log.search(.info).log("Loaded document index with \(documentIndex.count) entries")
    }

    func shutdown() {
        documentIndex.shutdown()
    }

    func insert(id: String, url: String, content: IndexEntry.Content) async throws {
        let newRowId = try indexDb.run(
            textTable.insert(or: .replace,
                             DB.domainRow <- id,
                             DB.urlRow <- url,
                             DB.titleRow <- content.title,
                             DB.descriptionRow <- content.description,
                             DB.contentRow <- content.condensedContent,
                             DB.keywordRow <- content.keywords,
                             DB.thumbnailUrlRow <- content.thumbnailUrl,
                             DB.lastModifiedRow <- content.lastModified))

        guard let sparseContent = content.sparseContent ?? content.title, sparseContent.isPopulated else {
            return
        }

        // free this actor up while we produce the vector
        let embeddings = Task<Vector?, Never>.detached {
            if let document = content.condensedContent ?? content.title ?? content.description {
                return await Embedding.vector(for: document, rowId: newRowId)
            }
            return nil
        }

        if let embeddingResult = await embeddings.value {
            documentIndex.append(embeddingResult)
            Log.crawling(id, .info).log("Added document embedding for '\(content.title ?? "<no title>")'")
        }
    }

    func purgeDomain(id: String) throws {
        var ids = Set<Int64>()
        for associatedRow in try indexDb.prepare(textTable.select(DB.rowId).filter(DB.domainRow == id)) {
            let i = try associatedRow.get(DB.rowId)
            ids.insert(i)
        }

        documentIndex.deleteAll {
            ids.contains($0.rowId)
        }

        try indexDb.run(textTable.filter(DB.domainRow == id).delete())
    }

    func searchQuery(_ text: String, limit: Int) async throws -> [Search.Result] {
        let start = Date.now
        defer {
            Log.search(.info).log("Keyword search query time: \(-start.timeIntervalSinceNow) sec")
        }

        let searchTerms = text.split(separator: " ").map { String($0) }
        let terms = searchTerms.map { $0.lowercased().sqlSafe }.joined(separator: " AND ")
        let elements = try Array(indexDb.prepareRowIterator(
            """
            select
            rowid,
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

            limit \(2000)
            """))

        guard let searchVector = await Embedding.vector(for: text) else {
            return elements.map {
                Search.Result(element: $0, terms: searchTerms, relevantVector: nil)
            }
        }

        let rowIds = Set(elements.map { $0[DB.rowId] })

        let vectorLookup = [Int64: Vector](uniqueKeysWithValues: documentIndex.filter {
            rowIds.contains($0.rowId)
        }.map {
            ($0.rowId, $0)
        })

        let searchCoordsBytes = malloc(2048)!
        let searchCoordsBuffer = searchCoordsBytes.assumingMemoryBound(to: Float.self)
        let comparisonBytes = malloc(2048)!
        let comparisonBuffer = comparisonBytes.assumingMemoryBound(to: Float.self)

        defer {
            free(searchCoordsBytes)
            free(comparisonBytes)
        }

        let searchVectorMagnitude = searchVector.magnitude
        withUnsafePointer(to: searchVector.coords) { _ = memcpy(searchCoordsBytes, $0, 2048) }

        return elements.max(count: limit) { e1, e2 in
            guard let v1 = vectorLookup[e1[DB.rowId]], let v2 = vectorLookup[e2[DB.rowId]] else {
                return false
            }
            var R: Float = 0
            withUnsafePointer(to: v1.coords) { _ = memcpy(comparisonBytes, $0, 2048) }
            vDSP_dotpr(searchCoordsBuffer, 1, comparisonBuffer, 1, &R, 512)
            R /= (v1.magnitude * searchVectorMagnitude)
            let R0 = R

            withUnsafePointer(to: v2.coords) { _ = memcpy(comparisonBytes, $0, 2048) }
            vDSP_dotpr(searchCoordsBuffer, 1, comparisonBuffer, 1, &R, 512)
            R /= (v2.magnitude * searchVectorMagnitude)

            return R0 < R

        }.map {
            Search.Result(element: $0, terms: searchTerms, relevantVector: vectorLookup[$0[DB.rowId]])

        }.uniqued { $0.url.normalisedUrlForResults() }
    }
}
