import Foundation
import SQLite

struct TableWrapper: Equatable {
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
        let totalChanges = db.totalChanges
        switch item {
        case let .pending(url, isSitemap):
            try db.run(table.insert(or: .replace, DB.urlRow <- url, DB.isSitemapRow <- isSitemap))
        case let .visited(url, lastModified, etag):
            try db.run(table.insert(or: .replace, DB.urlRow <- url, DB.lastModifiedRow <- lastModified, DB.etagRow <- etag))
        }
        if totalChanges != db.totalChanges, let c = cachedCount {
            cachedCount = c + 1
        }
    }

    mutating func append(items: any Collection<IndexEntry>, in db: Connection) throws {
        let totalChanges = db.totalChanges
        let setters = items.map {
            switch $0 {
            case let .pending(url, isSitemap):
                [DB.urlRow <- url, DB.isSitemapRow <- isSitemap]
            case let .visited(url, lastModified, etag):
                [DB.urlRow <- url, DB.lastModifiedRow <- lastModified, DB.etagRow <- etag]
            }
        }
        try db.run(table.insertMany(or: .ignore, setters))
        if totalChanges != db.totalChanges {
            cachedCount = nil
        }
    }

    mutating func delete(url: String, in db: Connection) throws {
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
            let totalChanges = db.totalChanges
            try db.run(pendingWithUrl.delete())
            if totalChanges != db.totalChanges {
                cachedCount = nil
            }
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
        cachedCount = 0
    }

    mutating func cloneAndClear(as newName: TableWrapper, in db: Connection) throws {
        try db.run(table.rename(newName.table))
        try create(in: db)
        cachedCount = 0
    }
}
