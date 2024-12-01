import Foundation

enum SitemapParser {
    private class Parser: NSObject, XMLParserDelegate {
        fileprivate typealias StreamType = AsyncThrowingStream<URL, Error>
        fileprivate let locationHose: StreamType

        private let continuation: StreamType.Continuation
        private var inLoc = false
        private let parser: XMLParser

        fileprivate init(data: Data) {
            (locationHose, continuation) = StreamType.makeStream()
            parser = XMLParser(data: data)
            super.init()
            parser.delegate = self
            parser.parse()
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

    static func extract(from data: Data) async throws -> (siteLocations: Set<IndexEntry>, xmlLocations: Set<IndexEntry>) {
        let parser = Parser(data: data)
        var siteLocations = Set<IndexEntry>()
        var xmlUrls = Set<IndexEntry>()
        for try await url in parser.locationHose {
            if url.pathExtension.caseInsensitiveCompare("xml") == .orderedSame {
                xmlUrls.insert(.pending(url: url.absoluteString, isSitemap: true))
            } else {
                siteLocations.insert(.pending(url: url.absoluteString, isSitemap: false))
            }
        }
        return (siteLocations, xmlUrls)
    }
}
