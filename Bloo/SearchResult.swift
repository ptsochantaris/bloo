import Foundation

struct SearchResult: ModelItem {
    let id: String
    let title: String
    let url: URL
    let descriptionText: String
    let updatedAt: Date?
    let thumbnailUrl: URL?
    let terms: [String]
    let keywords: [String]

    init(id: String, title: String, url: URL, descriptionText: String, updatedAt: Date?, thumbnailUrl: URL?, keywords: [String], terms: [String]) {
        self.id = id
        self.title = title
        self.url = url
        self.descriptionText = descriptionText
        self.updatedAt = updatedAt
        self.thumbnailUrl = thumbnailUrl
        self.terms = terms
        self.keywords = keywords
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
