import Foundation

struct PersistedSet {
    private var items = Set<IndexEntry>()
    private let path: URL

    mutating func removeAll() {
        items.removeAll()
    }

    func contains(_ url: URL) -> Bool {
        let tempEntry = IndexEntry(url: url)
        return items.contains(tempEntry)
    }

    mutating func remove(_ url: URL) {
        let tempEntry = IndexEntry(url: url)
        items.remove(tempEntry)
    }

    var count: Int {
        items.count
    }

    var isPopulated: Bool {
        items.isPopulated
    }

    mutating func subtract(_ set: PersistedSet) {
        items.subtract(set.items)
    }

    @discardableResult
    mutating func insert(_ url: IndexEntry) -> Bool {
        items.insert(url).inserted
    }

    mutating func formUnion(_ newItems: [URL]) {
        let entries = newItems.map { IndexEntry(url: $0) }
        items.formUnion(entries)
    }

    mutating func removeFirst() -> IndexEntry? {
        if items.isPopulated {
            items.removeFirst()
        } else {
            nil
        }
    }

    init(path: URL) throws {
        self.path = path
        if FileManager.default.fileExists(atPath: path.path) {
            let decoder = JSONDecoder()
            let data = try Data(contentsOf: path)
            items = try decoder.decode(Set<IndexEntry>.self, from: data)
            log("Read \(path.path)")
        } else {
            items = []
            log("Started new file at \(path.path)")
        }
    }

    func write() async {
        Task.detached { [items] in
            try! JSONEncoder().encode(items).write(to: path, options: .atomic)
            log("!! Written \(path)")
        }
    }
}
