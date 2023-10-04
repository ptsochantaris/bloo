import Foundation

enum IndexEntry: Codable, Hashable {
    case pending(url: URL, isSitemap: Bool), visited(url: URL, lastModified: Date?)

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .pending(url, _), let .visited(url, _):
            hasher.combine(url)
        }
    }

    var url: URL {
        switch self {
        case let .pending(url, _), let .visited(url, _):
            url
        }
    }

    static func == (lhs: IndexEntry, rhs: IndexEntry) -> Bool {
        lhs.url == rhs.url
    }
}
