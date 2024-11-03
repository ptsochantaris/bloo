import Foundation
import SwiftUI

// Swift warning workaround
extension KeyPath<AttributeScopes.SwiftUIAttributes, AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute>: @retroactive @unchecked Sendable {}

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

    private nonisolated(unsafe) static let regex = /\#\[BLU(.+?)ULB\]\#/.dotMatchesNewlines()

    func highlightedAttributedString() -> AttributedString {
        let text = String(unicodeScalars.filter { !$0.properties.isJoinControl })
        var attributedString = AttributedString(text)

        for match in text.matches(of: Self.regex).reversed() {
            let L = match.range.lowerBound
            let plainStart = text.distance(from: text.startIndex, to: L)

            let U = match.range.upperBound
            let plainLength = text.distance(from: L, to: U)

            let attributedStart = attributedString.index(attributedString.startIndex, offsetByCharacters: plainStart)
            let attributedEnd = attributedString.index(attributedStart, offsetByCharacters: plainLength)

            var replacement = AttributedString(match.output.1)
            replacement.foregroundColor = .accent
            attributedString.replaceSubrange(attributedStart ..< attributedEnd, with: replacement)
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
