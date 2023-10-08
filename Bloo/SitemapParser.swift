import Foundation

final class SitemapParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private let (locationHose, continuation) = AsyncThrowingStream<URL, Error>.makeStream()

    private var inLoc = false

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
    }

    func extract() async throws -> (siteLocations: Set<IndexEntry>, xmlLocations: Set<IndexEntry>) {
        parser.parse()
        var siteLocations = Set<IndexEntry>()
        var xmlUrls = Set<IndexEntry>()
        for try await url in locationHose {
            if url.pathExtension.caseInsensitiveCompare("xml") == .orderedSame {
                xmlUrls.insert(.pending(url: url.absoluteString, isSitemap: true))
            } else {
                siteLocations.insert(.pending(url: url.absoluteString, isSitemap: false))
            }
        }
        return (siteLocations, xmlUrls)
    }

    func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes _: [String: String] = [:]) {
        inLoc = elementName == "loc"
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        guard inLoc else {
            return
        }
        if let url = try? URL.create(from: string, relativeTo: nil, checkExtension: false) {
            continuation.yield(url)
        }
    }

    func parser(_: XMLParser, parseErrorOccurred parseError: Error) {
        continuation.finish(throwing: parseError)
    }

    func parserDidEndDocument(_: XMLParser) {
        continuation.finish()
    }
}
