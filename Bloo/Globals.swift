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

let urlSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.httpShouldUsePipelining = true
    config.httpShouldSetCookies = false
    config.httpCookieAcceptPolicy = .never
    config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Bloo/1.0.0"]
    config.timeoutIntervalForRequest = 20.0
    return URLSession(configuration: config)
}()

let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("storage.noindex", isDirectory: true)

func domainPath(for id: String) -> URL {
    documentsPath.appendingPathComponent(id, isDirectory: true)
}
