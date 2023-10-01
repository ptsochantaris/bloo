import Foundation

struct IndexEntry: Codable, Hashable {
    let id: String
    let url: URL
    let lastModified: Date?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    init(url: URL, lastModified: Date? = nil) {
        self.id = url.absoluteString
        self.url = url
        self.lastModified = lastModified
    }
}
