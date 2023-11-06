@preconcurrency import CoreSpotlight
import Foundation

extension Storage {
    final class Snapshot: Codable, Sendable {
        let id: String
        let state: Domain.State

        let items: [CSSearchableItem]
        let removedItems: Set<String>

        enum CodingKeys: CodingKey {
            case id, state, pending, indexed
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            state = try container.decode(Domain.State.self, forKey: .state)
            items = []
            removedItems = []
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(state, forKey: .state)
        }

        init(id: String, state: Domain.State, items: [CSSearchableItem] = [], removedItems: Set<String> = []) {
            self.id = id
            self.items = items
            self.removedItems = removedItems

            switch state {
            case .deleting, .done, .paused:
                self.state = state
            case let .pausing(a, b, c):
                self.state = .paused(a, b, c)
            case .indexing, .loading, .starting:
                self.state = .paused(0, 0, true)
            }
        }
    }
}
