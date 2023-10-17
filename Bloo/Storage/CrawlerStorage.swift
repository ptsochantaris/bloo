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
pragma journal_mode = off;
pragma locking_mode = exclusive;
"""

final actor SearchDB {
    static let shared = SearchDB()

    private let textTable = VirtualTable("text_search")

    private let indexDb: Connection

    init() {
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

        indexDb = c
    }

    func insert(id: String, url: String, content: IndexEntry.Content) throws {
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

    func purgeDomain(id: String) throws {
        try indexDb.run(textTable.filter(domainRow == id).delete())
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
            Search.Result(id: $0[urlRow],
                          title: $0[titleRow] ?? "",
                          descriptionText: $0[descriptionRow] ?? "",
                          contentText: $0[contentRow],
                          displayDate: $0[lastModifiedRow],
                          thumbnailUrl: URL(string: $0[thumbnailUrlRow] ?? ""),
                          keywords: $0[keywordRow]?.split(separator: ", ").map { String($0) } ?? [],
                          terms: searchTerms)
        }
    }
}

final class CrawlerStorage {
    private let id: String
    private var pending: TableWrapper
    private var visited: TableWrapper
    private let db: Connection

    struct TableWrapper: Equatable {
        let id = UUID()
        let table: Table
        var cachedCount: Int?

        static func == (lhs: CrawlerStorage.TableWrapper, rhs: CrawlerStorage.TableWrapper) -> Bool {
            lhs.id == rhs.id
        }
    }

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

        db = Self.createDomainConnection(id: id)

        let tableId = id.replacingOccurrences(of: ".", with: "_")

        let pendingTable = Table("pending_\(tableId)")
        pending = TableWrapper(table: pendingTable)

        let visitedTable = Table("visited_\(tableId)")
        visited = TableWrapper(table: visitedTable)

        try createPendingTable()
        try createIndexedTable()
    }

    var counts: (indexed: Int, pending: Int) {
        get throws {
            let indexedCount: Int
            if let cachedIndexedCount = visited.cachedCount {
                indexedCount = cachedIndexedCount
            } else {
                indexedCount = try db.scalar(visited.table.count)
                visited.cachedCount = indexedCount
            }
            let pendingCount: Int
            if let cachedPendingCount = pending.cachedCount {
                pendingCount = cachedPendingCount
            } else {
                pendingCount = try db.scalar(pending.table.count)
                pending.cachedCount = pendingCount
            }
            return (indexedCount, pendingCount)
        }
    }

    private func createPendingTable() throws {
        try db.run(pending.table.create(ifNotExists: true) {
            $0.column(urlRow, primaryKey: true)
            $0.column(isSitemapRow)
            $0.column(lastModifiedRow)
            $0.column(etagRow)
        })
        try db.run(pending.table.createIndex(urlRow, unique: true, ifNotExists: true))
    }

    private func createIndexedTable() throws {
        try db.run(visited.table.create(ifNotExists: true) {
            $0.column(urlRow, primaryKey: true)
            $0.column(isSitemapRow)
            $0.column(lastModifiedRow)
            $0.column(etagRow)
        })
        try db.run(visited.table.createIndex(urlRow, unique: true, ifNotExists: true))
    }

    func removeAll(purge: Bool) async throws {
        if purge {
            try db.run(visited.table.drop(ifExists: true))
            try db.run(pending.table.drop(ifExists: true))
        } else {
            try db.run(visited.table.delete())
            try db.run(pending.table.delete())
        }
        try await SearchDB.shared.purgeDomain(id: id)
        pending.cachedCount = nil
        visited.cachedCount = nil
    }

    func prepareForRefresh() throws {
        try db.run(pending.table.drop(ifExists: true))
        pending.cachedCount = nil
        try db.run(visited.table.rename(pending.table))
        visited.cachedCount = nil
        try createIndexedTable()
    }

    func nextPending() async throws -> IndexEntry? {
        guard let res = try db.pluck(pending.table) else {
            return nil
        }
        let url = res[urlRow]
        let isSitemap = res[isSitemapRow] ?? false
        let etag = res[etagRow]
        let lastModified = res[lastModifiedRow]

        let result: IndexEntry = if etag != nil || lastModified != nil {
            .visited(url: url, lastModified: lastModified, etag: etag)
        } else {
            .pending(url: url, isSitemap: isSitemap)
        }
        return result
    }

    private func append(item: IndexEntry, to table: inout TableWrapper) async throws {
        switch item {
        case let .pending(url, isSitemap):
            try db.run(table.table.insert(or: .replace, urlRow <- url, isSitemapRow <- isSitemap))
        case let .visited(url, lastModified, etag):
            try db.run(table.table.insert(or: .replace, urlRow <- url, lastModifiedRow <- lastModified, etagRow <- etag))
        }
        table.cachedCount = nil
    }

    private func delete(url: String, from table: inout TableWrapper) throws {
        try db.run(table.table.filter(urlRow == url).delete())
        table.cachedCount = nil
    }

    func handleCrawlCompletion(newItem: IndexEntry?, url: String, content: IndexEntry.Content?, newEntries: Set<IndexEntry>?) async throws {
        /* let start = Date()
         defer {
             print("crawl completion: \(-start.timeIntervalSinceNow * 1000)")
         } */

        try delete(url: url, from: &pending)

        let indexTask = Task { [id] in
            if let content {
                try await SearchDB.shared.insert(id: id, url: url, content: content)
            }
        }

        if let newItem {
            try await append(item: newItem, to: &visited)

            Log.crawling(id, .info).log("Indexed URL: \(newItem.url)")
        }

        if var newEntries, newEntries.isPopulated {
            try subtract(from: &newEntries, in: visited)
            if newEntries.isPopulated {
                Log.crawling(id, .default).log("Adding \(newEntries.count) unindexed URLs to pending")
                try appendPending(items: newEntries)
            }
        }

        try await indexTask.value
    }

    func appendPending(_ item: IndexEntry) async throws {
        try await append(item: item, to: &pending)
        try delete(url: item.url, from: &visited)
    }

    func appendPending(items: any Collection<IndexEntry>) throws {
        guard items.isPopulated else {
            return
        }

        let setters = items.map {
            switch $0 {
            case let .pending(url, isSitemap):
                [urlRow <- url, isSitemapRow <- isSitemap]
            case let .visited(url, lastModified, etag):
                [urlRow <- url, lastModifiedRow <- lastModified, etagRow <- etag]
            }
        }
        try db.run(pending.table.insertMany(or: .ignore, setters))
        pending.cachedCount = nil
    }

    private func subtract(from items: inout Set<IndexEntry>, in table: TableWrapper) throws {
        let array = items.map(\.url)
        if array.isPopulated {
            let itemsToSubtract = try db.prepare(table.table.select([urlRow]).filter(array.contains(urlRow))).map { IndexEntry.pending(url: $0[urlRow], isSitemap: false) }
            items.subtract(itemsToSubtract)
        }
    }

    func handleSitemapEntries(from url: String, newSitemaps: Set<IndexEntry>) throws {
        try delete(url: url, from: &pending)

        var newSitemaps = newSitemaps

        if newSitemaps.isPopulated {
            newSitemaps.remove(url.stubIndexEntry)
            try subtract(from: &newSitemaps, in: visited)
        }

        if newSitemaps.isPopulated {
            Log.crawling(id, .default).log("Adding \(newSitemaps.count) unindexed URLs from sitemap")
            try appendPending(items: newSitemaps)
        }
    }

    func substractIndexedFromPending() throws {
        let urlsToSubtract = try db.prepare(visited.table).map { $0[urlRow] }
        if urlsToSubtract.isPopulated {
            let pendingWithUrl = pending.table.filter(urlsToSubtract.contains(urlRow))
            try db.run(pendingWithUrl.delete())
            pending.cachedCount = nil
        }
    }
}

extension String {
    var stubIndexEntry: IndexEntry {
        IndexEntry.pending(url: self, isSitemap: false)
    }
}
