import Foundation
import SQLite

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
        try! c.run(DB.pragmas)
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
            $0.column(DB.urlRow, primaryKey: true)
            $0.column(DB.isSitemapRow)
            $0.column(DB.lastModifiedRow)
            $0.column(DB.etagRow)
        })
        try db.run(pending.table.createIndex(DB.urlRow, unique: true, ifNotExists: true))
    }

    private func createIndexedTable() throws {
        try db.run(visited.table.create(ifNotExists: true) {
            $0.column(DB.urlRow, primaryKey: true)
            $0.column(DB.isSitemapRow)
            $0.column(DB.lastModifiedRow)
            $0.column(DB.etagRow)
        })
        try db.run(visited.table.createIndex(DB.urlRow, unique: true, ifNotExists: true))
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
        let url = res[DB.urlRow]
        let isSitemap = res[DB.isSitemapRow] ?? false
        let etag = res[DB.etagRow]
        let lastModified = res[DB.lastModifiedRow]

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
            try db.run(table.table.insert(or: .replace, DB.urlRow <- url, DB.isSitemapRow <- isSitemap))
        case let .visited(url, lastModified, etag):
            try db.run(table.table.insert(or: .replace, DB.urlRow <- url, DB.lastModifiedRow <- lastModified, DB.etagRow <- etag))
        }
        table.cachedCount = nil
    }

    private func delete(url: String, from table: inout TableWrapper) throws {
        try db.run(table.table.filter(DB.urlRow == url).delete())
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
                [DB.urlRow <- url, DB.isSitemapRow <- isSitemap]
            case let .visited(url, lastModified, etag):
                [DB.urlRow <- url, DB.lastModifiedRow <- lastModified, DB.etagRow <- etag]
            }
        }
        try db.run(pending.table.insertMany(or: .ignore, setters))
        pending.cachedCount = nil
    }

    private func subtract(from items: inout Set<IndexEntry>, in table: TableWrapper) throws {
        let array = items.map(\.url)
        if array.isPopulated {
            let itemsToSubtract = try db.prepare(table.table.select([DB.urlRow]).filter(array.contains(DB.urlRow))).map { IndexEntry.pending(url: $0[DB.urlRow], isSitemap: false) }
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
        let urlsToSubtract = try db.prepare(visited.table).map { $0[DB.urlRow] }
        if urlsToSubtract.isPopulated {
            let pendingWithUrl = pending.table.filter(urlsToSubtract.contains(DB.urlRow))
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
