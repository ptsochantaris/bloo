import Accelerate
import AkashicTable
import Algorithms
import Foundation
import SQLite

final actor SearchDB {
    static let shared = try! SearchDB()

    private let textTable = VirtualTable("text_search")
    private let indexDb: Connection

    private let documentIndex: AkashicTable<Vector>

    init() throws {
        let file = documentsPath.appending(path: "index.sqlite3")
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

        let embeddingPath = documentsPath.appending(path: "doc.embeddings", directoryHint: .notDirectory).path
        documentIndex = try AkashicTable(at: embeddingPath, minimumCapacity: 10000, validateOrder: false)

        Log.search(.info).log("Loaded document index with \(documentIndex.count) entries")
    }

    func pause() {
        documentIndex.shutdown()
        Log.search(.default).log("Search DB paused")
    }

    func resume() throws {
        try documentIndex.resume()
    }

    func shutdown() {
        documentIndex.shutdown()
        Log.search(.default).log("Search DB shut down")
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
            try documentIndex.append(embeddingResult)
            Log.crawling(id, .info).log("Added document embedding for '\(content.title ?? "<no title>")', rowId: \(embeddingResult.rowId)")
        }
        return textTableRowId
    }

    func purgeDomain(id: String) throws {
        Log.crawling(id, .info).log("Purging domain of embeddings from \(id)")

        let associatedRows = try indexDb.prepare(textTable.select(DB.rowId).filter(DB.domainRow == id))

        let ids = try Set(associatedRows.map { associatedRow in
            try associatedRow.get(DB.rowId)
        })

        documentIndex.deleteEntries(with: ids)

        try indexDb.run(textTable.filter(DB.domainRow == id).delete())
    }

    func searchQuery(_ text: String, limit: Int) async throws -> [Search.Result] {
        let start = Date.now
        defer {
            Log.search(.info).log("Search query time: \(-start.timeIntervalSinceNow) sec")
        }

        let searchTerms = text.split(separator: " ").map { String($0) }
        let terms = searchTerms.map { $0.lowercased().sqlSafe }.joined(separator: " ")
        let query = searchTerms.count == 1 ? terms : "NEAR(\(terms), 0)"
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

            order by rank desc

            limit \(10000)
            """))

        guard let searchVector = await Embedding.vector(for: text) else {
            return elements.map {
                Search.Result(element: $0, terms: searchTerms)
            }
        }

        var rowIds = Set(elements.map { $0[DB.rowId] })
        Log.search(.info).log("Sifting through \(rowIds.count) DB suggestions")

        let vectorLookup = [Int64: Vector](uniqueKeysWithValues: documentIndex.filter {
            rowIds.remove($0.rowId) != nil // using "remove" in case there are duplicates
        }.map {
            ($0.rowId, $0)
        })

        let searchVectorMagnitude = searchVector.magnitude
        let searchVectorAccelBuffer = searchVector.accelerateBuffer

        return elements
            .map { Search.Result(element: $0, terms: searchTerms) }
            .uniqued { $0.titleHashValueForResults }
            .uniqued { $0.bodyHashValueForResults }
            .max(count: limit) { e1, e2 in
                guard let v1 = vectorLookup[e1.rowId] else {
                    Log.search(.error).log("Could not find an embedding for document '\(e1.title)', at rowId \(e1.rowId)")
                    return false
                }

                guard let v2 = vectorLookup[e2.rowId] else {
                    Log.search(.error).log("Could not find an embedding for document '\(e2.title)', at rowId \(e2.rowId)")
                    return false
                }

                let d1 = e1.displayDate ?? .distantPast
                let d2 = e2.displayDate ?? .distantPast
                let ms1 = v1.magnitude * searchVectorMagnitude
                let ms2 = v2.magnitude * searchVectorMagnitude
                let a1 = v1.accelerateBuffer
                let a2 = v2.accelerateBuffer
                let R1 = vDSP.dot(searchVectorAccelBuffer, a1) / ms1
                let R2 = vDSP.dot(searchVectorAccelBuffer, a2) / ms2

                if d1 < d2 {
                    return R1 < (R2 + 0.1)

                } else if d1 > d2 {
                    return (R1 + 0.1) < R2

                } else {
                    return R1 < R2
                }
            }
    }
}
