import Foundation
import OSLog

@globalActor actor LogActor: GlobalActor {
    static let shared = LogActor()
}

nonisolated enum Log {
    case storage(OSLogType), crawling(String, OSLogType), app(OSLogType), search(OSLogType)

    func log(_ text: String) {
        Task { @LogActor in
            switch self {
            case let .app(level):
                os_log(level, "General: %{public}@", text)
            case let .crawling(domain, level):
                os_log(level, "Crawling (%{public}@): %{public}@", domain, text)
            case let .storage(level):
                os_log(level, "Storage: %{public}@", text)
            case let .search(level):
                os_log(level, "Search: %{public}@", text)
            }
        }
    }
}
