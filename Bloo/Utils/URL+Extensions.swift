import Foundation

extension URL {
    static func create(from text: String, relativeTo: URL?, checkExtension: Bool) throws -> URL {
        guard text.isPopulated,
              text.isSaneLink,
              let url = URL(string: text, relativeTo: relativeTo)?.standardized.absoluteURL,
              url.scheme == "https",
              url.host?.contains(".") == true,
              !checkExtension || !url.hasMediaExtension
        else {
            throw Blooper.malformedUrl
        }

        return url.removingPathAfter("?").removingPathAfter("#")
    }

    func normalisedForResults() -> String {
        var host = host() ?? ""
        if host.hasPrefix("www.") {
            host = String(host.dropFirst(4))
        }
        return host + path
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
        case "7z", "aac", "avi", "bmp", "dmg", "doc", "exe", "gif", "gz", "jpeg", "jpg", "js", "json", "mid", "mp3", "mp4", "mpg", "pdf", "pkg", "png", "raw", "rss", "sig", "svg", "txt", "wav", "webp", "xhtml", "xls", "xml", "zip":
            true
        default:
            false
        }
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
