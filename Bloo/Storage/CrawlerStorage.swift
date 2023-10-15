import Foundation
import SQLite

struct CrawlerStorage {
    private static let db = {
        let file = documentsPath.appending(path: "content.sqlite3", directoryHint: .notDirectory)
        let fm = FileManager.default
        if !fm.fileExists(atPath: documentsPath.path) {
            try! fm.createDirectory(atPath: documentsPath.path, withIntermediateDirectories: true)
        }
        let c = try! Connection(file.path)
        try! c.run("""
                    pragma synchronous = off;
                    pragma temp_store = memory;
                    pragma journal_mode = WAL;
        """)
        return c
    }()

    private static let urlRow = Expression<String>("url")
    private static let isSitemapRow = Expression<Bool?>("isSitemap")
    private static let lastModifiedRow = Expression<Date?>("lastModified")
    private static let etagRow = Expression<String?>("etag")
    private static let contentRow = Expression<String?>("content")
    private static let descriptionRow = Expression<String?>("description")

    private let pendingTable: Table
    private let visitedTable: Table

    init(id: String) throws {
        let tableId = id.replacingOccurrences(of: ".", with: "_")
        pendingTable = Table("pending_\(tableId)")
        visitedTable = Table("visited_\(tableId)")

        try createPendingTable()

        try createIndexedTable()
    }

    private func createPendingTable() throws {
        try Self.db.run(pendingTable.create(ifNotExists: true) {
            $0.column(Self.urlRow, primaryKey: true)
            $0.column(Self.isSitemapRow)
            $0.column(Self.lastModifiedRow)
            $0.column(Self.etagRow)
            $0.column(Self.descriptionRow)
            $0.column(Self.contentRow)
        })
    }

    private func createIndexedTable() throws {
        try Self.db.run(visitedTable.create(ifNotExists: true) {
            $0.column(Self.urlRow, primaryKey: true)
            $0.column(Self.isSitemapRow)
            $0.column(Self.lastModifiedRow)
            $0.column(Self.etagRow)
            $0.column(Self.descriptionRow)
            $0.column(Self.contentRow)
        })
    }

    func removeAll(purge: Bool) throws {
        if purge {
            try Self.db.run(visitedTable.drop(ifExists: true))
            try Self.db.run(pendingTable.drop(ifExists: true))
        } else {
            try Self.db.run(visitedTable.delete())
            try Self.db.run(pendingTable.delete())
        }
    }

    var indexedCount: Int {
        get throws {
            try Self.db.scalar(visitedTable.count)
        }
    }

    var pendingCount: Int {
        get throws {
            try Self.db.scalar(pendingTable.count)
        }
    }

    func prepareForRefresh() throws {
        try Self.db.run(pendingTable.drop(ifExists: true))
        try Self.db.run(visitedTable.rename(pendingTable))
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
        guard let res = try Self.db.pluck(pendingTable) else {
            return nil
        }
        let url = res[Self.urlRow]
        let isSitemap = res[Self.isSitemapRow] ?? false
        let result: IndexEntry
        let lastModified = res[Self.lastModifiedRow]
        let etag = res[Self.etagRow]
        let desc = res[Self.descriptionRow]
        let content = res[Self.contentRow]
        if etag != nil || lastModified != nil || desc != nil || content != nil {
            result = .visited(url: url, lastModified: lastModified, etag: etag, description: desc, content: content)
        } else {
            result = .pending(url: url, isSitemap: isSitemap)
        }
        return result
    }

    private func append(item: IndexEntry, to table: Table) throws {
        switch item {
        case let .pending(url, isSitemap):
            try Self.db.run(table.insert(or: .replace, Self.urlRow <- url, Self.isSitemapRow <- isSitemap))
        case let .visited(url, lastModified, etag, desc, content):
            try Self.db.run(table.insert(or: .replace, Self.urlRow <- url, Self.lastModifiedRow <- lastModified, Self.etagRow <- etag, Self.descriptionRow <- desc, Self.contentRow <- content))
        }
    }

    private func delete(item: IndexEntry, from table: Table) throws {
        try Self.db.run(table.filter(Self.urlRow == item.url).delete())
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
                [Self.urlRow <- url, Self.isSitemapRow <- isSitemap]
            case let .visited(url, lastModified, etag, desc, content):
                [Self.urlRow <- url, Self.lastModifiedRow <- lastModified, Self.etagRow <- etag, Self.descriptionRow <- desc, Self.contentRow <- content]
            }
        }
        try Self.db.run(pendingTable.insertMany(or: .replace, setters))
    }

    private func subtract(from items: inout Set<IndexEntry>, in table: Table) throws {
        let array = items.map(\.url)
        if array.isPopulated {
            let itemsToSubtract = try Self.db.prepare(table.filter(array.contains(Self.urlRow))).map { IndexEntry.pending(url: $0[Self.urlRow], isSitemap: false) }
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
        let urlsToSubtract = try Self.db.prepare(visitedTable).map { $0[Self.urlRow] }
        if urlsToSubtract.isPopulated {
            let pendingWithUrl = pendingTable.filter(urlsToSubtract.contains(Self.urlRow))
            try Self.db.run(pendingWithUrl.delete())
        }
    }
}
