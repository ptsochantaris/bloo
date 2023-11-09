import Foundation
import SQLite

enum DB {
    static let rowId = Expression<Int64>("rowid")
    static let urlRow = Expression<String>("url")
    static let isSitemapRow = Expression<Bool?>("isSitemap")
    static let lastModifiedRow = Expression<Date?>("lastModified")
    static let etagRow = Expression<String?>("etag")
    static let thumbnailUrlRow = Expression<String?>("thumbnailUrl")
    static let textRowId = Expression<Int64?>("textRowId")

    static let titleRow = Expression<String?>("title")
    static let descriptionRow = Expression<String?>("description")
    static let contentRow = Expression<String?>("content")
    static let keywordRow = Expression<String?>("keywords")
    static let domainRow = Expression<String>("domain")

    static let resultIdentifierRow = Expression<Int64>("resultIdentifier")
    static let vectorRow = Expression<Blob>("vector")

    static let pragmas = """
    pragma synchronous = off;
    pragma temp_store = memory;
    pragma journal_mode = off;
    pragma locking_mode = exclusive;
    """
}
