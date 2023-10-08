import Foundation
import SwiftUI

enum DomainState: CaseIterable, Codable, Hashable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
    }

    case loading(Int), paused(Int, Int, Bool, Bool), indexing(Int, Int, String), done(Int), deleting

    static var allCases: [DomainState] {
        [.loading(0), .indexing(0, 0, ""), .paused(0, 0, false, false), .done(0)]
    }

    @ViewBuilder
    var symbol: some View {
        switch self {
        case .loading:
            StatusIcon(name: "gear", color: .yellow)
        case .deleting:
            StatusIcon(name: "trash", color: .red)
        case .paused:
            StatusIcon(name: "pause", color: .red)
        case .done:
            StatusIcon(name: "checkmark", color: .green)
        case .indexing:
            StatusIcon(name: "magnifyingglass", color: .yellow)
        }
    }

    var canStart: Bool {
        switch self {
        case .paused:
            true
        case .deleting, .done, .indexing, .loading:
            false
        }
    }

    var canRestart: Bool {
        switch self {
        case .done, .paused:
            true
        case .deleting, .indexing, .loading:
            false
        }
    }

    var canStop: Bool {
        switch self {
        case .deleting, .done, .loading, .paused:
            false
        case .indexing:
            true
        }
    }

    var isActive: Bool {
        switch self {
        case .deleting, .done, .paused:
            false
        case .indexing, .loading:
            true
        }
    }

    var title: String {
        switch self {
        case .done: "Done"
        case .indexing: "Indexing"
        case .loading: "Starting"
        case .paused: "Paused"
        case .deleting: "Deleting"
        }
    }

    var logText: String {
        switch self {
        case let .done(count): "Completed, \(count) indexed items"
        case .deleting, .indexing, .loading, .paused: title
        }
    }
}
