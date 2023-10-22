import CoreSpotlight
import Foundation
import SQLite

extension Search {
    struct Result: Identifiable {
        let id: String
        let url: String
        let title: String
        let descriptionText: String
        let contentText: String?
        let displayDate: Date?
        let thumbnailUrl: URL?
        let keywords: [String]
        let terms: [String]

        private static func highlightedExcerpt(_ text: String, phrase: String) -> String {
            guard let range = text.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: nil) else {
                return text
            }

            let padding = 96
            let preferredExcerptWidth = 256

            var text = text
            text.replaceSubrange(range, with: "#[BLU\(text[range])ULB]#")
            let start = text.startIndex
            let end = text.endIndex
            let distanceFromStart = text.distance(from: start, to: range.lowerBound)
            let distanceToEnd = text.distance(from: range.upperBound, to: end)
            let leadingExpansion = min(padding, distanceFromStart)
            let tralingExpansion = min(padding, distanceToEnd)
            var excerptStart = text.index(range.lowerBound, offsetBy: -leadingExpansion)
            var excerptEnd = text.index(range.upperBound, offsetBy: tralingExpansion)
            let currentLength = text.distance(from: excerptStart, to: excerptEnd)
            if currentLength < preferredExcerptWidth {
                if excerptStart == start, excerptEnd != end {
                    let distanceToEnd = text.distance(from: excerptEnd, to: end)
                    let more = min(distanceToEnd, preferredExcerptWidth - currentLength)
                    excerptEnd = text.index(excerptEnd, offsetBy: more)
                } else if excerptStart != start, excerptEnd == end {
                    let distanceToStart = text.distance(from: start, to: excerptStart)
                    let more = min(distanceToStart, preferredExcerptWidth - currentLength)
                    excerptStart = text.index(excerptStart, offsetBy: -more)
                }
            }
            let excerptRange = excerptStart ..< excerptEnd
            let prefix = excerptStart == start ? "" : "…"
            let suffix = excerptEnd == end ? "" : "…"
            return "\(prefix)\(text[excerptRange])\(suffix)"
        }

        init(element: Row, terms: [String], relevantVector: Vector?) {
            id = (relevantVector?.sentence ?? "") + String(element[DB.rowId])
            url = element[DB.urlRow]
            displayDate = element[DB.lastModifiedRow]
            thumbnailUrl = URL(string: element[DB.thumbnailUrlRow] ?? "")
            keywords = element[DB.keywordRow]?.split(separator: ", ").map { String($0) } ?? []
            self.terms = terms

            let _title = element[DB.titleRow] ?? ""
            let _descriptionText = element[DB.descriptionRow] ?? ""
            let _contentText = element[DB.contentRow]

            if let manuallyHighlight = relevantVector?.sentence {
                title = Self.highlightedExcerpt(_title, phrase: manuallyHighlight)
                descriptionText = Self.highlightedExcerpt(_descriptionText, phrase: manuallyHighlight)
                if let _contentText {
                    contentText = Self.highlightedExcerpt(_contentText, phrase: manuallyHighlight)
                } else {
                    contentText = _contentText
                }
            } else {
                title = _title
                descriptionText = _descriptionText
                contentText = _contentText
            }
        }

        var attributedTitle: AttributedString {
            title.highlightedAttributedString()
        }

        var attributedDescription: AttributedString {
            if let contentRes = contentText?.highlightedAttributedString() {
                return contentRes
            }
            return descriptionText.highlightedAttributedString()
        }

        var matchedKeywords: String? {
            var res = [String]()
            for term in terms {
                if let found = keywords.first(where: { $0.localizedCaseInsensitiveCompare(term) == .orderedSame }) {
                    res.append("#\(found)")
                }
            }
            return res.isEmpty ? nil : res.joined(separator: ", ")
        }

        func matchesFilter(_ filter: String) -> Bool {
            title.localizedCaseInsensitiveContains(filter) || descriptionText.localizedCaseInsensitiveContains(filter) || (contentText ?? "").localizedCaseInsensitiveContains(filter)
        }
    }
}
