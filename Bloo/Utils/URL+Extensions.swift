import Foundation

extension URL {
    static func create(from text: String, relativeTo: URL?, checkExtension: Bool) throws -> URL {
        guard text.isPopulated, text.isSaneLink else {
            throw Blooper.malformedUrl
        }

        guard let url = URL(string: text, relativeTo: relativeTo),
              url.scheme == "https",
              let host = url.host,
              host.contains("."),
              !checkExtension || !url.hasMediaExtension,
              !url.hasBlockedPath
        else {
            throw Blooper.malformedUrl
        }

        /* if host.hasPrefix("ci.") || host.hasPrefix("api.") || host.hasPrefix("mastodon.") {
             throw Blooper.blockedUrl
         } */

        let result: URL
        if relativeTo == nil {
            result = url
        } else if let resolved = URL(string: url.absoluteString) {
            result = resolved
        } else {
            throw Blooper.malformedUrl
        }

        return result.removingPathAfter("?").removingPathAfter("#")
    }

    private func removingPathAfter(_ string: String) -> URL {
        let segments = absoluteString.split(separator: string)
        if segments.count > 1, let first = segments.first, let resolved = URL(string: String(first)) {
            return resolved
        }
        return self
    }

    var hasMediaExtension: Bool {
        switch pathExtension {
        case "aac", "avi", "bmp", "doc", "exe", "gif", "gz", "jpeg", "jpg", "js", "json", "mid", "mp3", "mp4", "mpg", "pdf", "pkg", "png", "raw", "rss", "sig", "svg", "txt", "wav", "webp", "xhtml", "xls", "xml", "zip":
            true
        default:
            false
        }
    }

    var hasBlockedPath: Bool {
        let p = path()
        return p.hasSuffix("/login")
            || p.hasSuffix("wp-login.php")
    }
}

extension URLResponse {
    var guessedEncoding: String.Encoding {
        if let encodingName = textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
            if cfEncoding == kCFStringEncodingInvalidId {
                return .utf8
            } else {
                let swiftEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
                return String.Encoding(rawValue: swiftEncoding)
            }
        } else {
            return .utf8
        }
    }
}
