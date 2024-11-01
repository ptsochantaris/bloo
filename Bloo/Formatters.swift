import Foundation

enum Formatters {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    private static let relativeStyle = Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide, locale: .autoupdatingCurrent, calendar: .autoupdatingCurrent, capitalizationContext: .standalone)
    private static let httpModifiedSinceStyle = Date.VerbatimFormatStyle(format: "\(weekday: .abbreviated), \(day: .twoDigits) \(month: .abbreviated) \(year: .defaultDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits) GMT", locale: posixLocale, timeZone: .gmt, calendar: .autoupdatingCurrent)

    private static let httpHeaderParseStrategy = httpModifiedSinceStyle.parseStrategy

    private static let isoParseStrategy1 = Date.ISO8601FormatStyle()
    private static let isoParseStrategy4 = Date.VerbatimFormatStyle(format: "\(year: .defaultDigits)", locale: posixLocale, timeZone: .autoupdatingCurrent, calendar: .autoupdatingCurrent).parseStrategy
    private static let isoParseStrategy10 = Date.VerbatimFormatStyle(format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)", locale: posixLocale, timeZone: .autoupdatingCurrent, calendar: .autoupdatingCurrent).parseStrategy
    private static let isoParseStrategy17 = Date.VerbatimFormatStyle(format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)T\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)Z", locale: posixLocale, timeZone: .gmt, calendar: .autoupdatingCurrent).parseStrategy
    private static let isoParseStrategy19 = Date.VerbatimFormatStyle(format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)T\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)Z", locale: posixLocale, timeZone: .gmt, calendar: .autoupdatingCurrent).parseStrategy

    static func relativeTime(since date: Date) -> String {
        relativeStyle.format(date)
    }

    static func httpModifiedSinceString(from date: Date) -> String {
        httpModifiedSinceStyle.format(date)
    }

    static func httpHeaderDate(from dateString: String) -> Date? {
        do {
            return try Date(dateString, strategy: httpHeaderParseStrategy)
        } catch {
            Log.app(.error).log("Warning, header date parsing failed: \(dateString), count: \(dateString.count), error: \(error)")
            return nil
        }
    }

    static func tryParsingCreatedDate(_ dateString: String) -> Date? {
        do {
            switch dateString.count {
            case 0:
                return nil
            case 4:
                return try isoParseStrategy4.parse(dateString)
            case 10:
                return try isoParseStrategy10.parse(dateString)
            case 17:
                return try isoParseStrategy17.parse(dateString)
            case 19:
                return try isoParseStrategy19.parse(dateString)
            default:
                return try isoParseStrategy1.parse(dateString)
            }
        } catch {
            Log.app(.error).log("Warning, date parsing failed: \(dateString), count: \(dateString.count), error: \(error)")
            return nil
        }
    }
}
