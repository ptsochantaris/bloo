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

        case loading(PostAddAction), starting(Int, Int), pausing(Int, Int, Bool), paused(Int, Int, Bool), indexing(Int, Int, String), done(Int), deleting

        static var allCases: [Self] {
            [.loading(.none), .starting(0, 0), .indexing(0, 0, ""), .pausing(0, 0, false), defaultState, .done(0)]
        }

        static var defaultState: Self {
            .paused(0, 0, false)
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
            case .paused, .pausing:
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
            case .deleting, .done, .indexing, .loading, .pausing, .starting:
                false
            }
        }

        var shouldResume: Bool {
            switch self {
            case let .paused(_, _, reusumable):
                reusumable
            case .deleting, .done, .indexing, .loading, .pausing, .starting:
                false
            }
        }

        var canRemove: Bool {
            switch self {
            case .done, .paused:
                true
            case .deleting, .indexing, .loading, .pausing, .starting:
                false
            }
        }

        var canRestart: Bool {
            switch self {
            case .done, .paused:
                true
            case .deleting, .indexing, .loading, .pausing, .starting:
                false
            }
        }

        var canStop: Bool {
            switch self {
            case .deleting, .done, .loading, .paused, .pausing, .starting:
                false
            case .indexing:
                true
            }
        }

        var isNotIdle: Bool {
            switch self {
            case .done, .paused:
                false
            case .deleting, .indexing, .loading, .pausing, .starting:
                true
            }
        }

        var isStartingOrIndexing: Bool {
            switch self {
            case .deleting, .done, .loading, .paused, .pausing:
                false
            case .indexing, .starting:
                true
            }
        }

        var title: String {
            switch self {
            case .done: "Done"
            case .indexing: "Indexing"
            case .starting: "Starting"
            case .paused: "Paused"
            case .pausing: "Pausing"
            case .deleting: "Deleting"
            case .loading: "Loading"
            }
        }

        var logText: String {
            switch self {
            case let .done(count): "Completed, \(count) indexed items"
            case .deleting, .indexing, .loading, .paused, .pausing, .starting: title
            }
        }
    }
}
