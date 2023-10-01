import CoreSpotlight
import Foundation
import Maintini
import Semalot
import SwiftSoup
import SwiftUI

@MainActor
final class Domain: ObservableObject, Identifiable, CrawlerDelegate {
    let id: String
    let crawler: Crawler
    private let stateChangedHandler: (() -> Void)

    @Published var state = DomainState.paused(0, 0, false, false) {
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
        self.stateChangedHandler = handler
        let domainPath = documentsPath.appendingPathComponent(id, isDirectory: true)
        let (pending, indexed, state) = try await Model.shared.data(in: domainPath)
        self.state = state
        crawler = try await Crawler(id: id, url: url, domainPath: domainPath, pending: pending, indexed: indexed)
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

@MainActor
private protocol CrawlerDelegate: AnyObject {
    var state: DomainState { get set }
}

final actor Crawler {
    let id: String
    private let bootupEntry: IndexEntry
    private let domainPath: URL

    private var pending: PersistedSet
    private var indexed: PersistedSet
    private var spotlightQueue = [CSSearchableItem]()
    private var goTask: Task<Void, Never>?

    @MainActor
    fileprivate weak var crawlerDelegate: CrawlerDelegate!

    fileprivate init(id: String, url: URL, domainPath: URL, pending: PersistedSet, indexed: PersistedSet) async throws {
        self.id = id
        self.bootupEntry = IndexEntry(url: url)
        self.domainPath = domainPath
        self.indexed = indexed
        self.pending = pending
    }

    private func signalState(_ state: DomainState, onlyIfActive: Bool = false) {
        Task { @MainActor in
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

    fileprivate func start() {
        let count = pending.count
        goTask = Task {
            signalState(.loading(count))
            await go()
        }
    }

    fileprivate func pause(resumable: Bool) async {
        let newState = DomainState.paused(indexed.count, pending.count, true, resumable)
        if let g = goTask {
            signalState(newState)
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
        signalState(.loading(0))
        Task { @MainActor in
            let fm = FileManager.default
            if fm.fileExists(atPath: domainPath.path) {
                try! fm.removeItem(at: domainPath)
            }
            try! fm.createDirectory(at: domainPath, withIntermediateDirectories: true)
            await clearSpotlight()
            await start()
        }
    }

    fileprivate func remove() async {
        pending.removeAll()
        indexed.removeAll()
        signalState(.deleting)
        await clearSpotlight()
    }

    private func clearSpotlight() async {
        await Model.shared.clearDomainSpotlight(for: id)
        await snapshot()
    }

    deinit {
        log("Domain deleted: \(id)")
    }

    private func parseSitemap() async {
        guard let url = URL(string: "https://\(id)/sitemap.xml") else {
            return
        }

        log("\(id): Inspecting sitemap")

        let start = Date.now
        var map = Set<IndexEntry>([IndexEntry(url: url)])
        var extraPending = Set<IndexEntry>()
        var visited = Set<IndexEntry>()

        let siteMapLock = Semalot(tickets: 8)

        while map.isPopulated {
            let pendingChunk: Set<IndexEntry>
            (map, pendingChunk) = await withTaskGroup(of: (Set<IndexEntry>?, Set<IndexEntry>?).self, returning: (Set<IndexEntry>, Set<IndexEntry>).self) { group in
                for next in map where !visited.contains(next) {
                    visited.insert(next)
                    group.addTask { () -> (Set<IndexEntry>?, Set<IndexEntry>?) in
                        await siteMapLock.takeTicket()
                        defer {
                            siteMapLock.returnTicket()
                        }
                        let url = next.url
                        guard let xmlData = try? await urlSession.data(from: url).0 else {
                            log("Failed to fetch sitemap data from \(next.url.absoluteString)")
                            return (nil, nil)
                        }
                        log("Fetched sitemap from \(url.absoluteString)")
                        return await SitemapParser(data: xmlData).extract()
                    }
                }

                var allPending = Set<IndexEntry>()
                var allXml = Set<IndexEntry>()
                var passCount = 0
                for await (pending, xml) in group {
                    if let xml, xml.isPopulated {
                        allXml.formUnion(xml)
                        log("\(id) Further sitemaps from pass #\(passCount): \(xml.count)")
                    }
                    if let pending, pending.isPopulated {
                        allPending.formUnion(pending)
                        log("\(id) Further URLs from sitemap #\(passCount): \(pending.count)")
                    }
                    passCount += 1
                }
                return (allXml, allPending)
            }
            extraPending.formUnion(pendingChunk)
        }

        log("\(id): Considering \(extraPending.count) potential URLs from sitemap")
        indexed.remove(from: &extraPending)
        if extraPending.isPopulated {
            log("\(id): Adding \(extraPending.count) unindexed URLs from sitemap")
            pending.formUnion(extraPending)
        }
        log("\(id): Sitemap processing complete - \(-start.timeIntervalSinceNow) sec")
    }

    private func go() async {
        await Maintini.startMaintaining()
        defer {
            Task {
                await Maintini.endMaintaining()
            }
        }

        signalState(.loading(pending.count))
        if indexed.isEmpty {
            await parseSitemap()
            pending.insert(bootupEntry)
        }
        pending.subtract(indexed)
        if pending.isEmpty {
            pending.insert(bootupEntry)
        }
        signalState(.loading(pending.count))

        while let next = pending.removeFirst() {
            let start = Date()

            if let newItem = await index(page: next) {
                spotlightQueue.append(newItem)

                if spotlightQueue.count > 59 {
                    await snapshot()
                }
            }

            let currentState = await currentState
            guard currentState.isActive else {
                if case let .paused(x, y, busy, resumeOnLaunch) = currentState, busy {
                    signalState(.paused(x, y, false, resumeOnLaunch))
                }
                await snapshot()
                return
            }

            let duration = max(0, 1 + start.timeIntervalSinceNow)
            if duration > 0 {
                try? await Task.sleep(for: .seconds(duration))
            }
        }

        signalState(.done(indexed.count))
        await snapshot()
    }

    private func snapshot() async {
        let item = await Snapshotter.Item(domainName: id,
                                          state: currentState,
                                          items: spotlightQueue,
                                          pending: pending,
                                          indexed: indexed,
                                          domainRoot: domainPath)
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
        // TODO: Run update scans using last-modified

        let url = entry.url

        signalState(.indexing(indexed.count, pending.count, url), onlyIfActive: true)

        var headRequest = URLRequest(url: url)
        headRequest.httpMethod = "head"

        guard let response = try? await urlSession.data(for: headRequest).1 else {
            log("No HEAD response from \(url.absoluteString)")
            return nil
        }

        guard let mimeType = response.mimeType, mimeType.hasPrefix("text/html") else {
            log("Not HTML in \(url.absoluteString)")
            return nil
        }

        guard let contentResult = try? await urlSession.data(from: url) else {
            log("No content response from \(url.absoluteString)")
            return nil
        }

        guard let documentText = String(data: contentResult.0, encoding: contentResult.1.guessedEncoding) else {
            log("Cannot decode text from \(url.absoluteString)")
            return nil
        }

        guard let htmlDoc = try? SwiftSoup.parse(documentText, url.absoluteString) else {
            log("Cannot parse HTML from \(url.absoluteString)")
            return nil
        }

        let lastModified: Date?
        if let httpResponse = (contentResult.1 as? HTTPURLResponse)?.allHeaderFields, let lastModifiedHeader = (httpResponse["Last-Modified"] ?? httpResponse["last-modified"]) as? String {
            lastModified = Self.httpHeaderDateFormatter.date(from: lastModifiedHeader)
        } else {
            lastModified = nil
        }

        let headerTask = Task.detached { [id] in
            guard let header = htmlDoc.head() else {
                log("Cannot parse header from \(url.absoluteString)")
                return (String, String?, URL?, [URL], Date?, [String]?)?.none
            }

            let title: String
            if let v = try? htmlDoc.title().trimmingCharacters(in: .whitespacesAndNewlines), v.isPopulated {
                title = v
            } else if let foundTitle = header.metaPropertyContent(for: "og:title") {
                title = foundTitle
            } else {
                log("No title located at \(url.absoluteString)")
                return nil
            }

            let contentDescription = header.metaPropertyContent(for: "og:description")

            var thumbnailUrl: URL?
            if let ogImage = header.metaPropertyContent(for: "og:image") {
                thumbnailUrl = try? URL.create(from: ogImage, relativeTo: url, checkExtension: false)
            }

            let links = (try? htmlDoc.select("a[href]").compactMap { try? $0.attr("href") }) ?? []
            var newUrls = [URL]()
            for link in links {
                if let newUrl = try? URL.create(from: link, relativeTo: url, checkExtension: true),
                   newUrl.host()?.hasSuffix(id) == true,
                   url != newUrl,
                   await !self.indexed.contains(newUrl) {
                    newUrls.append(newUrl)
                }
            }

            let createdDateString = header.metaPropertyContent(for: "og:article:published_time") ?? header.datePublished ?? ""
            let creationDate = Self.isoFormatter.date(from: createdDateString) ?? Self.isoFormatter2.date(from: createdDateString) ?? Self.isoFormatter3.date(from: createdDateString)
            let keywords = header.metaNameContent(for: "keywords")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            return (title, contentDescription, thumbnailUrl, newUrls, creationDate, keywords)
        }

        guard let textContent = try? htmlDoc.body()?.text(trimAndNormaliseWhitespace: true) else {
            log("Cannot parse text in \(url.absoluteString)")
            return nil
        }

        guard let (title, contentDescription, thumbnailUrl, newUrls, creationDate, keywords) = await headerTask.value else {
            log("Could not parse metadata from \(url.absoluteString)")
            return nil
        }

        pending.formUnion(newUrls)

        let newEntry = IndexEntry(url: url, lastModified: lastModified)
        indexed.insert(newEntry)

        let thumbnailPath = domainPath.appendingPathComponent("thumbnails", isDirectory: true)

        return await CSSearchableItem(title: title, text: textContent, indexEntry: newEntry, thumbnailUrl: thumbnailUrl, contentDescription: contentDescription, domain: id, creationDate: creationDate, keywords: keywords, thumbnailPath: thumbnailPath)
    }
}
