import Foundation
import SQLite

extension SQLite.Expression: @retroactive @unchecked Sendable {}

enum DB {
    static let rowId = SQLite.Expression<Int64>("rowid")
    static let urlRow = SQLite.Expression<String>("url")
    static let isSitemapRow = SQLite.Expression<Bool?>("isSitemap")
    static let lastModifiedRow = SQLite.Expression<Date?>("lastModified")
    static let etagRow = SQLite.Expression<String?>("etag")
    static let thumbnailUrlRow = SQLite.Expression<String?>("thumbnailUrl")
    static let textRowId = SQLite.Expression<Int64?>("textRowId")

    static let titleRow = SQLite.Expression<String?>("title")
    static let descriptionRow = SQLite.Expression<String?>("description")
    static let contentRow = SQLite.Expression<String?>("content")
    static let keywordRow = SQLite.Expression<String?>("keywords")
    static let domainRow = SQLite.Expression<String>("domain")
    static let vectorRow = SQLite.Expression<Blob>("vector")

    static let pragmas = """
    pragma synchronous = off;
    pragma temp_store = memory;
    pragma journal_mode = off;
    pragma locking_mode = exclusive;
    """
}
