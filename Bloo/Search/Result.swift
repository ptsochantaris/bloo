import CoreSpotlight
import Foundation
import Lista
import SQLite

extension Search {
    struct Result: Identifiable {
        let id: String
        let url: String
        let title: String
        let descriptionText: String
        let displayDate: Date?
        let thumbnailUrl: URL?
        let keywords: [String]
        let terms: [String]
        let rowId: String
        let titleHashValueForResults: Int
        let bodyHashValueForResults: Int

        init(searchableItem: CSSearchableItem, terms: [String]) {
            rowId = searchableItem.uniqueIdentifier
            id = terms.joined(separator: ",") + String(rowId)
            url = searchableItem.uniqueIdentifier

            let attributes = searchableItem.attributeSet

            displayDate = attributes.contentCreationDate ?? attributes.contentModificationDate
            thumbnailUrl = attributes.thumbnailURL
            keywords = attributes.keywords ?? []
            self.terms = terms

            let _title = attributes.title
            title = _title ?? ""
            descriptionText = attributes.contentDescription ?? ""
            bodyHashValueForResults = descriptionText.hashValue
            titleHashValueForResults = (_title?.hashValue) ?? bodyHashValueForResults
        }

        var attributedTitle: AttributedString {
            title.highlightedAttributedString(terms: terms)
        }

        var attributedDescription: AttributedString {
            descriptionText.highlightedAttributedString(terms: terms)
        }

        var matchedKeywords: String? {
            let res = Lista<String>()
            for term in terms {
                if let found = keywords.first(where: { $0.localizedCaseInsensitiveCompare(term) == .orderedSame }) {
                    res.append("#\(found)")
                }
            }
            return res.isEmpty ? nil : res.joined(separator: ", ")
        }

        func matchesFilter(_ filter: String) -> Bool {
            title.localizedCaseInsensitiveContains(filter) || descriptionText.localizedCaseInsensitiveContains(filter)
        }
    }
}
