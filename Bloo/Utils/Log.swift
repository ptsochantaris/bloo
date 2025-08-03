import Foundation
import OSLog
import SwiftUI

let logStorage = LogStorage()

nonisolated enum Log {
    case storage(OSLogType), crawling(String, OSLogType), app(OSLogType), search(OSLogType)

    func log(_ text: String) {
        let message = LogMessage(type: self, text: text)
        Task { @MainActor in
            logStorage.append(message: message)
        }
    }
}

nonisolated struct LogMessage: Identifiable, Equatable {
    let id = UUID()
    let type: Log
    let text: String

    static func == (lhs: LogMessage, rhs: LogMessage) -> Bool {
        lhs.id == rhs.id
    }

    var icon: Image {
        switch type {
        case .storage: Image(systemName: "cylinder.split.1x2.fill")
        case .crawling: Image(systemName: "pencil.and.list.clipboard")
        case .search: Image(systemName: "magnifyingglass")
        case .app: Image(systemName: "books.vertical.circle")
        }
    }

    var displayText: String {
        switch type {
        case .storage: "Storage: \(text)"
        case let .crawling(domain, _): "Crawling: (\(domain)): \(text)"
        case .app: "General: \(text)"
        case .search: "Search: \(text)"
        }
    }

    func systemLog() {
        switch type {
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

@Observable
final class LogStorage {
    var filteredMessages = [LogMessage]()

    var filter = "" {
        didSet {
            applyFilter()
        }
    }

    private var allMessages = [LogMessage]()

    func append(message: LogMessage) {
        message.systemLog()

        allMessages.insert(message, at: 0)
        if allMessages.count > 10000 {
            allMessages = allMessages.dropLast(100)
        }

        if filter.isEmpty {
            filteredMessages = allMessages

        } else if message.displayText.localizedCaseInsensitiveContains(filter) {
            filteredMessages.insert(message, at: 0)

            if filteredMessages.count > 10000 {
                filteredMessages = filteredMessages.dropLast(100)
            }
        }
    }

    private func applyFilter() {
        if filter.isEmpty {
            filteredMessages = allMessages
        } else {
            filteredMessages = allMessages.filter { $0.displayText.localizedCaseInsensitiveContains(filter) }
        }
    }
}
