import CoreSpotlight
import Foundation
import NaturalLanguage

extension CSSearchableItem {
    private static func storeImageData(_ data: Data, for id: String) -> URL {
        let uuid = UUID().uuidString
        let first = String(uuid[uuid.startIndex ... uuid.index(uuid.startIndex, offsetBy: 1)])
        let second = String(uuid[uuid.index(uuid.startIndex, offsetBy: 2) ... uuid.index(uuid.startIndex, offsetBy: 3)])

        let domainPath = domainPath(for: id)
        let location = domainPath.appendingPathComponent("thumbnails", isDirectory: true)
            .appendingPathComponent(first, isDirectory: true)
            .appendingPathComponent(second, isDirectory: true)

        let fm = FileManager.default
        if !fm.fileExists(atPath: location.path(percentEncoded: false)) {
            try! fm.createDirectory(at: location, withIntermediateDirectories: true)
        }
        let fileUrl = location.appendingPathComponent(uuid + ".jpg", isDirectory: false)
        try! data.write(to: fileUrl)
        return fileUrl
    }

    convenience init?(title: String, text: String, indexEntry: IndexEntry, thumbnailUrl: URL?, contentDescription: String?, id: String, creationDate: Date?, keywords: [String]?) async {
        let imageFileUrl = Task<URL?, Never>.detached {
            if let thumbnailUrl,
               let data = try? await urlSession.data(from: thumbnailUrl).0,
               let image = data.asImage?.limited(to: CGSize(width: 512, height: 512)),
               let dataToSave = image.jpegData {
                return Self.storeImageData(dataToSave, for: id)
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
        attributes.title = title
        if let keywords {
            attributes.keywords = keywords
        } else {
            attributes.keywords = await CSSearchableItem.generateKeywords(from: text)
        }
        attributes.thumbnailURL = await imageFileUrl.value

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
