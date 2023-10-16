import Foundation
import SQLite

struct CrawlerStorage {
    private static let db = {
        let file = documentsPath.appending(path: "data.sqlite3", directoryHint: .notDirectory)
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
    private static let thumbnailUrlRow = Expression<String?>("thumbnailUrl")

    private static let titleRow = Expression<String?>("title")
    private static let descriptionRow = Expression<String?>("description")
    private static let contentRow = Expression<String?>("content")
    private static let keywordRow = Expression<String?>("keywords")
    private static let domainRow = Expression<String>("domain")

    private let id: String
    private let pendingTable: Table
    private let visitedTable: Table
    private static let textTable = VirtualTable("text_search")

    static func textQuery(_ text: String, limit: Int) throws -> [Search.Result] {
        let searchTerms = text.split(separator: " ").map { String($0) }
        let terms = searchTerms.map { $0.lowercased().sqlSafe }.joined(separator: " AND ")
        let resultSequence = try db.prepareRowIterator(
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
            let r = Search.Result(id: item[Self.urlRow],
                                  title: item[Self.titleRow] ?? "",
                                  descriptionText: item[Self.descriptionRow] ?? "",
                                  contentText: item[Self.contentRow],
                                  displayDate: item[Self.lastModifiedRow],
                                  thumbnailUrl: URL(string: item[Self.thumbnailUrlRow] ?? ""),
                                  keywords: (item[Self.keywordRow]?.split(separator: ", ").map { String($0) }) ?? [],
                                  terms: searchTerms)
            res.append(r)
        }
        return res
    }

    init(id: String) throws {
        self.id = id

        let tableId = id.replacingOccurrences(of: ".", with: "_")
        pendingTable = Table("pending_\(tableId)")
        visitedTable = Table("visited_\(tableId)")

        try createPendingTable()

        try createIndexedTable()

        try createTextTable()
    }

    private func createPendingTable() throws {
        try Self.db.run(pendingTable.create(ifNotExists: true) {
            $0.column(Self.urlRow, primaryKey: true)
            $0.column(Self.isSitemapRow)
            $0.column(Self.lastModifiedRow)
            $0.column(Self.etagRow)
        })
    }

    private func createIndexedTable() throws {
        try Self.db.run(visitedTable.create(ifNotExists: true) {
            $0.column(Self.urlRow, primaryKey: true)
            $0.column(Self.isSitemapRow)
            $0.column(Self.lastModifiedRow)
            $0.column(Self.etagRow)
        })
    }

    private func createTextTable() throws {
        let fts5Config = FTS5Config()
        fts5Config.column(Self.domainRow, [.unindexed])
        fts5Config.column(Self.urlRow, [.unindexed])
        fts5Config.column(Self.titleRow)
        fts5Config.column(Self.descriptionRow)
        fts5Config.column(Self.contentRow)
        fts5Config.column(Self.keywordRow)
        fts5Config.column(Self.thumbnailUrlRow, [.unindexed])
        fts5Config.column(Self.lastModifiedRow, [.unindexed])
        try Self.db.run(Self.textTable.create(.FTS5(fts5Config), ifNotExists: true))
    }

    func removeAll(purge: Bool) throws {
        if purge {
            try Self.db.run(visitedTable.drop(ifExists: true))
            try Self.db.run(pendingTable.drop(ifExists: true))
        } else {
            try Self.db.run(visitedTable.delete())
            try Self.db.run(pendingTable.delete())
        }
        try Self.db.run(Self.textTable.filter(Self.domainRow == id).delete())
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
        let etag = res[Self.etagRow]
        let lastModified = res[Self.lastModifiedRow]

        let tq = Self.textTable.filter(Self.urlRow == url)
        let textRes = try Self.db.pluck(tq)
        let content = IndexEntry.Content(title: textRes?[Self.titleRow],
                                         description: textRes?[Self.descriptionRow],
                                         content: textRes?[Self.contentRow],
                                         keywords: textRes?[Self.keywordRow],
                                         thumbnailUrl: textRes?[Self.thumbnailUrlRow],
                                         lastModified: textRes?[Self.lastModifiedRow])

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
            try Self.db.run(table.insert(or: .replace, Self.urlRow <- url, Self.isSitemapRow <- isSitemap))
        case let .visited(url, lastModified, etag, content):
            try Self.db.run(table.insert(or: .replace, Self.urlRow <- url, Self.lastModifiedRow <- lastModified, Self.etagRow <- etag))
            try Self.db.run(Self.textTable.insert(or: .replace, Self.domainRow <- id, Self.urlRow <- url, Self.titleRow <- content.title, Self.descriptionRow <- content.description, Self.contentRow <- content.content, Self.keywordRow <- content.keywords, Self.thumbnailUrlRow <- content.thumbnailUrl, Self.lastModifiedRow <- content.lastModified))
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
            case let .visited(url, lastModified, etag, _):
                [Self.urlRow <- url, Self.lastModifiedRow <- lastModified, Self.etagRow <- etag]
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
