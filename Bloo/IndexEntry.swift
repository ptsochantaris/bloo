import Foundation
import SQLite

enum IndexEntry: Hashable, Sendable {
    struct Content {
        let title: String?
        let description: String?
        let content: String?
        let keywords: String?
        let thumbnailUrl: String?
        let lastModified: Date?

        var hasItems: Bool {
            title != nil || description != nil || content != nil || keywords != nil
        }
    }

    case pending(url: String, isSitemap: Bool), visited(url: String, lastModified: Date?, etag: String?, content: Content)

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .pending(url, _), let .visited(url, _, _, _):
            hasher.combine(url)
        }
    }

    var url: String {
        switch self {
        case let .pending(url, _), let .visited(url, _, _, _):
            url
        }
    }

    static func == (lhs: IndexEntry, rhs: IndexEntry) -> Bool {
        lhs.url == rhs.url
    }
}
