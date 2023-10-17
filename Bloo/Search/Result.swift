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
