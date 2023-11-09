import Accelerate
import Algorithms
import Foundation
import SQLite

final actor SearchDB {
    static let shared = try! SearchDB()

    private let textTable = VirtualTable("text_search")
    private let indexDb: Connection

    private var documentIndex: MemoryMappedCollection<Vector>

    init() throws {
        let file = documentsPath.appending(path: "index.sqlite3", directoryHint: .notDirectory)
        let fm = FileManager.default
        if !fm.fileExists(atPath: documentsPath.path) {
            try! fm.createDirectory(atPath: documentsPath.path, withIntermediateDirectories: true)
        }
        let c = try! Connection(file.path)
        try! c.run(DB.pragmas)

        try! c.run("""
            CREATE VIRTUAL TABLE IF NOT EXISTS "text_search"
            USING fts5("domain" UNINDEXED, "url" UNINDEXED, "title", "description", "content", "keywords", "thumbnailUrl" UNINDEXED, "lastModified" UNINDEXED, tokenize="porter unicode61 remove_diacritics 1")
        """)
        indexDb = c

        documentIndex = try MemoryMappedCollection(at: documentsPath.appending(path: "document.embeddings", directoryHint: .notDirectory).path,
                                                   minimumCapacity: 1000)

        Log.search(.info).log("Loaded document index with \(documentIndex.count) entries")
    }

    func shutdown() {
        documentIndex.shutdown()
    }

    func insert(id: String, url: String, content: IndexEntry.Content, existingRowId: Int64?) async throws -> Int64 {
        let textTableRowId: Int64
        if let existingRowId {
            textTableRowId = existingRowId
            try indexDb.run(textTable
                .where(DB.rowId == existingRowId)
                .update(DB.rowId <- existingRowId,
                        DB.titleRow <- content.title,
                        DB.descriptionRow <- content.description,
                        DB.contentRow <- content.condensedContent,
                        DB.keywordRow <- content.keywords,
                        DB.thumbnailUrlRow <- content.thumbnailUrl,
                        DB.lastModifiedRow <- content.lastModified))
        } else {
            textTableRowId = try indexDb.run(textTable
                .insert(DB.domainRow <- id,
                        DB.urlRow <- url,
                        DB.titleRow <- content.title,
                        DB.descriptionRow <- content.description,
                        DB.contentRow <- content.condensedContent,
                        DB.keywordRow <- content.keywords,
                        DB.thumbnailUrlRow <- content.thumbnailUrl,
                        DB.lastModifiedRow <- content.lastModified))
        }
        if let sparseContent = content.sparseContent ?? content.title, sparseContent.isPopulated,
           let document = content.condensedContent ?? content.title ?? content.description,
           let embeddingResult = await Embedding.vector(for: document, rowId: textTableRowId) {
            try documentIndex.insert(embeddingResult)
            Log.crawling(id, .info).log("Added document embedding for '\(content.title ?? "<no title>")', rowId: \(embeddingResult.rowId)")
        }
        return textTableRowId
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

    func searchQuery(_ text: String, limit: Int) async throws -> (items: [Search.Result], count: Int) {
        let start = Date.now
        defer {
            Log.search(.info).log("Search query time: \(-start.timeIntervalSinceNow) sec")
        }

        let searchTerms = text.split(separator: " ").map { String($0) }
        let terms = searchTerms.map { $0.lowercased().sqlSafe }.joined(separator: " ")
        let query = searchTerms.count == 1 ? terms : "NEAR(\(terms))"
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

            where text_search match '\(query)' and rank match 'bm25(0, 0, 10, 0, 100)'

            order by rank, lastModified desc

            limit \(3000)
            """))

        guard let searchVector = await Embedding.vector(for: text) else {
            let res = elements.map {
                Search.Result(element: $0, terms: searchTerms, relevantVector: nil)
            }
            return (res, res.count)
        }

        let rowIds = Set(elements.map { $0[DB.rowId] })

        let vectorLookup = [Int64: Vector](uniqueKeysWithValues: documentIndex.filter {
            rowIds.contains($0.rowId)
        }.map {
            ($0.rowId, $0)
        })

        let results = elements
            .map { Search.Result(element: $0, terms: searchTerms, relevantVector: vectorLookup[$0[DB.rowId]]) }
            .uniqued { $0.titleHashValueForResults }
            .uniqued { $0.bodyHashValueForResults }

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

        let res = results.max(count: limit) { e1, e2 in
            guard let v1 = vectorLookup[e1.rowId] else {
                Log.search(.error).log("Could not find an embedding for document '\(e1.title)', at rowId \(e1.rowId)")
                return false
            }
            var R1: Float = 0
            withUnsafePointer(to: v1.coords) { _ = memcpy(comparisonBytes, $0, 2048) }
            vDSP_dotpr(searchCoordsBuffer, 1, comparisonBuffer, 1, &R1, 512)
            R1 /= (v1.magnitude * searchVectorMagnitude)
            let d1 = e1.displayDate ?? .distantPast

            guard let v2 = vectorLookup[e2.rowId] else {
                Log.search(.error).log("Could not find an embedding for document '\(e2.title)', at rowId \(e2.rowId)")
                return false
            }
            var R2: Float = 0
            withUnsafePointer(to: v2.coords) { _ = memcpy(comparisonBytes, $0, 2048) }
            vDSP_dotpr(searchCoordsBuffer, 1, comparisonBuffer, 1, &R2, 512)
            R2 /= (v2.magnitude * searchVectorMagnitude)
            let d2 = e2.displayDate ?? .distantPast

            if d1 < d2 {
                R2 += 0.01
            } else if d1 > d2 {
                R1 += 0.01
            }

            return R1 < R2
        }

        return (res, min(1000, results.count))
    }
}
