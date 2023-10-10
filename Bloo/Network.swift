import Foundation

enum Network {
    private static let urlSession: URLSession = {
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

    static func getData(from link: String, lastVisited: Date? = nil, lastEtag: String? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: link) else {
            throw Blooper.malformedUrl
        }
        return try await getData(for: URLRequest(url: url), lastVisited: lastVisited, lastEtag: lastEtag)
    }

    static func getData(from url: URL, lastVisited: Date? = nil, lastEtag: String? = nil) async throws -> (Data, HTTPURLResponse) {
        try await getData(for: URLRequest(url: url), lastVisited: lastVisited, lastEtag: lastEtag)
    }

    static func getData(for request: URLRequest, lastVisited: Date? = nil, lastEtag: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = request

        if let lastEtag {
            request.setValue(lastEtag, forHTTPHeaderField: "If-None-Match")
            request.cachePolicy = .reloadIgnoringLocalCacheData
        } else if let lastVisited {
            let dateString = httpModifiedSinceFormatter.string(from: lastVisited)
            request.setValue(dateString, forHTTPHeaderField: "If-Modified-Since")
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }

        let res = try await urlSession.data(for: request)
        return (res.0, res.1 as! HTTPURLResponse)
    }
}
