//
//  Snapshot.swift
//  Bloo
//
//  Created by Paul Tsochantaris on 02/10/2023.
//

import Foundation
import CoreSpotlight

struct Snapshot: Codable {
    let id: String
    let state: DomainState
    let items: [CSSearchableItem]
    let pending: IndexSet
    let indexed: IndexSet

    init(id: String, state: DomainState, items: [CSSearchableItem], pending: IndexSet, indexed: IndexSet) {
        self.id = id
        self.items = items
        self.pending = pending
        self.indexed = indexed

        switch state {
        case .done, .paused, .deleting:
            self.state = state
        case .indexing, .loading:
            self.state = .paused(0, 0, false, true)
        }
    }

    enum CodingKeys: CodingKey {
        case id, state, pending, indexed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(state, forKey: .state)
        try container.encode(pending, forKey: .pending)
        try container.encode(indexed, forKey: .indexed)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        state = try container.decode(DomainState.self, forKey: .state)
        pending = try container.decode(IndexSet.self, forKey: .pending)
        indexed = try container.decode(IndexSet.self, forKey: .indexed)
        items = []
    }
}
