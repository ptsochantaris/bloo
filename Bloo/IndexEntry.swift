import Foundation
import SQLite

enum IndexEntry: Hashable, Sendable {
    struct Content {
        let title: String?
        let description: String?
        let condensedContent: String?
        let textBlocks: [String]
        let keywords: String?
        let thumbnailUrl: String?
        let lastModified: Date?

        var hasItems: Bool {
            title != nil || description != nil || condensedContent != nil || keywords != nil || textBlocks.isPopulated
        }
    }

    case pending(url: String, isSitemap: Bool, textRowId: Int64?), visited(url: String, lastModified: Date?, etag: String?, textRowId: Int64?)

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .pending(url, _, _), let .visited(url, _, _, _):
            hasher.combine(url)
        }
    }

    var url: String {
        switch self {
        case let .pending(url, _, _), let .visited(url, _, _, _):
            url
        }
    }

    var textRowId: Int64? {
        switch self {
        case let .pending(_, _, textRowId), let .visited(_, _, _, textRowId):
            textRowId
        }
    }

    func withTextRowId(_ newId: Int64?) -> IndexEntry {
        switch self {
        case let .pending(url, isSitemap, _):
            .pending(url: url, isSitemap: isSitemap, textRowId: newId)
        case let .visited(url, lastModified, etag, _):
            .visited(url: url, lastModified: lastModified, etag: etag, textRowId: newId)
        }
    }

    static func == (lhs: IndexEntry, rhs: IndexEntry) -> Bool {
        lhs.url == rhs.url
    }
}
