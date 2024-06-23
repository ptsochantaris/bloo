import Foundation
import SQLite

enum DB {
    nonisolated(unsafe) static let rowId = SQLite.Expression<Int64>("rowid")
    nonisolated(unsafe) static let urlRow = SQLite.Expression<String>("url")
    nonisolated(unsafe) static let isSitemapRow = SQLite.Expression<Bool?>("isSitemap")
    nonisolated(unsafe) static let lastModifiedRow = SQLite.Expression<Date?>("lastModified")
    nonisolated(unsafe) static let etagRow = SQLite.Expression<String?>("etag")
    nonisolated(unsafe) static let thumbnailUrlRow = SQLite.Expression<String?>("thumbnailUrl")
    nonisolated(unsafe) static let textRowId = SQLite.Expression<Int64?>("textRowId")

    nonisolated(unsafe) static let titleRow = SQLite.Expression<String?>("title")
    nonisolated(unsafe) static let descriptionRow = SQLite.Expression<String?>("description")
    nonisolated(unsafe) static let contentRow = SQLite.Expression<String?>("content")
    nonisolated(unsafe) static let keywordRow = SQLite.Expression<String?>("keywords")
    nonisolated(unsafe) static let domainRow = SQLite.Expression<String>("domain")
    nonisolated(unsafe) static let vectorRow = SQLite.Expression<Blob>("vector")

    static let pragmas = """
    pragma synchronous = off;
    pragma temp_store = memory;
    pragma journal_mode = off;
    pragma locking_mode = exclusive;
    """
}
