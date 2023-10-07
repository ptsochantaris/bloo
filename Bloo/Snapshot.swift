@preconcurrency import CoreSpotlight
import Foundation
@preconcurrency import OrderedCollections

final class Snapshot: Codable, Sendable {
    let id: String
    let state: DomainState
    let pending: OrderedSet<IndexEntry>
    let indexed: OrderedSet<IndexEntry>

    let items: [CSSearchableItem]

    enum CodingKeys: CodingKey {
        case id, state, pending, indexed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        state = try container.decode(DomainState.self, forKey: .state)
        pending = try container.decode(OrderedSet<IndexEntry>.self, forKey: .pending)
        indexed = try container.decode(OrderedSet<IndexEntry>.self, forKey: .indexed)
        items = []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(state, forKey: .state)
        try container.encode(pending, forKey: .pending)
        try container.encode(indexed, forKey: .indexed)
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
