import Foundation

enum IndexState: Codable {
    case pending(Bool), visited(Date?)
}

struct IndexEntry: Codable, Hashable {
    let url: String
    let state: IndexState

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.url == rhs.url
    }

    init(url: URL, isSitemap: Bool) {
        self.url = url.absoluteString
        state = .pending(isSitemap)
    }

    init(url: String, state: IndexState) {
        self.url = url
        self.state = state
    }
}
