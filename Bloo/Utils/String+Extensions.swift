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

    func highlightedAttributedStirng(_ terms: [String]) -> AttributedString {
        var attributedString = AttributedString(self)
        for term in terms {
            let ranges = wordRanges(of: term, options: [.caseInsensitive, .diacriticInsensitive])
            for range in ranges {
                let plainStart = distance(from: startIndex, to: range.lowerBound)
                let plainLength = distance(from: range.lowerBound, to: range.upperBound)
                let attributedStart = attributedString.index(attributedString.startIndex, offsetByCharacters: plainStart)
                let attributedEnd = attributedString.index(attributedStart, offsetByCharacters: plainLength)
                attributedString[attributedStart ..< attributedEnd].foregroundColor = .accent
            }
        }
        return attributedString
    }
}
