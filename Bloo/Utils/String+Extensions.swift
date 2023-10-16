import Foundation
import SwiftUI

extension String {
    var isSaneLink: Bool {
        !(self == "/"
            || contains("/feed/")
            || contains("/feeds/")
            || starts(with: "#")
            || starts(with: "?")
            || hasSuffix("/rss")
            || hasSuffix("/rss2")
            || hasSuffix("/feed"))
    }

    private static let highlightRegex = /\#\[BLU(.+?)ULB\]\#/

    func highlightedAttributedString() -> AttributedString {
        var attributedString = AttributedString(self)

        for match in matches(of: Self.highlightRegex).reversed() {
            let plainStart = distance(from: startIndex, to: match.range.lowerBound)
            let plainLength = distance(from: match.range.lowerBound, to: match.range.upperBound)
            let attributedStart = attributedString.index(attributedString.startIndex, offsetByCharacters: plainStart)
            let attributedEnd = attributedString.index(attributedStart, offsetByCharacters: plainLength)
            let newRange = attributedStart ..< attributedEnd
            var replacement = AttributedString(match.output.1)
            replacement.foregroundColor = .accent
            attributedString.replaceSubrange(newRange, with: replacement)
        }

        return attributedString
    }

    var sqlSafe: String {
        components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }
}
