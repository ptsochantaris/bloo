import Accelerate
import Algorithms
import Foundation
import SQLite

final actor SearchDB {
    static let shared = SearchDB()

    private let textTable = VirtualTable("text_search")
    private var vectorIndex: MemoryMappedCollection<Vector>
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
        Log.search(.info).log("Loaded search indexes with \(vectorIndex.count) entries")
    }

    func shutdown() {
        vectorIndex.shutdown()
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

        // free this actor up while we produce the vectors
        let embedSentences = Task<[Vector], Never>.detached {
            let sentences = await SentenceEmbedding.sentences(for: sparseContent, titled: content.title)

            guard sentences.isPopulated else {
                return []
            }

            let res = await SentenceEmbedding.vectors(for: sentences, at: newRowId)
            #if DEBUG
                for vector in res {
                    Log.search(.debug).log("Adding vector: [\(vector.sentence)]")
                }
            #endif
            return res
        }

        let newVectors = await embedSentences.value
        vectorIndex.append(contentsOf: newVectors)
        Log.crawling(id, .info).log("Added \(newVectors.count) embeddings")
    }

    func purgeDomain(id: String) throws {
        var ids = Set<Int64>()
        for associatedRow in try indexDb.prepare(textTable.select(DB.rowId).filter(DB.domainRow == id)) {
            let i = try associatedRow.get(DB.rowId)
            ids.insert(i)
        }

        vectorIndex.deleteAll {
            ids.contains($0.rowId)
        }

        try indexDb.run(textTable.filter(DB.domainRow == id).delete())
    }

    func keywordQuery(_ text: String, limit: Int) throws -> [Search.Result] {
        let start = Date.now
        defer {
            Log.search(.info).log("Keyword search query time: \(-start.timeIntervalSinceNow) sec")
        }

        let searchTerms = text.split(separator: " ").map { String($0) }
        let terms = searchTerms.map { $0.lowercased().sqlSafe }.joined(separator: " AND ")
        return try indexDb.prepareRowIterator(
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

            limit \(limit)
            """).map {
            Search.Result(element: $0, terms: searchTerms, relevantVector: nil)
        }
    }

    func sentenceQuery(_ text: String, limit: Int) async throws -> [Search.Result] {
        let start = Date.now
        defer {
            Log.search(.info).log("Sentence search query time: \(-start.timeIntervalSinceNow) sec")
        }
        guard let searchVector = await SentenceEmbedding.vector(for: text) else {
            return []
        }

        let searchVectorSumOfSquares = searchVector.sumOfSquares
        let buf = malloc(4096)!
        defer { free(buf) }
        withUnsafePointer(to: searchVector.coords) { _ = memcpy(buf, $0, 4096) }
        let searchCoordsBuffer = buf.assumingMemoryBound(to: Double.self)

        let count = vectorIndex.count
        let shardLength = 1_000_000
        let shardCount = Int((Double(count) / Double(shardLength)).rounded(.up))
        let resultSequence = AsyncStream { continuation in
            DispatchQueue.concurrentPerform(iterations: shardCount) { [vectorIndex] i in
                let shardStart = i * shardLength
                let shardEnd = min(shardStart + shardLength, count)

                let buf = malloc(4096)!
                defer { free(buf) }
                let B = buf.assumingMemoryBound(to: Double.self)

                let block = vectorIndex[shardStart ..< shardEnd].max(count: limit) { @Sendable (e1: Vector, e2: Vector) -> Bool in
                    var R: Double = 0
                    withUnsafePointer(to: e1.coords) { _ = memcpy(buf, $0, 4096) }
                    vDSP_dotprD(searchCoordsBuffer, 1, B, 1, &R, 512)
                    R /= (e1.sumOfSquares * searchVectorSumOfSquares)
                    let R0 = R

                    withUnsafePointer(to: e2.coords) { _ = memcpy(buf, $0, 4096) }
                    vDSP_dotprD(searchCoordsBuffer, 1, B, 1, &R, 512)
                    R /= (e2.sumOfSquares * searchVectorSumOfSquares)

                    return R0 < R
                }
                Log.search(.info).log("Scanned shard \(shardStart) to \(shardEnd); \(block.count) vectors match")
                continuation.yield(block)
            }
            continuation.finish()
        }

        var res = [Vector]()
        res.reserveCapacity(shardCount * limit)
        for await chunk in resultSequence {
            res.append(contentsOf: chunk)
        }

        if res.isEmpty {
            return []
        }

        let buf2 = malloc(4096)!
        defer { free(buf2) }
        let B2 = buf2.assumingMemoryBound(to: Double.self)
        let comparator2 = { @Sendable (e1: Vector, e2: Vector) -> Bool in
            var R: Double = 0
            withUnsafePointer(to: e1.coords) { _ = memcpy(buf, $0, 4096) }
            vDSP_dotprD(searchCoordsBuffer, 1, B2, 1, &R, 512)
            R /= (e1.sumOfSquares * searchVectorSumOfSquares)
            if e1.sentence.localizedCaseInsensitiveContains(text) {
                R += 1
            }
            let R0 = R

            withUnsafePointer(to: e2.coords) { _ = memcpy(buf, $0, 4096) }
            vDSP_dotprD(searchCoordsBuffer, 1, B2, 1, &R, 512)
            R /= (e2.sumOfSquares * searchVectorSumOfSquares)
            if e2.sentence.localizedCaseInsensitiveContains(text) {
                R += 1
            }
            return R0 < R
        }

        let vectors = res
            .uniqued { $0.rowId }
            .max(count: limit, sortedBy: comparator2)

        Log.search(.info).log("Total \(vectors.count) vectors match")

        let idList = vectors.map(\.rowId)
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
        ).compactMap { element in
            let id = element[DB.rowId]
            if let v = vectors.first(where: { $0.rowId == id }) {
                return (v, element)
            } else {
                return nil
            }
        }.sorted {
            let pos1 = idList.firstIndex(of: $0.0.rowId) ?? 0
            let pos2 = idList.firstIndex(of: $1.0.rowId) ?? 0
            return pos1 > pos2

        }.map { (relevantVector: Vector, element: RowIterator.Element) in
            withUnsafePointer(to: relevantVector.coords) { coordPointer in
                // let vb = UnsafeBufferPointer(start: UnsafePointer<Double>(OpaquePointer(coordPointer)), count: 512)
                // let score = vDSP.dot(searchCoordsBuffer, vb) / (relevantVector.sumOfSquares * searchVectorSumOfSquares) * 1000
                // print(">>> \(relevantVector.sentence) - \(score)")
                return Search.Result(element: element, terms: termList, relevantVector: relevantVector)
            }

        }.uniqued { $0.url.normalisedUrlForResults() }
    }
}
