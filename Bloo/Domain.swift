import CoreSpotlight
import Foundation
import Maintini
import SwiftSoup
import SwiftUI
import NaturalLanguage

@MainActor
private protocol CrawlerDelegate: AnyObject {
    var state: DomainState { get set }
}

@MainActor
@Observable
final class Domain: Identifiable, CrawlerDelegate {
    let id: String
    let crawler: Crawler
    private let stateChangedHandler: () -> Void

    fileprivate(set) var state = DomainState.paused(0, 0, false, false) {
        didSet {
            if oldValue != state { // only handle base enum changes
                log("Domain \(id) state is now \(state.logText)")
                stateChangedHandler()
            }
        }
    }

    init(startingAt: String, handler: @escaping (() -> Void)) async throws {
        let url = try URL.create(from: startingAt, relativeTo: nil, checkExtension: true)

        guard let id = url.host() else {
            throw Blooper.malformedUrl
        }

        self.id = id
        stateChangedHandler = handler

        let snapshot = try await Model.shared.data(for: id)
        state = snapshot.state
        crawler = try await Crawler(id: id, url: url, pending: snapshot.pending, indexed: snapshot.indexed)

        crawler.crawlerDelegate = self
    }

    func restart() async {
        await crawler.restart()
    }

    func pause(resumable: Bool) async {
        await crawler.pause(resumable: resumable)
    }

    func start() async {
        await crawler.start()
    }

    func remove() async {
        await crawler.remove()
    }
}

final actor Crawler {
    let id: String
    private let bootupEntry: IndexEntry

    private var pending: IndexSet
    private var indexed: IndexSet
    private var spotlightQueue = [CSSearchableItem]()
    private var goTask: Task<Void, Never>?

    @MainActor
    fileprivate weak var crawlerDelegate: CrawlerDelegate!

    fileprivate init(id: String, url: URL, pending: IndexSet, indexed: IndexSet) async throws {
        self.id = id
        bootupEntry = IndexEntry(url: url, isSitemap: false)
        self.indexed = indexed
        self.pending = pending
    }

    private func signalState(_ state: DomainState, onlyIfActive: Bool = false) async {
        await MainActor.run {
            if !onlyIfActive || crawlerDelegate.state.isActive {
                crawlerDelegate.state = state
            }
        }
    }

    private var currentState: DomainState {
        get async {
            await crawlerDelegate.state
        }
    }

    fileprivate func start() async {
        let count = pending.count
        await signalState(.loading(count))
        goTask = Task {
            await go()
        }
    }

    fileprivate func pause(resumable: Bool) async {
        let newState = DomainState.paused(indexed.count, pending.count, true, resumable)
        if let g = goTask {
            await signalState(newState)
            goTask = nil
            await g.value
        }
    }

    fileprivate func restart() async {
        if await currentState.isActive {
            return
        }
        log("Resetting domain \(id)")
        pending.removeAll()
        indexed.removeAll()
        await Model.shared.clearDomainSpotlight(for: id)
        await start()
        await snapshot()
    }

    fileprivate func remove() async {
        pending.removeAll()
        indexed.removeAll()
        await signalState(.deleting)
        await snapshot()
    }

    deinit {
        log("Domain deleted: \(id)")
    }

    private func parseSitemap(at url: URL) async {
        guard let xmlData = try? await Network.getData(from: url).0 else {
            log("Failed to fetch sitemap data from \(url.absoluteString)")
            return
        }
        log("Fetched sitemap from \(url.absoluteString)")
        var (newUrls, newSitemaps) = await SitemapParser(data: xmlData).extract()

        log("\(id): Considering \(newSitemaps.count) further sitemap URLs")
        indexed.remove(from: &newSitemaps)
        if newSitemaps.isPopulated {
            log("\(id): Adding \(newSitemaps.count) unindexed URLs from sitemap")
            pending.formUnion(newSitemaps)
        }

        log("\(id): Considering \(newUrls.count) potential URLs from sitemap")
        indexed.remove(from: &newUrls)
        if newUrls.isPopulated {
            log("\(id): Adding \(newUrls.count) unindexed URLs from sitemap")
            pending.formUnion(newUrls)
        }

        await signalState(.indexing(indexed.count, pending.count, url), onlyIfActive: true)
    }

    private func go() async {
        await Maintini.startMaintaining()
        defer {
            Task {
                await Maintini.endMaintaining()
            }
        }

        await signalState(.loading(pending.count))
        if indexed.isEmpty {
            if let url = URL(string: "https://\(id)/sitemap.xml") {
                let sitemapEntry = IndexEntry(url: url, isSitemap: true)
                pending.insert(sitemapEntry)
            }
            pending.insert(bootupEntry)
        }
        pending.subtract(indexed)
        if pending.isEmpty {
            pending.insert(bootupEntry)
        }
        await signalState(.loading(pending.count))

        while let next = pending.removeFirst() {
            let start = Date()
            switch next.state {
            case let .pending(isSitemap):
                if isSitemap {
                    if let url = URL(string: next.url) {
                        await parseSitemap(at: url)
                    }
                } else {
                    if let newItem = await index(page: next) {
                        spotlightQueue.append(newItem)

                        if spotlightQueue.count > 59 {
                            await snapshot()
                        }
                    }
                }
            case .visited:
                // wuuuut
                continue
            }

            // Detect stop
            let currentState = await currentState
            guard currentState.isActive else {
                if case let .paused(x, y, busy, resumeOnLaunch) = currentState, busy {
                    await signalState(.paused(x, y, false, resumeOnLaunch))
                }
                log("\(id): Stopping crawl")
                await snapshot()
                return
            }

            let duration = max(0, 1 + start.timeIntervalSinceNow)
            if duration > 0 {
                try? await Task.sleep(for: .seconds(duration))
            }
        }

        await signalState(.done(indexed.count))
        await snapshot()
    }

    private func snapshot() async {
        let state = await currentState
        log("Snapshotting \(id) with state \(state)")
        let item = Snapshot(id: id,
                            state: state,
                            items: spotlightQueue,
                            pending: pending,
                            indexed: indexed)
        spotlightQueue.removeAll(keepingCapacity: true)
        await Model.shared.queueSnapshot(item: item)
    }

    private static let isoFormatter = ISO8601DateFormatter()

    private static let isoFormatter2: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "YYYY-MM-DDTHH:mm:SSZ"
        return formatter
    }()

    private static let isoFormatter3: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "YYYY-MM-DD"
        return formatter
    }()

    private static let httpHeaderDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE',' dd' 'MMM' 'yyyy HH':'mm':'ss zzz"
        return formatter
    }()

    private func index(page entry: IndexEntry) async -> CSSearchableItem? {
        // TODO: robots
        // TODO: Run update scans; use if-last-modified in HEAD requests, if available, and weed out the 304s

        let link = entry.url
        guard let site = URL(string: link) else {
            log("\(link) is not a valid URL")
            return nil
        }

        await signalState(.indexing(indexed.count, pending.count, site), onlyIfActive: true)

        var headRequest = URLRequest(url: site)
        headRequest.httpMethod = "head"

        guard let response = try? await Network.getData(for: headRequest).1 else {
            log("No HEAD response from \(link)")
            return nil
        }

        guard let mimeType = response.mimeType, mimeType.hasPrefix("text/html") else {
            log("Not HTML in \(link)")
            return nil
        }

        guard let contentResult = try? await Network.getData(from: site) else {
            log("No content response from \(link)")
            return nil
        }

        guard let documentText = String(data: contentResult.0, encoding: contentResult.1.guessedEncoding) else {
            log("Cannot decode text from \(link)")
            return nil
        }

        guard let htmlDoc = try? SwiftSoup.parse(documentText, link) else {
            log("Cannot parse HTML from \(link)")
            return nil
        }

        let headerTask = Task.detached { [id] in
            guard let header = htmlDoc.head() else {
                log("Cannot parse header from \(link)")
                return (String, String?, URL?, [URL], Date?, [String]?)?.none
            }

            let title: String
            if let v = try? htmlDoc.title().trimmingCharacters(in: .whitespacesAndNewlines), v.isPopulated {
                title = v
            } else if let foundTitle = header.metaPropertyContent(for: "og:title") {
                title = foundTitle
            } else {
                log("No title located at \(link)")
                return nil
            }

            let contentDescription = header.metaPropertyContent(for: "og:description")

            var thumbnailUrl: URL?
            if let ogImage = header.metaPropertyContent(for: "og:image") {
                thumbnailUrl = try? URL.create(from: ogImage, relativeTo: site, checkExtension: false)
            }

            let links = (try? htmlDoc.select("a[href]").compactMap { try? $0.attr("href") }) ?? []
            var newUrls = [URL]()
            for link in links {
                if let newUrl = try? URL.create(from: link, relativeTo: site, checkExtension: true),
                   newUrl.host()?.hasSuffix(id) == true,
                   site != newUrl,
                   await !self.indexed.contains(newUrl) {
                    newUrls.append(newUrl)
                }
            }

            let createdDateString = header.metaPropertyContent(for: "og:article:published_time") ?? header.datePublished ?? ""
            let creationDate = Self.isoFormatter.date(from: createdDateString) ?? Self.isoFormatter2.date(from: createdDateString) ?? Self.isoFormatter3.date(from: createdDateString)
            let keywords = header.metaNameContent(for: "keywords")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            return (title, contentDescription, thumbnailUrl, newUrls, creationDate, keywords)
        }

        guard let textContent = try? htmlDoc.body()?.text() else {
            log("Cannot parse text in \(link)")
            return nil
        }

        guard let (title, contentDescription, thumbnailUrl, newUrls, creationDate, keywords) = await headerTask.value else {
            log("Could not parse metadata from \(link)")
            return nil
        }

        let imageFileUrl = Task<URL?, Never>.detached { [id] in
            if let thumbnailUrl,
               let data = try? await Network.getData(from: thumbnailUrl).0,
               let image = data.asImage?.limited(to: CGSize(width: 512, height: 512)),
               let dataToSave = image.jpegData {
                return Self.storeImageData(dataToSave, for: id)
            }
            return nil
        }

        let lastModified = await Task.detached { () -> Date? in
            let headers = contentResult.1.allHeaderFields
            if let lastModifiedHeader = (headers["Last-Modified"] ?? headers["last-modified"]) as? String, let lm = Self.httpHeaderDateFormatter.date(from: lastModifiedHeader) {
                return lm
            } else if let creationDate {
                return creationDate
            } else {
                return await Self.generateDate(from: textContent)
            }
        }.value

        let attributes = CSSearchableItemAttributeSet(contentType: .url)
        if let keywords {
            attributes.keywords = keywords
        } else {
            attributes.keywords = await Self.generateKeywords(from: textContent)
        }
        attributes.contentDescription = (contentDescription ?? "").isEmpty ? textContent : contentDescription
        attributes.title = title
        attributes.contentModificationDate = lastModified
        attributes.thumbnailURL = await imageFileUrl.value

        let newEntry = IndexEntry(url: link, state: .visited(lastModified: lastModified))
        indexed.insert(newEntry)
        pending.formUnion(newUrls)

        /*
        log("""
            URL: \(newEntry.url)
            Modified: \(attributes.contentModificationDate?.description ?? "<none>")
            State: \(newEntry.state)
            """)
         */

        return CSSearchableItem(uniqueIdentifier: link, domainIdentifier: id, attributeSet: attributes)

    }

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

    private static func generateDate(from text: String) async -> Date? {
        let types: NSTextCheckingResult.CheckingType = [.date]
        guard let detector = try? NSDataDetector(types: types.rawValue) else {
            return nil
        }
        return detector.firstMatch(in: text, range: NSRange(text.startIndex ..< text.endIndex, in: text))?.date
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
