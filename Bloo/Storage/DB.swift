import Foundation
import SQLite

extension SQLite.Expression: @retroactive @unchecked Sendable {}

nonisolated enum DB {
    static let urlRow = SQLite.Expression<String>("url")
    static let isSitemapRow = SQLite.Expression<Bool?>("isSitemap")
    static let lastModifiedRow = SQLite.Expression<Date?>("lastModified")
    static let etagRow = SQLite.Expression<String?>("etag")

    static let pragmas = """
    pragma synchronous = off;
    pragma temp_store = memory;
    pragma journal_mode = off;
    pragma locking_mode = exclusive;
    """
}
