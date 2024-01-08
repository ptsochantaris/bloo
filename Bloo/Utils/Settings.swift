import Foundation

enum SortStyle: Int, CaseIterable, Identifiable {
    case typical, newestFirst, oldestFirst

    var id: Int { rawValue }

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

    var indexingTaskPriority = TaskPriority(rawValue: Settings.indexingTaskPriorityRaw) {
        didSet {
            Settings.indexingTaskPriorityRaw = indexingTaskPriority.rawValue
        }
    }

    var maxConcurrentIndexingOperations: UInt = Settings.maxConcurrentIndexingOperationsRaw {
        didSet {
            Settings.maxConcurrentIndexingOperationsRaw = maxConcurrentIndexingOperations
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

    @UserDefault(key: "sortDoneStyle", defaultValue: 0)
    private static var sortDoneStyle: Int

    @UserDefault(key: "indexingDelayRaw", defaultValue: 2)
    private static var indexingDelayRaw: TimeInterval

    @UserDefault(key: "indexingScanDelayRaw", defaultValue: 0.5)
    private static var indexingScanDelayRaw: TimeInterval

    @UserDefault(key: "indexingTaskPriorityRaw", defaultValue: TaskPriority.medium.rawValue)
    private static var indexingTaskPriorityRaw: UInt8

    @UserDefault(key: "maxConcurrentIndexingOperations", defaultValue: 0)
    private static var maxConcurrentIndexingOperationsRaw: UInt
}
