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

    func wordRanges(of substring: String, options: CompareOptions = []) -> [Range<Index>] {
        if substring.localizedCaseInsensitiveCompare(self) == .orderedSame {
            return [startIndex ..< endIndex]
        }

        var ranges: [Range<Index>] = []
        let word = " \(substring) "
        while let range = range(of: word, options: options, range: (ranges.last?.upperBound ?? startIndex) ..< endIndex) {
            ranges.append(range)
        }
        // first word?
        if let fr = range(of: "\(substring) ", options: options), fr.lowerBound == startIndex {
            ranges.append(fr)
        }
        // last word?
        var options = options
        options.insert(.backwards)
        if let lr = range(of: " \(substring)", options: options), lr.upperBound == endIndex {
            ranges.append(lr)
        }
        return ranges
    }

    func highlightedAttributedString(_ terms: [String]) -> (text: AttributedString, firstMatchRange: Range<AttributedString.Index>?) {
        var attributedString = AttributedString(self)
        var firstMatchRange: Range<AttributedString.Index>?
        for term in terms {
            let ranges = wordRanges(of: term, options: [.caseInsensitive, .diacriticInsensitive])
            for range in ranges {
                let plainStart = distance(from: startIndex, to: range.lowerBound)
                let plainLength = distance(from: range.lowerBound, to: range.upperBound)
                let attributedStart = attributedString.index(attributedString.startIndex, offsetByCharacters: plainStart)
                let attributedEnd = attributedString.index(attributedStart, offsetByCharacters: plainLength)
                let newRange = attributedStart ..< attributedEnd
                attributedString[newRange].foregroundColor = .accent
                if firstMatchRange == nil {
                    firstMatchRange = newRange
                }
            }
        }
        return (text: attributedString, firstMatchRange: firstMatchRange)
    }
}

extension AttributedString {
    func clippedAround(_ range: Range<AttributedString.Index>) -> AttributedString {
        let padding = 128

        let leadingDistance = characters.distance(from: startIndex, to: range.lowerBound)
        if leadingDistance <= padding {
            return self
        }

        let finalRangeLower = index(range.lowerBound, offsetByCharacters: -padding)
        var clipped = AttributedString(self[finalRangeLower ..< endIndex])
        clipped.insert(AttributedString("..."), at: clipped.startIndex)
        return clipped
    }
}
