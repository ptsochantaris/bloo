import Foundation

final class SitemapParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private let (locationHose, continuation) = AsyncStream<URL>.makeStream()

    private var inLoc = false
    private var running = false

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
    }

    func extract() async -> (siteLocations: Set<IndexEntry>, xmlLocations: Set<IndexEntry>) {
        running = true
        parser.parse()
        var siteLocations = Set<IndexEntry>()
        var xmlUrls = Set<IndexEntry>()
        for await url in locationHose {
            if url.pathExtension.caseInsensitiveCompare("xml") == .orderedSame {
                xmlUrls.insert(IndexEntry(url: url))
            } else {
                siteLocations.insert(IndexEntry(url: url))
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
        log("XML parser error: \(parseError.localizedDescription)")
        running = false
        continuation.finish()
    }

    func parserDidEndDocument(_: XMLParser) {
        running = false
        continuation.finish()
    }
}
