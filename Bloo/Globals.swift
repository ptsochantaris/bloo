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

extension Collection {
    var isPopulated: Bool {
        !isEmpty
    }
}

enum Blooper: Error {
    case malformedUrl
    case coreSpotlightNotEnabled
    case blockedUrl
}

let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("storage.noindex", isDirectory: true)

func domainPath(for id: String) -> URL {
    documentsPath.appendingPathComponent(id, isDirectory: true)
}
