import Foundation

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

    @UserDefault(key: "indexingTaskPriorityRaw", defaultValue: TaskPriority.medium.rawValue)
    private static var indexingTaskPriorityRaw: UInt8

    @UserDefault(key: "maxConcurrentIndexingOperations", defaultValue: 0)
    private static var maxConcurrentIndexingOperationsRaw: UInt
}
