import Foundation
import SwiftData

final nonisolated class TableWrapper {
    private static let chunkSize = 500

    private let kind: CrawlItem.Kind
    private let kindRaw: Int

    var cachedCount: Int?

    init(kind: CrawlItem.Kind) {
        self.kind = kind
        kindRaw = kind.rawValue
        cachedCount = nil
    }

    func setCachedCount(_ newCount: Int) {
        cachedCount = newCount
    }

    func count(in context: ModelContext) throws -> Int {
        if let cachedCount {
            return cachedCount
        }
        let k = kindRaw
        let result = try context.fetchCount(FetchDescriptor<CrawlItem>(predicate: #Predicate<CrawlItem> { $0.kindRaw == k }))
        cachedCount = result
        return result
    }

    func next(in context: ModelContext) throws -> CrawlItem? {
        let k = kindRaw
        var descriptor = FetchDescriptor<CrawlItem>(predicate: #Predicate<CrawlItem> { $0.kindRaw == k })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Does not save; the caller flushes once it has finished a batch of mutations.
    func append(item: IndexEntry, in context: ModelContext) throws {
        let k = kindRaw
        let url = item.url
        var descriptor = FetchDescriptor<CrawlItem>(predicate: #Predicate<CrawlItem> { $0.kindRaw == k && $0.url == url })
        descriptor.fetchLimit = 1
        if try context.fetch(descriptor).first != nil {
            return
        }
        context.insert(CrawlItem(entry: item, kind: kind))
        if let c = cachedCount {
            cachedCount = c + 1
        }
    }

    /// Does not save; the caller flushes once it has finished a batch of mutations.
    func append(items: [IndexEntry], in context: ModelContext) throws {
        guard items.isPopulated else {
            return
        }
        let k = kindRaw
        let candidateUrls = items.map(\.url)
        var seen = Set<String>()
        for start in stride(from: 0, to: candidateUrls.count, by: Self.chunkSize) {
            let chunk = Array(candidateUrls[start ..< min(start + Self.chunkSize, candidateUrls.count)])
            let existing = try context.fetch(FetchDescriptor<CrawlItem>(predicate: #Predicate<CrawlItem> { $0.kindRaw == k && chunk.contains($0.url) }))
            seen.formUnion(existing.map(\.url))
        }
        var insertedCount = 0
        for item in items where seen.insert(item.url).inserted {
            context.insert(CrawlItem(entry: item, kind: kind))
            insertedCount += 1
        }
        if insertedCount > 0, let c = cachedCount {
            cachedCount = c + insertedCount
        }
    }

    /// Does not save; the caller flushes once it has finished a batch of mutations.
    func delete(url: String, in context: ModelContext) throws {
        let k = kindRaw
        let matches = try context.fetch(FetchDescriptor<CrawlItem>(predicate: #Predicate<CrawlItem> { $0.kindRaw == k && $0.url == url }))
        guard matches.isPopulated else {
            return
        }
        for match in matches {
            context.delete(match)
        }
        if let c = cachedCount {
            cachedCount = c - matches.count
        }
    }

    func subtract(from items: inout Set<IndexEntry>, in context: ModelContext) throws {
        let urls = items.map(\.url)
        guard urls.isPopulated else {
            return
        }
        let k = kindRaw
        var existingUrls = Set<String>()
        for start in stride(from: 0, to: urls.count, by: Self.chunkSize) {
            let chunk = Array(urls[start ..< min(start + Self.chunkSize, urls.count)])
            let found = try context.fetch(FetchDescriptor<CrawlItem>(predicate: #Predicate<CrawlItem> { $0.kindRaw == k && chunk.contains($0.url) }))
            existingUrls.formUnion(found.map(\.url))
        }
        if existingUrls.isPopulated {
            items = items.filter { !existingUrls.contains($0.url) }
        }
    }

    func subtract(_ otherTable: TableWrapper, in context: ModelContext) throws {
        let otherK = otherTable.kindRaw
        let urlsToSubtract = try context.fetch(FetchDescriptor<CrawlItem>(predicate: #Predicate<CrawlItem> { $0.kindRaw == otherK })).map(\.url)
        guard urlsToSubtract.isPopulated else {
            return
        }
        let k = kindRaw
        var deletedCount = 0
        for start in stride(from: 0, to: urlsToSubtract.count, by: Self.chunkSize) {
            let chunk = Array(urlsToSubtract[start ..< min(start + Self.chunkSize, urlsToSubtract.count)])
            let matches = try context.fetch(FetchDescriptor<CrawlItem>(predicate: #Predicate<CrawlItem> { $0.kindRaw == k && chunk.contains($0.url) }))
            for match in matches {
                context.delete(match)
            }
            deletedCount += matches.count
        }
        try context.save()
        if deletedCount > 0, let c = cachedCount {
            cachedCount = c - deletedCount
        }
    }

    func clear(purge _: Bool, in context: ModelContext) throws {
        let k = kindRaw
        try context.delete(model: CrawlItem.self, where: #Predicate<CrawlItem> { $0.kindRaw == k })
        try context.save()
        cachedCount = 0
    }

    func cloneAndClear(as newName: TableWrapper, in context: ModelContext) throws {
        let k = kindRaw
        let newKindRaw = newName.kindRaw
        let rows = try context.fetch(FetchDescriptor<CrawlItem>(predicate: #Predicate<CrawlItem> { $0.kindRaw == k }))
        for row in rows {
            row.kindRaw = newKindRaw
        }
        try context.save()
        cachedCount = 0
        if let nc = newName.cachedCount {
            newName.cachedCount = nc + rows.count
        }
    }
}
