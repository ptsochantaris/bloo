import Foundation

struct SearchResult: Identifiable {
    let id: String
    let title: String
    let url: URL
    let descriptionText: String
    let displayDate: Date?
    let thumbnailUrl: URL?
    let keywords: [String]
    let terms: [String]

    var attributedTitle: AttributedString {
        title.highlightedAttributedStirng(terms)
    }

    var attributedDescription: AttributedString {
        descriptionText.highlightedAttributedStirng(terms)
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
}
