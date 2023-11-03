import Foundation
import SQLite

private struct TableWrapper: Equatable {
    private let id = UUID()
    private let table: Table
    private var cachedCount: Int?

    init(table: Table, in db: Connection) throws {
        self.table = table
        cachedCount = nil
        try create(in: db)
    }

    func next(in db: Connection) throws -> Row? {
        try db.pluck(table)
    }

    mutating func append(item: IndexEntry, in db: Connection) throws {
        switch item {
        case let .pending(url, isSitemap):
            try db.run(table.insert(or: .replace, DB.urlRow <- url, DB.isSitemapRow <- isSitemap))
        case let .visited(url, lastModified, etag):
            try db.run(table.insert(or: .replace, DB.urlRow <- url, DB.lastModifiedRow <- lastModified, DB.etagRow <- etag))
        }
        cachedCount = nil
    }

    mutating func append(items: any Collection<IndexEntry>, in db: Connection) throws {
        let setters = items.map {
            switch $0 {
            case let .pending(url, isSitemap):
                [DB.urlRow <- url, DB.isSitemapRow <- isSitemap]
            case let .visited(url, lastModified, etag):
                [DB.urlRow <- url, DB.lastModifiedRow <- lastModified, DB.etagRow <- etag]
            }
        }
        try db.run(table.insertMany(or: .ignore, setters))
        cachedCount = nil
    }

    mutating func delete(url: String, in db: Connection) throws {
        try db.run(table.filter(DB.urlRow == url).delete())
        cachedCount = nil
    }

    private func create(in db: Connection) throws {
        try db.run(table.create(ifNotExists: true) {
            $0.column(DB.urlRow, primaryKey: true)
            $0.column(DB.isSitemapRow)
            $0.column(DB.lastModifiedRow)
            $0.column(DB.etagRow)
        })
        try db.run(table.createIndex(DB.urlRow, unique: true, ifNotExists: true))
    }

    mutating func subtract(from items: inout Set<IndexEntry>, in db: Connection) throws {
        let array = items.map(\.url)
        if array.isPopulated {
            let itemsToSubtract = try db.prepare(table.select([DB.urlRow]).filter(array.contains(DB.urlRow)))
                .map { IndexEntry.pending(url: $0[DB.urlRow], isSitemap: false) }
            items.subtract(itemsToSubtract)
        }
    }

    mutating func subtract(_ otherTable: TableWrapper, in db: Connection) throws {
        let urlsToSubtract = try db.prepare(otherTable.table).map { $0[DB.urlRow] }
        if urlsToSubtract.isPopulated {
            let pendingWithUrl = table.filter(urlsToSubtract.contains(DB.urlRow))
            try db.run(pendingWithUrl.delete())
            cachedCount = nil
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    mutating func count(in db: Connection?) throws -> Int {
        if let cachedCount {
            return cachedCount
        } else if let db {
            let result = try db.scalar(table.count)
            cachedCount = result
            return result
        } else {
            return 0
        }
    }

    mutating func clear(purge: Bool, in db: Connection) throws {
        if purge {
            try db.run(table.drop(ifExists: true))
        } else {
            try db.run(table.delete())
        }
        cachedCount = nil
    }

    mutating func cloneAndClear(as newName: TableWrapper, in db: Connection) throws {
        try db.run(table.rename(newName.table))
        try create(in: db)
        cachedCount = nil
    }
}

final class CrawlerStorage {
    private let id: String
    private var pending: TableWrapper
    private var visited: TableWrapper
    private var db: Connection?

    init(id: String) throws {
        self.id = id

        let path = domainPath(for: id)
        let file = path.appending(path: "crawler.sqlite3", directoryHint: .notDirectory)
        let fm = FileManager.default
        if !fm.fileExists(atPath: path.path) {
            try fm.createDirectory(atPath: path.path, withIntermediateDirectories: true)
        }
        let c = try Connection(file.path)
        try c.run(DB.pragmas)
        db = c

        let tableId = id.replacingOccurrences(of: ".", with: "_")

        let pendingTable = Table("pending_\(tableId)")
        pending = try TableWrapper(table: pendingTable, in: c)

        let visitedTable = Table("visited_\(tableId)")
        visited = try TableWrapper(table: visitedTable, in: c)
    }

    var counts: (indexed: Int, pending: Int) {
        get throws {
            try (visited.count(in: db), pending.count(in: db))
        }
    }

    func removeAll(purge: Bool) async throws {
        if let db {
            try visited.clear(purge: purge, in: db)
            try pending.clear(purge: purge, in: db)
        }
        try await SearchDB.shared.purgeDomain(id: id)
        if purge {
            db = nil
        }
    }

    func prepareForRefresh() throws {
        guard let db else { return }
        try pending.clear(purge: true, in: db)
        try visited.cloneAndClear(as: pending, in: db)
    }

    func nextPending() async throws -> IndexEntry? {
        guard let db, let res = try pending.next(in: db) else {
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

    func handleCrawlCompletion(newItem: IndexEntry?, url: String, content: IndexEntry.Content?, newEntries: Set<IndexEntry>?) async throws {
        guard let db else { return }
        try pending.delete(url: url, in: db)

        let indexTask = Task { [id] in
            if let content {
                try await SearchDB.shared.insert(id: id, url: url, content: content)
            }
        }

        if let newItem {
            try visited.append(item: newItem, in: db)

            Log.crawling(id, .info).log("Visited URL: \(newItem.url)")
        }

        if var newEntries, newEntries.isPopulated {
            try visited.subtract(from: &newEntries, in: db)
            if newEntries.isPopulated {
                Log.crawling(id, .default).log("Adding \(newEntries.count) unindexed URLs to pending")
                try appendPending(items: newEntries)
            }
        }

        try await indexTask.value
    }

    func appendPending(_ item: IndexEntry) throws {
        guard let db else { return }
        try pending.append(item: item, in: db)
        try visited.delete(url: item.url, in: db)
    }

    func appendPending(items: any Collection<IndexEntry>) throws {
        guard let db, items.isPopulated else {
            return
        }
        try pending.append(items: items, in: db)
    }

    func handleSitemapEntries(from url: String, newSitemaps: Set<IndexEntry>) throws {
        guard let db else { return }
        try pending.delete(url: url, in: db)

        var newSitemaps = newSitemaps

        if newSitemaps.isPopulated {
            newSitemaps.remove(url.stubIndexEntry)
            try visited.subtract(from: &newSitemaps, in: db)
        }

        if newSitemaps.isPopulated {
            Log.crawling(id, .default).log("Adding \(newSitemaps.count) unindexed URLs from sitemap")
            try appendPending(items: newSitemaps)
        }
    }

    func substractIndexedFromPending() throws {
        guard let db else { return }
        try pending.subtract(visited, in: db)
    }
}

extension String {
    var stubIndexEntry: IndexEntry {
        IndexEntry.pending(url: self, isSitemap: false)
    }
}
