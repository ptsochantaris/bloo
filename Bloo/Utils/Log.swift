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
    var messages = [LogMessage]()

    func append(message: LogMessage) {
        message.systemLog()

        messages.insert(message, at: 0)
        if messages.count > 1000 {
            messages = messages.dropLast(100)
        }
    }
}

struct LogView: View {
    let store: LogStorage

    @State private var messages = [LogMessage]()
    @State private var filter = ""

    var body: some View {
        VStack(alignment: .leading) {
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(.tertiary)

            TextField("Filter log", text: $filter)
                .focusable(false)
                .padding(.horizontal)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(messages) { message in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .firstTextBaseline) {
                                message.icon
                                    .bold()
                                    .frame(width: 28)
                                    .foregroundStyle(.accent)

                                Text(message.displayText)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.vertical, 4)

                            Rectangle()
                                .frame(height: 1)
                                .foregroundStyle(.quaternary)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .background(.quinary)
        .onChange(of: store.messages) { _, newMessages in
            applyFilter(filter, to: newMessages)
        }
        .onChange(of: filter) { _, newFilter in
            applyFilter(newFilter, to: store.messages)
        }
    }

    private func applyFilter(_ filter: String, to messageList: [LogMessage]) {
        Task {
            messages = await Task.detached {
                filter.isEmpty
                    ? messageList
                    : messageList.filter { $0.displayText.localizedCaseInsensitiveContains(filter) }
            }.value
        }
    }
}
