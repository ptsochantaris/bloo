import Foundation
import SwiftUI

extension Domain {
    enum PostAddAction: Codable {
        case none, start, resumeIfNeeded
    }

    nonisolated enum State: CaseIterable, Codable, Hashable {
        case starting(Int, Int), pausing(Int, Int, Bool), paused(Int, Int, Bool), indexing(Int, Int, String), done(Int, Date?), deleting

        var groupId: Int {
            switch self {
            case .starting: 1
            case .pausing: 2
            case .paused: 3
            case .indexing: 4
            case .done: 5
            case .deleting: 6
            }
        }

        var progress: Double {
            switch self {
            case let .indexing(indexed, pending, _),
                 let .paused(indexed, pending, _),
                 let .pausing(indexed, pending, _),
                 let .starting(indexed, pending):
                let linear = Double(indexed) / max(1, Double(pending + indexed))
                return linear * linear

            case .deleting, .done:
                return 0
            }
        }

        static var allCases: [Self] {
            [.starting(0, 0), .indexing(0, 0, ""), .pausing(0, 0, false), defaultState, .done(0, .distantPast)]
        }

        static var defaultState: Self {
            .paused(0, 0, false)
        }

        var lastRefreshDate: Date {
            if case let .done(_, date) = self {
                return date ?? .distantPast
            }
            return .distantPast
        }

        @ViewBuilder
        var symbol: some View {
            switch self {
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
            case .deleting, .done, .indexing, .pausing, .starting:
                false
            }
        }

        var shouldResume: Bool {
            switch self {
            case let .paused(_, _, reusumable):
                reusumable
            case .deleting, .done, .indexing, .pausing, .starting:
                false
            }
        }

        var canRemove: Bool {
            switch self {
            case .done, .paused:
                true
            case .deleting, .indexing, .pausing, .starting:
                false
            }
        }

        var canRestart: Bool {
            switch self {
            case .done, .paused:
                true
            case .deleting, .indexing, .pausing, .starting:
                false
            }
        }

        var canStop: Bool {
            switch self {
            case .deleting, .done, .paused, .pausing, .starting:
                false
            case .indexing:
                true
            }
        }

        var isNotIdle: Bool {
            switch self {
            case .done, .paused:
                false
            case .deleting, .indexing, .pausing, .starting:
                true
            }
        }

        var isStartingOrIndexing: Bool {
            switch self {
            case .deleting, .done, .paused, .pausing:
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
            }
        }

        var logText: String {
            switch self {
            case let .done(count, date):
                if let date {
                    "Completed \(Formatters.relativeTime(since: date)), \(count) indexed items"
                } else {
                    "Completed on unknown date, \(count) indexed items"
                }
            case .deleting, .indexing, .paused, .pausing, .starting:
                title
            }
        }
    }
}
