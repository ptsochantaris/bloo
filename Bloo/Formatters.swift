import Foundation

enum Formatters {
    nonisolated(unsafe) static let isoFormatter = ISO8601DateFormatter()

    static let isoFormatter2: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "YYYY-MM-DDTHH:mm:SSZ"
        return formatter
    }()

    static let isoFormatter3: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "YYYY-MM-DD"
        return formatter
    }()

    static let httpHeaderDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE',' dd' 'MMM' 'yyyy HH':'mm':'ss zzz"
        return formatter
    }()

    static let httpModifiedSinceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, dd LLL yyyy HH:mm:ss zzz"
        return formatter
    }()

    nonisolated(unsafe) static let relativeTime: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.formattingContext = .standalone
        formatter.unitsStyle = .full
        return formatter
    }()

    nonisolated(unsafe) static func tryParsingCreatedDate(_ dateString: String) -> Date? {
        isoFormatter.date(from: dateString)
            ?? isoFormatter2.date(from: dateString)
            ?? isoFormatter3.date(from: dateString)
    }
}
