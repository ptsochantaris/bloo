import Foundation
import OSLog

enum Log {
    case storage(OSLogType), crawling(String, OSLogType), app(OSLogType), search(OSLogType)

    func log(_ text: String) {
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
