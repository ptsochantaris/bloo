import CoreSpotlight
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

    init?(_ item: CSSearchableItem, searchTerms: [String]) {
        id = item.uniqueIdentifier
        terms = searchTerms

        let attributes = item.attributeSet
        guard let sourceUrl = URL(string: id), let sourceTitle = attributes.title, let contentDescription = attributes.contentDescription else {
            return nil
        }

        url = sourceUrl
        title = sourceTitle
        descriptionText = contentDescription
        displayDate = attributes.contentModificationDate
        thumbnailUrl = attributes.thumbnailURL
        keywords = attributes.keywords ?? []
    }

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
