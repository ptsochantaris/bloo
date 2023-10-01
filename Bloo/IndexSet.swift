import Foundation
import OrderedCollections

struct IndexSet: Codable {
    private var items: OrderedSet<IndexEntry>

    enum CodingKeys: CodingKey {
        case items
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode(OrderedSet<IndexEntry>.self, forKey: .items)
    }

    init() {
        items = []
    }

    mutating func removeAll() {
        items.removeAll()
    }

    var isEmpty: Bool {
        items.isEmpty
    }

    func remove(from original: inout Set<IndexEntry>) {
        original.subtract(items)
    }

    func contains(_ url: URL) -> Bool {
        let tempEntry = IndexEntry(url: url, isSitemap: false)
        return items.contains(tempEntry)
    }

    mutating func remove(_ url: URL) {
        let tempEntry = IndexEntry(url: url, isSitemap: false)
        items.remove(tempEntry)
    }

    var count: Int {
        items.count
    }

    var isPopulated: Bool {
        items.isPopulated
    }

    mutating func subtract(_ set: IndexSet) {
        items.subtract(set.items)
    }

    @discardableResult
    mutating func insert(_ url: IndexEntry) -> Bool {
        items.append(url).inserted
    }

    mutating func formUnion(_ newItems: any Sequence<URL>) {
        let entries = newItems.map { IndexEntry(url: $0, isSitemap: false) }
        items.append(contentsOf: entries)
    }

    mutating func formUnion(_ newItems: any Sequence<IndexEntry>) {
        items.append(contentsOf: newItems)
    }

    mutating func removeFirst() -> IndexEntry? {
        if items.isPopulated {
            items.removeFirst()
        } else {
            nil
        }
    }
}
