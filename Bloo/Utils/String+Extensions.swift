import Foundation
import RegexBuilder
import SwiftUI

// Swift warning workaround
extension KeyPath<AttributeScopes.SwiftUIAttributes, AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute>: @retroactive @unchecked Sendable {}

extension AttributedString {
    func ranges(of text: String) -> [Range<AttributedString.Index>] {
        var ranges = [Range<AttributedString.Index>]()
        var start = startIndex
        let end = endIndex
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
            var count = 0
            var L = firstMatch.lowerBound
            var H = firstMatch.upperBound
            var lowerSpaceFound = false
            var upperSpaceFound = false
            let maxCount = 300
            let minCount = maxCount - 30
            while count < maxCount {
                let existingCount = count
                if L != attributedString.startIndex, !lowerSpaceFound {
                    if count > minCount, attributedString.characters[L] == " " {
                        lowerSpaceFound = true
                    } else {
                        L = attributedString.index(beforeCharacter: L)
                        count += 1
                    }
                }
                if H != attributedString.endIndex, !upperSpaceFound {
                    if count > minCount, attributedString.characters[H] == " " {
                        upperSpaceFound = true
                    } else {
                        H = attributedString.index(afterCharacter: H)
                        count += 1
                    }
                }
                if count == existingCount {
                    break
                }
            }
            if lowerSpaceFound, L != attributedString.endIndex {
                L = attributedString.index(afterCharacter: L)
            }
            attributedString = AttributedString(attributedString[L ..< H])
            if L != attributedString.startIndex {
                attributedString.insert(AttributedString("…"), at: attributedString.startIndex)
            }
            if H != attributedString.endIndex {
                attributedString.append(AttributedString("…"))
            }
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
