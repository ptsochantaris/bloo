import CoreSpotlight
import Foundation
import NaturalLanguage

extension CSSearchableItem {
    convenience init?(title: String, text: String, indexEntry: IndexEntry, thumbnailUrl: URL?, contentDescription: String?, id: String, creationDate: Date?, keywords: [String]?) async {
        let imageData = Task<URL?, Never>.detached {
            if let thumbnailUrl,
               let data = try? await urlSession.data(from: thumbnailUrl).0,
               let image = data.asImage?.limited(to: CGSize(width: 512, height: 512)),
               let dataToSave = image.jpegData {
                return await Model.shared.storeImageData(dataToSave, for: id)
            }
            return nil
        }

        guard case let .visited(lastModified) = indexEntry.state else {
            return nil
        }

        let attributes = CSSearchableItemAttributeSet(contentType: .url)
        if let creationDate {
            attributes.contentModificationDate = creationDate
        } else if let cd = await CSSearchableItem.generateDate(from: text) {
            attributes.contentModificationDate = cd
        } else {
            attributes.contentModificationDate = lastModified
        }
        attributes.contentDescription = (contentDescription ?? "").isEmpty ? text : contentDescription
        attributes.textContent = text
        attributes.title = title
        if let keywords {
            attributes.keywords = keywords
        } else {
            attributes.keywords = await CSSearchableItem.generateKeywords(from: text)
        }
        attributes.thumbnailURL = await imageData.value

        self.init(uniqueIdentifier: indexEntry.url, domainIdentifier: id, attributeSet: attributes)
    }

    private static func generateDate(from text: String) async -> Date? {
        let types: NSTextCheckingResult.CheckingType = [.date]
        guard let detector = try? NSDataDetector(types: types.rawValue) else {
            return nil
        }
        var exracted: Date?
        detector.enumerateMatches(in: text, options: [], range: NSRange(text.startIndex ..< text.endIndex, in: text)) { result, _, stop in
            if let d = result?.date {
                exracted = d
                stop.pointee = true
            }
        }
        return exracted
    }

    private static func generateKeywords(from text: String) async -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let range = text.startIndex ..< text.endIndex
        let results = tagger.tags(in: range, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitOther, .omitPunctuation])
        let res = results.compactMap { token -> String? in
            guard let tag = token.0 else { return nil }
            switch tag {
            case .noun, .organizationName, .personalName, .placeName:
                return String(text[token.1])
            default:
                return nil
            }
        }
        return Array(Set(res))
    }
}
