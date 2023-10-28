import Foundation

enum Network {
    private static let urlCache = {
        let meg = 1000 * 1000
        let gig = 1000 * meg
        #if os(iOS)
            return URLCache(memoryCapacity: 40 * meg, diskCapacity: 4 * gig)
        #elseif os(macOS)
            return URLCache(memoryCapacity: 1000 * meg, diskCapacity: 10 * gig)
        #endif
    }()

    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpShouldUsePipelining = true
        config.httpShouldSetCookies = false
        config.waitsForConnectivity = true
        config.httpCookieAcceptPolicy = .never
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Bloo/1.0.0"]
        config.timeoutIntervalForRequest = 20.0
        config.urlCache = urlCache
        return URLSession(configuration: config)
    }()

    private static let httpModifiedSinceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, dd LLL yyyy HH:mm:ss zzz"
        return formatter
    }()

    static func getData(from link: String, lastVisited: Date? = nil, lastEtag: String? = nil) async -> (Data, HTTPURLResponse)? {
        guard let url = URL(string: link) else {
            return nil
        }
        return await getData(for: URLRequest(url: url), lastVisited: lastVisited, lastEtag: lastEtag)
    }

    static func getData(from url: URL) async -> (Data, HTTPURLResponse) {
        await getData(for: URLRequest(url: url), lastVisited: nil, lastEtag: nil)
    }

    static func getData(for request: URLRequest, lastVisited: Date? = nil, lastEtag: String? = nil) async -> (Data, HTTPURLResponse) {
        var request = request

        if let lastEtag {
            request.setValue(lastEtag, forHTTPHeaderField: "If-None-Match")
            request.cachePolicy = .reloadIgnoringLocalCacheData
        } else if let lastVisited {
            let dateString = httpModifiedSinceFormatter.string(from: lastVisited)
            request.setValue(dateString, forHTTPHeaderField: "If-Modified-Since")
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }

        var attempts = 10
        while true {
            do {
                let res = try await urlSession.data(for: request)
                return (res.0, res.1 as! HTTPURLResponse)
            } catch {
                let location = request.url!.absoluteString
                let code = (error as NSError).code
                attempts -= 1
                if attempts == 0 {
                    Log.app(.info).log("Giving up after multiple connection failures to \(location)")
                    return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: [:])!)
                } else if code == -1007 { // too many redirects
                    Log.app(.info).log("Too many redirects to \(location), giving up")
                    return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: [:])!)
                } else if Task.isCancelled {
                    Log.app(.info).log("Task was cancelled to \(location), giving up")
                    return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: [:])!)
                } else {
                    Log.app(.error).log("Connection error to \(location), retrying in a moment: \(error.localizedDescription) - code: \(code)")
                    try? await Task.sleep(for: .seconds(6))
                }
            }
        }
    }

    static func getImageData(from url: URL) async -> Data? {
        try? await urlSession.data(from: url).0
    }
}
