import Foundation
import SQLite

enum IndexEntry: Hashable, Sendable {
    case pending(url: String, isSitemap: Bool), visited(url: String, lastModified: Date?, etag: String?)

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .pending(url, _), let .visited(url, _, _):
            hasher.combine(url)
        }
    }

    var url: String {
        switch self {
        case let .pending(url, _), let .visited(url, _, _):
            url
        }
    }

    func withCsIdentifier(_ csIdentifier: String) -> IndexEntry {
        switch self {
        case let .pending(url, isSitemap):
            .pending(url: url, isSitemap: isSitemap)
        case let .visited(url, lastModified, etag):
            .visited(url: url, lastModified: lastModified, etag: etag)
        }
    }

    static func == (lhs: IndexEntry, rhs: IndexEntry) -> Bool {
        lhs.url == rhs.url
    }
}
