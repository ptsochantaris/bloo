import Foundation
import SwiftUI

extension Domain {
    enum PostAddAction: Codable {
        case none, start, resumeIfNeeded
    }

    enum State: CaseIterable, Codable, Hashable, Identifiable {
        var id: Int {
            switch self {
            case .deleting:
                1
            case .done:
                2
            case .indexing:
                3
            case .pausing:
                4
            case .starting:
                5
            case .paused:
                6
            }
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.title == rhs.title
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(title)
        }

        case starting(Int, Int), pausing(Int, Int, Bool), paused(Int, Int, Bool), indexing(Int, Int, String), done(Int, Date?), deleting

        static var allCases: [Self] {
            [.starting(0, 0), .indexing(0, 0, ""), .pausing(0, 0, false), defaultState, .done(0, .distantPast)]
        }

        static var defaultState: Self {
            .paused(0, 0, false)
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
            case let .done(count, date): "Completed on \(Formatters.relativeTime.string(for: date) ?? "<no date>"), \(count) indexed items"
            case .deleting, .indexing, .paused, .pausing, .starting: title
            }
        }
    }
}
