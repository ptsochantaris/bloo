import Foundation
import SQLite

enum IndexEntry: Hashable, Sendable {
    case pending(url: String, isSitemap: Bool, csIdentifier: String?), visited(url: String, lastModified: Date?, etag: String?, csIdentifier: String?)

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

    var csIdentifier: String? {
        switch self {
        case let .pending(_, _, csIdentifier), let .visited(_, _, _, csIdentifier):
            csIdentifier
        }
    }

    func withCsIdentifier(_ csIdentifier: String) -> IndexEntry {
        switch self {
        case let .pending(url, isSitemap, _):
            .pending(url: url, isSitemap: isSitemap, csIdentifier: csIdentifier)
        case let .visited(url, lastModified, etag, _):
            .visited(url: url, lastModified: lastModified, etag: etag, csIdentifier: csIdentifier)
        }
    }

    static func == (lhs: IndexEntry, rhs: IndexEntry) -> Bool {
        lhs.url == rhs.url
    }
}
