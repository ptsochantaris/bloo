import Foundation
import SQLite

enum IndexEntry: Codable, Hashable, Sendable {
    case pending(url: String, isSitemap: Bool), visited(url: String, lastModified: Date?, etag: String?, description: String?, content: String?)

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .pending(url, _), let .visited(url, _, _, _, _):
            hasher.combine(url)
        }
    }

    var url: String {
        switch self {
        case let .pending(url, _), let .visited(url, _, _, _, _):
            url
        }
    }

    static func == (lhs: IndexEntry, rhs: IndexEntry) -> Bool {
        lhs.url == rhs.url
    }
}
