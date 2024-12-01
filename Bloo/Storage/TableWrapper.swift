import Foundation
import SQLite

final class TableWrapper: Equatable {
    private let id = UUID()
    private let table: Table

    var cachedCount: Int?

    var count: ScalarQuery<Int> {
        table.count
    }

    init(table: Table, in db: Connection) throws {
        self.table = table
        cachedCount = nil
        try create(in: db)
    }

    func setCachedCount(_ newCount: Int) {
        cachedCount = newCount
    }

    func next(in db: Connection) throws -> Row? {
        try db.pluck(table)
    }

    private static func itemRowSetters(for item: IndexEntry) -> [Setter] {
        switch item {
        case let .pending(url, isSitemap, csIdentifier):
            [DB.urlRow <- url,
             DB.isSitemapRow <- isSitemap,
             DB.csIdentifier <- csIdentifier]

        case let .visited(url, lastModified, etag, csIdentifier):
            [DB.urlRow <- url,
             DB.lastModifiedRow <- lastModified,
             DB.etagRow <- etag,
             DB.csIdentifier <- csIdentifier]
        }
    }

    func append(item: IndexEntry, in db: Connection) throws {
        let totalChanges = db.totalChanges
        let setters = Self.itemRowSetters(for: item)
        try db.run(table.insert(or: .ignore, setters))
        if totalChanges != db.totalChanges, let c = cachedCount {
            cachedCount = c + 1
        }
    }

    func append(items: [IndexEntry], in db: Connection) throws {
        let totalChanges = db.totalChanges
        let setters = items.map { Self.itemRowSetters(for: $0) }
        try db.run(table.insertMany(or: .ignore, setters))
        if totalChanges != db.totalChanges {
            cachedCount = nil
        }
    }

    func delete(url: String, in db: Connection) throws {
        let totalChanges = db.totalChanges
        try db.run(table.filter(DB.urlRow == url).delete())
        if totalChanges != db.totalChanges {
            cachedCount = nil
        }
    }

    private func create(in db: Connection) throws {
        try db.run(table.create(ifNotExists: true) {
            $0.column(DB.urlRow, primaryKey: true)
            $0.column(DB.isSitemapRow)
            $0.column(DB.lastModifiedRow)
            $0.column(DB.etagRow)
            $0.column(DB.csIdentifier)
        })
        try db.run(table.createIndex(DB.urlRow, unique: true, ifNotExists: true))
    }

    func subtract(from items: inout Set<IndexEntry>, in db: Connection) throws {
        let array = items.map(\.url)
        if array.isPopulated {
            let itemsToSubtract = try db.prepare(table.select([DB.urlRow]).filter(array.contains(DB.urlRow)))
                .map { IndexEntry.pending(url: $0[DB.urlRow], isSitemap: false, csIdentifier: nil) }
            items.subtract(itemsToSubtract)
        }
    }

    func subtract(_ otherTable: TableWrapper, in db: Connection) throws {
        let urlsToSubtract = try db.prepare(otherTable.table).map { $0[DB.urlRow] }
        if urlsToSubtract.isPopulated {
            let pendingWithUrl = table.filter(urlsToSubtract.contains(DB.urlRow))
            let totalChanges = db.totalChanges
            try db.run(pendingWithUrl.delete())
            if totalChanges != db.totalChanges {
                cachedCount = nil
            }
        }
    }

    nonisolated static func == (lhs: TableWrapper, rhs: TableWrapper) -> Bool {
        lhs.id == rhs.id
    }

    func clear(purge: Bool, in db: Connection) throws {
        if purge {
            try db.run(table.drop(ifExists: true))
        } else {
            try db.run(table.delete())
        }
        cachedCount = 0
    }

    func cloneAndClear(as newName: TableWrapper, in db: Connection) throws {
        try db.run(table.rename(newName.table))
        try create(in: db)
        cachedCount = 0
    }
}
