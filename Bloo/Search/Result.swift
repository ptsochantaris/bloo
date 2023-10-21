import CoreSpotlight
import Foundation

extension Search {
    struct Result: Identifiable {
        let id: String
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

        init(id: String, title: String, descriptionText: String, contentText: String?, displayDate: Date?, thumbnailUrl: URL?, keywords: [String], terms: [String], manuallyHighlight: String?) {
            self.id = id
            self.displayDate = displayDate
            self.thumbnailUrl = thumbnailUrl
            self.keywords = keywords
            self.terms = terms

            if let manuallyHighlight {
                self.title = Self.highlightedExcerpt(title, phrase: manuallyHighlight)
                self.descriptionText = Self.highlightedExcerpt(descriptionText, phrase: manuallyHighlight)
                if let contentText {
                    self.contentText = Self.highlightedExcerpt(contentText, phrase: manuallyHighlight)
                } else {
                    self.contentText = contentText
                }
            } else {
                self.title = title
                self.descriptionText = descriptionText
                self.contentText = contentText
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

        var url: URL? {
            URL(string: id)
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
