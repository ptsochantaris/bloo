import Foundation
import SwiftUI

// Swift warning workaround
extension KeyPath<AttributeScopes.SwiftUIAttributes, AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute>: @unchecked Sendable {}

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

    func highlightedAttributedString() -> AttributedString {
        var attributedString = AttributedString(self)

        for match in matches(of: /\#\[BLU(.+?)ULB\]\#/).reversed() {
            let R = match.range
            let L = R.lowerBound
            let U = R.upperBound
            let plainStart = distance(from: startIndex, to: L)
            let plainLength = distance(from: L, to: U)
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
