import Foundation
import SwiftData

@Model
nonisolated final class CrawlItem {
    enum Kind: Int, Codable {
        case pending = 0, visited = 1
    }

    #Index<CrawlItem>([\.kindRaw], [\.url], [\.kindRaw, \.url])

    var url: String = ""
    var isSitemap: Bool = false
    var lastModified: Date?
    var etag: String?
    var kindRaw: Int = Kind.pending.rawValue

    init(url: String, isSitemap: Bool, lastModified: Date?, etag: String?, kind: Kind) {
        self.url = url
        self.isSitemap = isSitemap
        self.lastModified = lastModified
        self.etag = etag
        kindRaw = kind.rawValue
    }

    convenience init(entry: IndexEntry, kind: Kind) {
        switch entry {
        case let .pending(url, isSitemap):
            self.init(url: url, isSitemap: isSitemap, lastModified: nil, etag: nil, kind: kind)
        case let .visited(url, lastModified, etag):
            self.init(url: url, isSitemap: false, lastModified: lastModified, etag: etag, kind: kind)
        }
    }

    var asIndexEntry: IndexEntry {
        if etag != nil || lastModified != nil {
            .visited(url: url, lastModified: lastModified, etag: etag)
        } else {
            .pending(url: url, isSitemap: isSitemap)
        }
    }
}
