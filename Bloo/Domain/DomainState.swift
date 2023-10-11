import Foundation
import SwiftUI

extension Domain {
    enum PostAddAction: Codable {
        case none, start, resumeIfNeeded
    }

    enum State: CaseIterable, Codable, Hashable {
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.title == rhs.title
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(title)
        }

        case loading(PostAddAction), starting(Int, Int), paused(Int, Int, Bool, Bool), indexing(Int, Int, String), done(Int), deleting

        static var allCases: [Self] {
            [.loading(.none), .starting(0, 0), .indexing(0, 0, ""), defaultState, .done(0)]
        }

        static var defaultState: Self {
            .paused(0, 0, false, false)
        }

        @ViewBuilder
        var symbol: some View {
            switch self {
            case .loading:
                StatusIcon(name: "gear", color: .yellow)
            case .starting:
                StatusIcon(name: "magnifyingglass", color: .yellow)
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
            case .deleting, .done, .indexing, .loading, .starting:
                false
            }
        }

        var shouldResume: Bool {
            switch self {
            case let .paused(_, _, _, reusumable):
                reusumable
            case .deleting, .done, .indexing, .loading, .starting:
                false
            }
        }

        var canRestart: Bool {
            switch self {
            case .done, .paused:
                true
            case .deleting, .indexing, .loading, .starting:
                false
            }
        }

        var canStop: Bool {
            switch self {
            case .deleting, .done, .loading, .paused, .starting:
                false
            case .indexing:
                true
            }
        }

        var isActive: Bool {
            switch self {
            case .done, .paused:
                false
            case .deleting, .indexing, .loading, .starting:
                true
            }
        }

        var title: String {
            switch self {
            case .done: "Done"
            case .indexing: "Indexing"
            case .starting: "Starting"
            case .paused: "Paused"
            case .deleting: "Deleting"
            case .loading: "Loading"
            }
        }

        var logText: String {
            switch self {
            case let .done(count): "Completed, \(count) indexed items"
            case .deleting, .indexing, .loading, .paused, .starting: title
            }
        }
    }
}
