import Accelerate
import Algorithms
import BlooLib
import Foundation
import SQLite

final actor SearchDB {
    static let shared = try! SearchDB()

    private let textTable = VirtualTable("text_search")
    private let indexDb: Connection

    private let documentIndex: MemoryMappedCollection<Vector>

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
        documentIndex = try MemoryMappedCollection(at: embeddingPath, minimumCapacity: 10000, validateOrder: true)

        Log.search(.info).log("Loaded document index with \(documentIndex.count) entries")
    }

    func pause() {
        documentIndex.pause()
    }

    func resume() throws {
        try documentIndex.resume()
    }

    func shutdown() {
        documentIndex.shutdown()
    }

    func insert(id: String, url: String, content: IndexEntry.Content, existingRowId: Int64?) async throws -> Int64? {
        let textBlocks = content.textBlocks

        guard let embeddingResult = await Embedding.vector(for: textBlocks)?.map({ Float($0) }) else {
            return nil
        }

        let textTableRowId: Int64

        if let existingRowId {
            textTableRowId = existingRowId

            Log.crawling(id, .info).log("Replacing document embedding for '\(content.title ?? "<no title>")', rowId: \(existingRowId)")

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

            Log.crawling(id, .info).log("Adding document embedding for '\(content.title ?? "<no title>")', rowId: \(textTableRowId)")
        }

        let vector = Vector(coordVector: embeddingResult, rowId: textTableRowId)
        try documentIndex.insert(vector)

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
            Log.search(.info).log("Search query time for '\(text)': \(-start.timeIntervalSinceNow) sec")
        }

        let vectorLimit = min(limit, documentIndex.count)
        guard vectorLimit > 0, let searchVectorFloats = await Embedding.vector(for: text)?.map({ Float($0) }) else {
            return []
        }

        let searchVector = Vector(coordVector: searchVectorFloats, rowId: 0)
        let searchVectorMagnitude = searchVector.magnitude
        let searchVectorAccelBuffer = searchVector.accelerateBuffer
        let idList = documentIndex
            .min(count: vectorLimit) { v1, v2 in
                let R1 = Embedding.distance(between: v1.accelerateBuffer, firstMagnitude: v1.magnitude, and: searchVectorAccelBuffer, secondMagnitude: searchVectorMagnitude)
                let R2 = Embedding.distance(between: v2.accelerateBuffer, firstMagnitude: v2.magnitude, and: searchVectorAccelBuffer, secondMagnitude: searchVectorMagnitude)
                return R1 < R2
            }
            .map { String($0.rowId) }
            .joined(separator: ",")

        let elements = try indexDb.prepareRowIterator(
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

            where rowid in (\(idList))
            """)

        let searchTerms = text.split(separator: " ").map { String($0) }

        return try elements
            .map { Search.Result(element: $0, terms: searchTerms) }
            .uniqued { $0.titleHashValueForResults }
            .uniqued { $0.bodyHashValueForResults }
            .sorted {
                let i1 = documentIndex.index(for: $0.rowId)!
                let v1 = documentIndex[i1]
                let R1 = Embedding.distance(between: v1.accelerateBuffer, firstMagnitude: v1.magnitude, and: searchVectorAccelBuffer, secondMagnitude: searchVectorMagnitude)

                let i2 = documentIndex.index(for: $1.rowId)!
                let v2 = documentIndex[i2]
                let R2 = Embedding.distance(between: v2.accelerateBuffer, firstMagnitude: v2.magnitude, and: searchVectorAccelBuffer, secondMagnitude: searchVectorMagnitude)

                return R1 < R2
            }.map {
                let i1 = documentIndex.index(for: $0.rowId)!
                let v1 = documentIndex[i1]
                let R1 = Embedding.distance(between: v1.accelerateBuffer, firstMagnitude: v1.magnitude, and: searchVectorAccelBuffer, secondMagnitude: searchVectorMagnitude)

                print($0.title, "distance", R1)
                return $0
            }
    }
}
