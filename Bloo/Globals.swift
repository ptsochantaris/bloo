import Foundation
import OSLog

func log(_ text: String) {
    os_log("%{public}@", text)
}

extension Collection {
    var isPopulated: Bool {
        !isEmpty
    }
}

enum Blooper: Error {
    case malformedUrl
    case coreSpotlightNotEnabled
    case blockedUrl
}

let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("storage.noindex", isDirectory: true)

func domainPath(for id: String) -> URL {
    documentsPath.appendingPathComponent(id, isDirectory: true)
}

enum Network {
    static private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpShouldUsePipelining = true
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Bloo/1.0.0"]
        config.timeoutIntervalForRequest = 20.0
        let meg = 1000 * 1000
        let gig = 1000 * meg
        #if os(iOS)
        config.urlCache = URLCache(memoryCapacity: 40 * meg, diskCapacity: 4 * gig)
        #elseif os(macOS)
        config.urlCache = URLCache(memoryCapacity: 1000 * meg, diskCapacity: 10 * gig)
        #endif
        return URLSession(configuration: config)
    }()

    private static let httpModifiedSinceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, dd LLL yyyy HH:mm:ss zzz"
        return formatter
    }()

    static func getData(from url: URL, since date: Date? = nil) async throws -> (Data, HTTPURLResponse) {
        try await getData(for: URLRequest(url: url), since: date)
    }

    static func getData(for request: URLRequest, since date: Date? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = request
        if let date {
            let dateString = httpModifiedSinceFormatter.string(from: date)
            request.setValue(dateString, forHTTPHeaderField: "If-Modified-Since")
        }

        let res = try await urlSession.data(for: request)
        return (res.0, res.1 as! HTTPURLResponse)
    }
}

