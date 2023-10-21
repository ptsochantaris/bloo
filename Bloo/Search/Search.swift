import Foundation

enum Search: Equatable, Codable, Sendable {
    case none(Bool), top(String, Bool), full(String, Bool)

    var trimmedText: String {
        switch self {
        case .none: ""
        case let .full(text, _), let .top(text, _): text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    @MainActor
    private static var _windowIdToSearch: [UUID: Search]?

    @MainActor
    static var windowIdToSearch: [UUID: Search] {
        get {
            if let _windowIdToSearch {
                return _windowIdToSearch
            }
            let searchesPath = documentsPath.appendingPathComponent("searches.json", isDirectory: false)
            if let data = try? Data(contentsOf: searchesPath),
               let searches = try? JSONDecoder().decode([UUID: Search].self, from: data) {
                _windowIdToSearch = searches
                return searches
            }
            _windowIdToSearch = [:]
            return [:]
        }
        set {
            _windowIdToSearch = newValue
            let searchesPath = documentsPath.appendingPathComponent("searches.json", isDirectory: false)
            if let data = try? JSONEncoder().encode(newValue) {
                try? data.write(to: searchesPath)
            }
        }
    }
}
