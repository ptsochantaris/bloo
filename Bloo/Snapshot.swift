import CoreSpotlight
import Foundation
import OrderedCollections

final class Snapshot: Codable {
    let id: String
    let state: DomainState
    let pending: OrderedSet<IndexEntry>
    let indexed: OrderedSet<IndexEntry>

    var items: [CSSearchableItem] = []

    enum CodingKeys: CodingKey {
        case id, state, pending, indexed
    }

    init(id: String, state: DomainState, items: [CSSearchableItem], pending: OrderedSet<IndexEntry>, indexed: OrderedSet<IndexEntry>) {
        self.id = id
        self.items = items
        self.pending = pending
        self.indexed = indexed

        switch state {
        case .deleting, .done, .paused:
            self.state = state
        case .indexing, .loading:
            self.state = .paused(0, 0, false, true)
        }
    }
}
