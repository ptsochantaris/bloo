import Foundation
import SQLite

struct CrawlerStorage {
    private let db: Connection
    private let pendingTable = Table("pending")
    private let visitedTable = Table("visited")
    private let urlRow = Expression<String>("url")
    private let isSitemapRow = Expression<Bool?>("isSitemap")
    private let lastModifiedRow = Expression<Date?>("lastModified")
    private let etagRow = Expression<String?>("etag")

    init(in path: URL) throws {
        if !FileManager.default.fileExists(atPath: path.path) {
            try! FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        }
        let file = path.appending(path: "db.sqlite3", directoryHint: .notDirectory)
        db = try Connection()
        try db.attach(.uri(file.path, parameters: []), as: "db")

        try db.run("""
                    pragma synchronous = off;
                    pragma temp_store = memory;
        """)

        try db.vacuum()

        try createPendingTable()

        try createIndexedTable()
    }

    private func createPendingTable() throws {
        try db.run(pendingTable.create(ifNotExists: true) {
            $0.column(urlRow, primaryKey: true)
            $0.column(isSitemapRow)
            $0.column(lastModifiedRow)
            $0.column(etagRow)
        })
    }

    private func createIndexedTable() throws {
        try db.run(visitedTable.create(ifNotExists: true) {
            $0.column(urlRow, primaryKey: true)
            $0.column(isSitemapRow)
            $0.column(lastModifiedRow)
            $0.column(etagRow)
        })
    }

    func shutdown() throws {
        try db.detach("db")
    }

    func removeAll() throws {
        try db.run(visitedTable.delete())
        try db.run(pendingTable.delete())
    }

    var indexedCount: Int {
        get throws {
            try db.scalar(visitedTable.count)
        }
    }

    var pendingCount: Int {
        get throws {
            try db.scalar(pendingTable.count)
        }
    }

    func prepareForRefresh() throws {
        try db.run(pendingTable.drop(ifExists: true))
        try db.run(visitedTable.rename(pendingTable))
        try createIndexedTable()
    }

    var noPending: Bool {
        get throws {
            try pendingCount == 0
        }
    }

    var noIndexed: Bool {
        get throws {
            try indexedCount == 0
        }
    }

    func nextPending() throws -> IndexEntry? {
        guard let res = try db.pluck(pendingTable) else {
            return nil
        }
        let url = res[urlRow]
        let isSitemap = res[isSitemapRow] ?? false
        let result: IndexEntry
        let lastModified = res[lastModifiedRow]
        let etag = res[etagRow]
        if let etag {
            result = .visited(url: url, lastModified: lastModified, etag: etag)
        } else if let lastModified {
            result = .visited(url: url, lastModified: lastModified, etag: etag)
        } else {
            result = .pending(url: url, isSitemap: isSitemap)
        }
        return result
    }

    private func append(item: IndexEntry, to table: Table) throws {
        switch item {
        case let .pending(url, isSitemap):
            try db.run(table.insert(or: .replace, urlRow <- url, isSitemapRow <- isSitemap))
        case let .visited(url, lastModified, etag):
            try db.run(table.insert(or: .replace, urlRow <- url, lastModifiedRow <- lastModified, etagRow <- etag))
        }
    }

    private func delete(item: IndexEntry, from table: Table) throws {
        try db.run(table.filter(urlRow == item.url).delete())
    }

    func deletePending(_ item: IndexEntry) throws {
        try delete(item: item, from: pendingTable)
    }

    func appendIndexed(_ item: IndexEntry) throws {
        try append(item: item, to: visitedTable)
        try delete(item: item, from: pendingTable)
    }

    func appendPending(_ item: IndexEntry) throws {
        try append(item: item, to: pendingTable)
        try delete(item: item, from: visitedTable)
    }

    func appendPending(_ items: any Collection<IndexEntry>) throws {
        guard items.isPopulated else {
            return
        }

        let setters = items.map {
            switch $0 {
            case let .pending(url, isSitemap):
                return [urlRow <- url, isSitemapRow <- isSitemap]
            case let .visited(url, lastModified, etag):
                return [urlRow <- url, lastModifiedRow <- lastModified, etagRow <- etag]
            }
        }
        try db.run(pendingTable.insertMany(or: .replace, setters))
    }

    private func subtract(from items: inout Set<IndexEntry>, in table: Table) throws {
        let array = items.map { $0.url }
        if array.isPopulated {
            let itemsToSubtract = try db.prepare(table.filter(array.contains(urlRow))).map { IndexEntry.pending(url: $0[urlRow], isSitemap: false) }
            items.subtract(itemsToSubtract)
        }
    }

    func subtractIndexed(from items: inout Set<IndexEntry>) throws {
        try subtract(from: &items, in: visitedTable)
    }

    func subtractPending(from items: inout Set<IndexEntry>) throws {
        try subtract(from: &items, in: pendingTable)
    }

    func substractIndexedFromPending() throws {
        let urlsToSubtract = try db.prepare(visitedTable).map { $0[urlRow] }
        if urlsToSubtract.isPopulated {
            let pendingWithUrl = pendingTable.filter(urlsToSubtract.contains(urlRow))
            try db.run(pendingWithUrl.delete())
        }
    }
}
