import Foundation
import SQLite

private let urlRow = Expression<String>("url")
private let isSitemapRow = Expression<Bool?>("isSitemap")
private let lastModifiedRow = Expression<Date?>("lastModified")
private let etagRow = Expression<String?>("etag")
private let thumbnailUrlRow = Expression<String?>("thumbnailUrl")

private let titleRow = Expression<String?>("title")
private let descriptionRow = Expression<String?>("description")
private let contentRow = Expression<String?>("content")
private let keywordRow = Expression<String?>("keywords")
private let domainRow = Expression<String>("domain")

private let pragmas = """
                        pragma synchronous = off;
                        pragma temp_store = memory;
                        pragma journal_mode = WAL;
                        pragma locking_mode = exclusive;
                        """

enum SearchDB {
    private static let textTable = VirtualTable("text_search")

    private static let indexDb = {
        let file = documentsPath.appending(path: "index.sqlite3", directoryHint: .notDirectory)
        let fm = FileManager.default
        if !fm.fileExists(atPath: documentsPath.path) {
            try! fm.createDirectory(atPath: documentsPath.path, withIntermediateDirectories: true)
        }
        let c = try! Connection(file.path)
        try! c.run(pragmas)

        let fts5Config = FTS5Config()
        fts5Config.column(domainRow, [.unindexed])
        fts5Config.column(urlRow, [.unindexed])
        fts5Config.column(titleRow)
        fts5Config.column(descriptionRow)
        fts5Config.column(contentRow)
        fts5Config.column(keywordRow)
        fts5Config.column(thumbnailUrlRow, [.unindexed])
        fts5Config.column(lastModifiedRow, [.unindexed])
        try! c.run(textTable.create(.FTS5(fts5Config), ifNotExists: true))

        return c
    }()

    static func insert(id: String, url: String, content: IndexEntry.Content) throws {
        try indexDb.run(textTable.insert(or: .replace,
                                         domainRow <- id,
                                         urlRow <- url,
                                         titleRow <- content.title,
                                         descriptionRow <- content.description,
                                         contentRow <- content.content,
                                         keywordRow <- content.keywords,
                                         thumbnailUrlRow <- content.thumbnailUrl,
                                         lastModifiedRow <- content.lastModified))
    }

    static func entry(for url: String) throws -> Row? {
        let tq = textTable.filter(urlRow == url)
        return try indexDb.pluck(tq)
    }

    static func purgeDomain(id: String) throws {
        try indexDb.run(textTable.filter(domainRow == id).delete())
    }

    static func textQuery(_ text: String, limit: Int) throws -> [Search.Result] {
        let searchTerms = text.split(separator: " ").map { String($0) }
        let terms = searchTerms.map { $0.lowercased().sqlSafe }.joined(separator: " AND ")
        let resultSequence = try indexDb.prepareRowIterator(
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
            """)
        var res = [Search.Result]()
        while let item = resultSequence.next() {
            let r = Search.Result(id: item[urlRow],
                                  title: item[titleRow] ?? "",
                                  descriptionText: item[descriptionRow] ?? "",
                                  contentText: item[contentRow],
                                  displayDate: item[lastModifiedRow],
                                  thumbnailUrl: URL(string: item[thumbnailUrlRow] ?? ""),
                                  keywords: (item[keywordRow]?.split(separator: ", ").map { String($0) }) ?? [],
                                  terms: searchTerms)
            res.append(r)
        }
        return res
    }
}

final class CrawlerStorage {
    private let id: String
    private let pendingTable: Table
    private let visitedTable: Table
    private let db: Connection

    private static func createDomainConnection(id: String) -> Connection {
        let path = domainPath(for: id)
        let file = path.appending(path: "crawler.sqlite3", directoryHint: .notDirectory)
        let fm = FileManager.default
        if !fm.fileExists(atPath: path.path) {
            try! fm.createDirectory(atPath: path.path, withIntermediateDirectories: true)
        }
        let c = try! Connection(file.path)
        try! c.run(pragmas)
        return c
    }

    init(id: String) throws {
        self.id = id

        self.db = Self.createDomainConnection(id: id)

        let tableId = id.replacingOccurrences(of: ".", with: "_")

        pendingTable = Table("pending_\(tableId)")
        visitedTable = Table("visited_\(tableId)")

        try createPendingTable()
        try createIndexedTable()
    }

    private var cachedIndexedCount: Int?
    private var cachedPendingCount: Int?
    var counts: (indexed: Int, pending: Int) {
        get throws {
            let indexedCount: Int
            if let cachedIndexedCount {
                indexedCount = cachedIndexedCount
            } else {
                indexedCount = try db.scalar(visitedTable.count)
                cachedIndexedCount = indexedCount
            }
            let pendingCount: Int
            if let cachedPendingCount {
                pendingCount = cachedPendingCount
            } else {
                pendingCount = try db.scalar(pendingTable.count)
                cachedPendingCount = pendingCount
            }
            return (indexedCount, pendingCount)
        }
    }

    private func createPendingTable() throws {
        try db.run(pendingTable.create(ifNotExists: true) {
            $0.column(urlRow, primaryKey: true)
            $0.column(isSitemapRow)
            $0.column(lastModifiedRow)
            $0.column(etagRow)
        })
        try db.run(pendingTable.createIndex(urlRow, unique: true, ifNotExists: true))
    }

    private func createIndexedTable() throws {
        try db.run(visitedTable.create(ifNotExists: true) {
            $0.column(urlRow, primaryKey: true)
            $0.column(isSitemapRow)
            $0.column(lastModifiedRow)
            $0.column(etagRow)
        })
        try db.run(visitedTable.createIndex(urlRow, unique: true, ifNotExists: true))
    }

    func removeAll(purge: Bool) throws {
        if purge {
            try db.run(visitedTable.drop(ifExists: true))
            try db.run(pendingTable.drop(ifExists: true))
        } else {
            try db.run(visitedTable.delete())
            try db.run(pendingTable.delete())
        }
        try SearchDB.purgeDomain(id: id)
        invalidateCounts()
    }

    func prepareForRefresh() throws {
        try db.run(pendingTable.drop(ifExists: true))
        try db.run(visitedTable.rename(pendingTable))
        try createIndexedTable()
        invalidateCounts()
    }

    private func invalidateCounts() {
        cachedIndexedCount = nil
        cachedPendingCount =  nil
    }

    func nextPending() throws -> IndexEntry? {
        guard let res = try db.pluck(pendingTable) else {
            return nil
        }
        let url = res[urlRow]
        let isSitemap = res[isSitemapRow] ?? false
        let etag = res[etagRow]
        let lastModified = res[lastModifiedRow]

        let textRes = try SearchDB.entry(for: url)
        let content = IndexEntry.Content(title: textRes?[titleRow],
                                         description: textRes?[descriptionRow],
                                         content: textRes?[contentRow],
                                         keywords: textRes?[keywordRow],
                                         thumbnailUrl: textRes?[thumbnailUrlRow],
                                         lastModified: textRes?[lastModifiedRow])

        let result: IndexEntry = if etag != nil || lastModified != nil || content.hasItems {
            .visited(url: url, lastModified: lastModified, etag: etag, content: content)
        } else {
            .pending(url: url, isSitemap: isSitemap)
        }
        return result
    }

    private func append(item: IndexEntry, to table: Table) throws {
        switch item {
        case let .pending(url, isSitemap):
            try db.run(table.insert(or: .replace, urlRow <- url, isSitemapRow <- isSitemap))
        case let .visited(url, lastModified, etag, content):
            try db.run(table.insert(or: .replace, urlRow <- url, lastModifiedRow <- lastModified, etagRow <- etag))
            try SearchDB.insert(id: id, url: url, content: content)
        }
    }

    private func delete(item: IndexEntry, from table: Table) throws {
        try db.run(table.filter(urlRow == item.url).delete())
    }

    func handleCrawlCompletion(newItem: IndexEntry?, previousItem: IndexEntry, newEntries: Set<IndexEntry>?) throws {
        // let start = Date.now
        try delete(item: previousItem, from: pendingTable)
        cachedPendingCount = nil

        if let newItem {
            try append(item: newItem, to: visitedTable)
            cachedIndexedCount = nil
            Log.crawling(id, .info).log("Indexed URL: \(newItem.url)")
        }

        if var newEntries, newEntries.isPopulated {
            try subtract(from: &newEntries, in: visitedTable)
            if newEntries.isPopulated {
                Log.crawling(id, .default).log("Adding \(newEntries.count) unindexed URLs to pending")
                try appendPending(items: newEntries)
            }
        }
        // print("crawl completion handling: \(-start.timeIntervalSinceNow * 1000)")
    }

    func appendPending(_ item: IndexEntry) throws {
        try append(item: item, to: pendingTable)
        try delete(item: item, from: visitedTable)
        invalidateCounts()
    }

    func appendPending(items: any Collection<IndexEntry>) throws {
        guard items.isPopulated else {
            return
        }

        let setters = items.map {
            switch $0 {
            case let .pending(url, isSitemap):
                [urlRow <- url, isSitemapRow <- isSitemap]
            case let .visited(url, lastModified, etag, _):
                [urlRow <- url, lastModifiedRow <- lastModified, etagRow <- etag]
            }
        }
        try db.run(pendingTable.insertMany(or: .ignore, setters))
        cachedPendingCount = nil
    }

    private func subtract(from items: inout Set<IndexEntry>, in table: Table) throws {
        let array = items.map(\.url)
        if array.isPopulated {
            let itemsToSubtract = try db.prepare(table.select([urlRow]).filter(array.contains(urlRow))).map { IndexEntry.pending(url: $0[urlRow], isSitemap: false) }
            items.subtract(itemsToSubtract)
        }
    }

    func handleSitemapEntries(from entry: IndexEntry, newSitemaps: Set<IndexEntry>) throws {
        try delete(item: entry, from: pendingTable)

        var newSitemaps = newSitemaps

        if newSitemaps.isPopulated {
            newSitemaps.remove(entry)
            try subtract(from: &newSitemaps, in: visitedTable)
        }

        if newSitemaps.isPopulated {
            Log.crawling(id, .default).log("Adding \(newSitemaps.count) unindexed URLs from sitemap")
            try appendPending(items: newSitemaps)
        }
    }

    func substractIndexedFromPending() throws {
        let urlsToSubtract = try db.prepare(visitedTable).map { $0[urlRow] }
        if urlsToSubtract.isPopulated {
            let pendingWithUrl = pendingTable.filter(urlsToSubtract.contains(urlRow))
            try db.run(pendingWithUrl.delete())
            cachedPendingCount = nil
        }
    }
}
