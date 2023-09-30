import Foundation

struct IndexEntry: Equatable, Hashable, Identifiable, Codable {
    let id: String
    let url: URL
    let lastModified: Date?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    init(url: URL, lastModified: Date? = nil) {
        id = url.absoluteString
        self.url = url
        self.lastModified = lastModified
    }
}
