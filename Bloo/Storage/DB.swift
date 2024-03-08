import Foundation
import SQLite

enum DB {
    nonisolated(unsafe) static let rowId = Expression<Int64>("rowid")
    nonisolated(unsafe) static let urlRow = Expression<String>("url")
    nonisolated(unsafe) static let isSitemapRow = Expression<Bool?>("isSitemap")
    nonisolated(unsafe) static let lastModifiedRow = Expression<Date?>("lastModified")
    nonisolated(unsafe) static let etagRow = Expression<String?>("etag")
    nonisolated(unsafe) static let thumbnailUrlRow = Expression<String?>("thumbnailUrl")
    nonisolated(unsafe) static let textRowId = Expression<Int64?>("textRowId")

    nonisolated(unsafe) static let titleRow = Expression<String?>("title")
    nonisolated(unsafe) static let descriptionRow = Expression<String?>("description")
    nonisolated(unsafe) static let contentRow = Expression<String?>("content")
    nonisolated(unsafe) static let keywordRow = Expression<String?>("keywords")
    nonisolated(unsafe) static let domainRow = Expression<String>("domain")
    nonisolated(unsafe) static let vectorRow = Expression<Blob>("vector")

    static let pragmas = """
    pragma synchronous = off;
    pragma temp_store = memory;
    pragma journal_mode = off;
    pragma locking_mode = exclusive;
    """
}
