import Foundation

struct IndexEntry: ModelItem, Codable {
    let id: String
    let url: URL
    let lastModified: Date?

    init(url: URL, lastModified: Date? = nil) {
        id = url.absoluteString
        self.url = url
        self.lastModified = lastModified
    }
}
