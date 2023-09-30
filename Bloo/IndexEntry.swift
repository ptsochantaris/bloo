import Foundation

struct IndexEntry: Codable, Hashable {
    let url: URL
    let lastModified: Date?

    init(url: URL, lastModified: Date? = nil) {
        self.url = url
        self.lastModified = lastModified
    }
}
