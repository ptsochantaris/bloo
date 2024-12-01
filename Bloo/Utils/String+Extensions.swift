import Foundation
import SwiftUI
import RegexBuilder

// Swift warning workaround
extension KeyPath<AttributeScopes.SwiftUIAttributes, AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute>: @retroactive @unchecked Sendable {}

extension AttributedString {
    func ranges(of text: String) -> [Range<AttributedString.Index>] {
        var ranges = [Range<AttributedString.Index>]()
        var start = self.startIndex
        let end = self.endIndex
        while let range = self[start ..< end].range(of: text, options: .caseInsensitive) {
            ranges.append(range)
            start = range.upperBound
        }
        return ranges
    }
}

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

    func highlightedAttributedString(terms: [String]) -> AttributedString {
        let text = String(unicodeScalars.filter { !$0.properties.isJoinControl })
        var attributedString = AttributedString(text)

        var matches: [Range<AttributedString.Index>] = []
        for term in terms {
            for match in attributedString.ranges(of: term).reversed() {
                matches.append(match)
                attributedString[match].foregroundColor = .accent
            }
        }

        let firstMatch = matches.min(by: { $0.lowerBound < $1.lowerBound })

        if let firstMatch {
            let lowerDistance = attributedString.characters.distance(from: attributedString.startIndex, to: firstMatch.lowerBound)
            let newLowerBound = attributedString.index(firstMatch.lowerBound, offsetByCharacters: -(min(lowerDistance, 200)))
            let upperDistance = attributedString.characters.distance(from: firstMatch.upperBound, to: attributedString.endIndex)
            let newUpperBound = attributedString.index(firstMatch.upperBound, offsetByCharacters: (min(upperDistance, 200)))

            attributedString = AttributedString(attributedString[newLowerBound ..< newUpperBound])
        }

        return attributedString
    }

    var sqlSafe: String {
        components(separatedBy: CharacterSet.alphanumerics.inverted).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hashString: String {
        var res = utf8.reduce(UInt64(5381)) { 127 * ($0 & 0x00FF_FFFF_FFFF_FFFF) + UInt64($1) }

        return withUnsafeBytes(of: &res) { pointer in
            (0 ..< 8).map { pointer.loadUnaligned(fromByteOffset: $0, as: UInt8.self) }.map { String($0, radix: 16) }.joined()
        }
    }

    var wholeRange: Range<String.Index> {
        startIndex ..< endIndex
    }

    var wholeNSRange: NSRange {
        NSRange(wholeRange, in: self)
    }

    func normalisedUrlForResults() -> String {
        if let url = URL(string: self) {
            return url.normalisedForResults()
        }
        return self
    }
}
