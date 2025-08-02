import Foundation
import OrderedCollections

nonisolated struct BlockList<T: Hashable> {
    private let length: Int
    private var cache: OrderedCollections.OrderedSet<T>

    init(length: Int) {
        self.length = length
        cache = OrderedCollections.OrderedSet<T>()
    }

    mutating func checkForRejection(of item: T) -> Bool {
        if let index = cache.firstIndex(of: item) {
            let rejectionCount = cache.count
            if rejectionCount > length {
                cache.elements.move(fromOffsets: IndexSet(integer: index), toOffset: rejectionCount)
            }
            return true
        }
        return false
    }

    mutating func addRejection(for item: T) {
        cache.append(item)
        let rejectionCount = cache.count
        if rejectionCount == (length + 100) {
            cache = OrderedSet(cache.suffix(length - 100))
        }
    }
}
