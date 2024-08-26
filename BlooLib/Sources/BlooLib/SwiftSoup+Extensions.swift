import Foundation
import SwiftSoup
import HTMLString

public extension Element {
    var textBlocks: [String] {
        get throws {
            try getAllElements().compactMap { child in
                if child.tag().getName() == "div" {
                    let text = try child.text().removingHTMLEntities()
                    if text.count > 10 {
                        return text
                    }
                }
                return nil
            }
        }
    }

    private func meta(for tag: String, attribute: String) -> String? {
        if let metaTags = try? select("meta[\(attribute)=\"\(tag)\"]") {
            for node in metaTags {
                if let content = try? node.attr("content"), content.isPopulated {
                    return content
                }
            }
        }
        return nil
    }

    func metaPropertyContent(for tag: String) -> String? {
        meta(for: tag, attribute: "property")
    }

    func metaNameContent(for tag: String) -> String? {
        meta(for: tag, attribute: "name")
    }

    private nonisolated(unsafe) static let dateTimePublishedRegex = /\"dateTimePublished\"\:\s*?\"(.+?)\"/
    private nonisolated(unsafe) static let datePublishedRegex = /\"datePublished\"\:\s*?\"(.+?)\"/
    var datePublished: String? {
        guard let html = try? html() else {
            return nil
        }
        if let match = try? Element.dateTimePublishedRegex.firstMatch(in: html)?.output {
            return String(match.1)
        }
        if let match = try? Element.datePublishedRegex.firstMatch(in: html)?.output {
            return String(match.1)
        }
        return nil
    }
}
