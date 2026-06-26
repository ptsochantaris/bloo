import Foundation

nonisolated enum SortStyle: Int, CaseIterable, Identifiable {
    case typical, newestFirst, oldestFirst

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .typical: "By Name"
        case .newestFirst: "Newly Refreshed Domains First"
        case .oldestFirst: "Oldest Refreshed Domains First"
        }
    }

    static var allCases: [SortStyle] {
        [.typical, .newestFirst, .oldestFirst]
    }
}

@Observable
final class Settings {
    static let shared = Settings()

    /// The selectable values for the "Simultaneous calls" setting. A value of `0` means unlimited.
    static let simultaneousCallOptions: [UInt] = [1, 2, 4, 8, 16, 0]

    var indexingTaskPriority = TaskPriority(rawValue: Settings.indexingTaskPriorityRaw) {
        didSet {
            Settings.indexingTaskPriorityRaw = indexingTaskPriority.rawValue
        }
    }

    /// The maximum number of HTTP calls that may be in flight across all crawlers at once. A value
    /// of `0` means unlimited. Drives the ticket pool of the shared `RequestGate`.
    var maxSimultaneousCalls: UInt = Settings.maxSimultaneousCallsRaw {
        didSet {
            Settings.maxSimultaneousCallsRaw = maxSimultaneousCalls
        }
    }

    var indexingDelay: TimeInterval = Settings.indexingDelayRaw {
        didSet {
            Settings.indexingDelayRaw = indexingDelay
        }
    }

    var indexingScanDelay: TimeInterval = Settings.indexingScanDelayRaw {
        didSet {
            Settings.indexingScanDelayRaw = indexingScanDelay
        }
    }

    var sortDoneStyle = SortStyle(rawValue: Settings.sortDoneStyle) ?? .typical {
        didSet {
            Settings.sortDoneStyle = sortDoneStyle.rawValue
        }
    }

    var collapsedSections = Set(Settings.collapsedSectionsRaw) {
        didSet {
            Settings.collapsedSectionsRaw = Array(collapsedSections)
        }
    }

    func isSectionCollapsed(_ id: String) -> Bool {
        collapsedSections.contains(id)
    }

    func toggleSection(_ id: String) {
        if collapsedSections.contains(id) {
            collapsedSections.remove(id)
        } else {
            collapsedSections.insert(id)
        }
    }

    @UserDefault(key: "collapsedSections", defaultValue: [])
    private static var collapsedSectionsRaw: [String]

    @UserDefault(key: "sortDoneStyle", defaultValue: 0)
    private static var sortDoneStyle: Int

    @UserDefault(key: "indexingDelayRaw", defaultValue: 2)
    private static var indexingDelayRaw: TimeInterval

    @UserDefault(key: "indexingScanDelayRaw", defaultValue: 0.5)
    private static var indexingScanDelayRaw: TimeInterval

    @UserDefault(key: "indexingTaskPriorityRaw", defaultValue: TaskPriority.medium.rawValue)
    private static var indexingTaskPriorityRaw: UInt8

    // Key retained from the previous "Minimise Network Usage" setting so existing preferences carry
    // over: a stored value of 1 now reads as a single simultaneous call, 0 as unlimited.
    @UserDefault(key: "maxConcurrentIndexingOperations", defaultValue: 0)
    private static var maxSimultaneousCallsRaw: UInt
}
