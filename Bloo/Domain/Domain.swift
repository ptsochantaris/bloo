import CoreSpotlight
import Foundation
import Maintini
import NaturalLanguage
import OrderedCollections
import Semalot
import SwiftSoup
import SwiftUI

@MainActor
private protocol CrawlerDelegate: AnyObject {
    var state: Domain.State { get set }
}

@MainActor
@Observable
final class Domain: Identifiable, CrawlerDelegate, Sendable {
    let id: String

    fileprivate(set) var state = State.defaultState {
        didSet {
            if oldValue != state { // only report base enum changes
                Log.crawling(id, .default).log("Domain \(id) state is now \(state.logText)")
            }
        }
    }

    private let crawler: Crawler

    init(startingAt: String, postAddAction: PostAddAction) async throws {
        let url = try URL.create(from: startingAt, relativeTo: nil, checkExtension: true)

        guard let id = url.host() else {
            throw Blooper.malformedUrl
        }

        self.id = id

        state = .loading(postAddAction)
        crawler = try await Crawler(id: id, url: url.absoluteString)
        crawler.crawlerDelegate = self

        Task.detached {
            try await self.crawler.loadFromSnapshot(postAddAction: postAddAction)
        }
    }

    func restart(wipingExistingData: Bool) async throws {
        try await crawler.restart(wipingExistingData: wipingExistingData)
    }

    func pause(resumable: Bool) async throws {
        try await crawler.pause(resumable: resumable)
    }

    func start() async throws {
        try await crawler.start()
    }

    func remove() async throws {
        try await crawler.remove()
    }

    var shouldDispose: Bool {
        state == .deleting
    }

    nonisolated func matchesFilter(_ text: String) -> Bool {
        if text.isEmpty {
            return true
        }
        return id.localizedCaseInsensitiveContains(text)
    }

    private final actor Crawler {
        let id: String
        private let bootupEntry: IndexEntry
        private var robots: Robots?

        private var spotlightQueue = [CSSearchableItem]()
        private var spotlightInvalidationQueue = Set<String>()
        private var goTask: Task<Void, Error>?
        private let storage: CrawlerStorage

        private var rejectionCache = OrderedCollections.OrderedSet<String>()

        @MainActor
        fileprivate weak var crawlerDelegate: CrawlerDelegate!

        fileprivate init(id: String, url: String) async throws {
            self.id = id
            bootupEntry = .pending(url: url, isSitemap: false)
            storage = try CrawlerStorage(id: id)
        }

        fileprivate func loadFromSnapshot(postAddAction: PostAddAction) async throws {
            let snapshot = try await BlooCore.shared.data(for: id)
            await signalState(snapshot.state)

            switch postAddAction {
            case .none:
                break
            case .resumeIfNeeded:
                if snapshot.state.shouldResume {
                    try await start()
                }
            case .start:
                try await start()
            }
        }

        private func signalState(_ state: State, onlyIfActive: Bool = false) async {
            await MainActor.run {
                if !onlyIfActive || crawlerDelegate.state.isActive {
                    if crawlerDelegate.state != state {
                        // category change, animate
                        withAnimation {
                            crawlerDelegate.state = state
                        }
                    } else {
                        crawlerDelegate.state = state
                    }
                }
            }
        }

        @MainActor
        private var currentState: State {
            crawlerDelegate.state
        }

        fileprivate func start() async throws {
            let counts = try storage.counts
            await signalState(.starting(counts.indexed, counts.pending))
            startGoTask(priority: Settings.shared.indexingTaskPriority, signalStateChange: true)
        }

        private func startGoTask(priority: TaskPriority, signalStateChange: Bool) {
            goTask = Task(priority: priority) {
                Log.crawling(id, .info).log("Starting main loop")
                do {
                    try await go(signalStateChange: signalStateChange)
                } catch {
                    Log.crawling(id, .error).log("Failed in main loop: \(error.localizedDescription)")
                }
            }
        }

        fileprivate func pause(resumable: Bool) async throws {
            if let g = goTask {
                Log.crawling(id, .info).log("Pausing")
                let counts = try storage.counts
                let newState = State.paused(counts.indexed, counts.pending, true, resumable)
                await signalState(newState)
                goTask = nil
                try await g.value
            }
            Log.crawling(id, .info).log("Paused")
        }

        fileprivate func restart(wipingExistingData: Bool) async throws {
            if await currentState.isActive {
                return
            }
            Log.crawling(id, .default).log("Resetting domain \(id)")
            if wipingExistingData {
                try await storage.removeAll(purge: false)
                await BlooCore.shared.clearDomainSpotlight(for: id)
            } else {
                try storage.prepareForRefresh()
            }
            try await start()
            await snapshot()
        }

        fileprivate func remove() async throws {
            try await storage.removeAll(purge: true)
            await signalState(.deleting)
            await snapshot()
        }

        deinit {
            Log.crawling(id, .default).log("Domain deleted: \(id)")
        }

        private func parseSitemap(at url: String) async -> Set<IndexEntry>? {
            guard let xmlData = try? await Network.getData(from: url).0 else {
                Log.crawling(id, .error).log("Failed to fetch sitemap data from \(url)")
                return nil
            }
            Log.crawling(id, .default).log("Fetched sitemap from \(url)")
            do {
                let (newUrls, newSitemaps) = try await SitemapParser(data: xmlData).extract()
                Log.crawling(id, .default).log("Considering \(newSitemaps.count) further sitemap URLs")
                try storage.handleSitemapEntries(from: url, newSitemaps: newSitemaps)

                Log.crawling(id, .default).log("Considering \(newUrls.count) potential URLs from sitemap")
                return newUrls

            } catch {
                Log.crawling(id, .error).log("XML Parser error in \(url) - \(error.localizedDescription)")
                try? storage.handleSitemapEntries(from: url, newSitemaps: [])
                return nil
            }
        }

        private static let requestLock = Semalot(tickets: 1)

        private func scanRobots() async {
            let url = "https://\(id)/robots.txt"
            Log.crawling(id, .default).log("\(id) - Scanning \(url)")
            if let data = try? await Network.getData(from: url).0,
               let robotText = String(data: data, encoding: .utf8) {
                robots = Robots.parse(robotText)
            }
        }

        private func go(signalStateChange: Bool) async throws {
            await Maintini.startMaintaining()
            defer {
                Task {
                    await Maintini.endMaintaining()
                }
            }

            if signalStateChange {
                let counts = try storage.counts
                await signalState(.starting(counts.indexed, counts.pending))
            }

            await scanRobots()

            if try storage.counts.indexed == 0 {
                let url = "https://\(id)/sitemap.xml"
                try await storage.appendPending(.pending(url: url, isSitemap: true))

                if let providedSitemaps = robots?.sitemaps {
                    let sitemapEntries = providedSitemaps
                        .map { IndexEntry.pending(url: $0, isSitemap: true) }

                    try storage.appendPending(items: sitemapEntries)
                }

                try await storage.appendPending(bootupEntry)
            }

            try storage.substractIndexedFromPending()
            if try storage.counts.pending == 0 {
                try await storage.appendPending(bootupEntry)
            }

            if signalStateChange {
                let counts = try storage.counts
                await signalState(.starting(counts.indexed, counts.pending))
            }

            var operationCount = 0
            let originalPriority = Settings.shared.indexingTaskPriority
            while let next = try await storage.nextPending() {
                let setPriority = Settings.shared.indexingTaskPriority
                if originalPriority != setPriority {
                    defer {
                        Log.crawling(id, .default).log("Restarting crawler for \(id) becaues of priority change")
                        startGoTask(priority: setPriority, signalStateChange: false)
                    }
                    return
                }

                let willThrottle = Settings.shared.maxConcurrentIndexingOperations == 1
                if willThrottle {
                    await Self.requestLock.takeTicket()
                }

                let start = Date()
                let createdContent = try await crawl(entry: next)
                let counts = try storage.counts
                await signalState(.indexing(counts.indexed, counts.pending, next.url), onlyIfActive: true)

                // Detect stop
                let currentState = await currentState
                if currentState.isActive {
                    operationCount += 1
                    if operationCount > 59 {
                        operationCount = 0
                        await snapshot()
                    }
                    if willThrottle {
                        Self.requestLock.returnTicket()
                    }

                    let maxWait = createdContent ? 1 : 0.5
                    let duration = max(0, maxWait + start.timeIntervalSinceNow)
                    if duration > 0 {
                        try? await Task.sleep(for: .seconds(duration))
                    }

                } else {
                    if case let .paused(x, y, busy, resumeOnLaunch) = currentState, busy {
                        await signalState(.paused(x, y, false, resumeOnLaunch))
                    }
                    Log.crawling(id, .default).log("Stopping crawl because of app action")
                    await snapshot()
                    if willThrottle {
                        Self.requestLock.returnTicket()
                    }
                    return
                }
            }

            Log.crawling(id, .default).log("Stopping crawl because of completion")
            let counts = try storage.counts
            await signalState(.done(counts.indexed))
            await snapshot()
        }

        private func crawl(entry: IndexEntry) async throws -> Bool {
            var newEntries: Set<IndexEntry>?
            let indexResult: IndexResponse

            switch entry {
            case let .pending(url, isSitemap):
                if isSitemap {
                    newEntries = await parseSitemap(at: url)
                    indexResult = .noChange
                } else {
                    indexResult = try await index(page: url, lastModified: nil, lastEtag: nil)
                }
            case let .visited(url, lastModified, etag):
                indexResult = try await index(page: url, lastModified: lastModified, lastEtag: etag)
            }

            let newItem: IndexEntry?
            let newContent: IndexEntry.Content?

            switch indexResult {
            case .error:
                newContent = nil
                spotlightInvalidationQueue.insert(entry.url)
                newItem = nil

            case .noChange:
                newContent = nil
                newItem = nil

            case let .indexed(csEntry, createdItem, newPendingItems, content):
                newContent = content
                spotlightQueue.append(csEntry)
                newEntries = newPendingItems
                newItem = createdItem
            }

            try await storage.handleCrawlCompletion(newItem: newItem, url: entry.url, content: newContent, newEntries: newEntries)
            return newContent != nil
        }

        private func snapshot() async {
            let state = await currentState
            Log.storage(.default).log("Snapshotting \(id) with state \(state)")
            let item = Storage.Snapshot(id: id,
                                        state: state,
                                        items: spotlightQueue,
                                        removedItems: spotlightInvalidationQueue)
            spotlightQueue.removeAll(keepingCapacity: true)
            spotlightInvalidationQueue.removeAll(keepingCapacity: true)
            await BlooCore.shared.queueSnapshot(item: item)
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

        enum IndexResponse {
            case noChange, error, indexed(CSSearchableItem, IndexEntry, Set<IndexEntry>, IndexEntry.Content)
        }

        private func index(page link: String, lastModified: Date?, lastEtag: String?) async throws -> IndexResponse {
            guard let site = URL(string: link) else {
                Log.crawling(id, .error).log("Malformed URL: \(link)")
                return .error
            }

            let counts = try storage.counts
            await signalState(.indexing(counts.indexed, counts.pending, link), onlyIfActive: true)

            var headRequest = URLRequest(url: site)
            headRequest.httpMethod = "head"

            guard let headResponse = try? await Network.getData(for: headRequest, lastVisited: lastModified, lastEtag: lastEtag).1 else {
                Log.crawling(id, .error).log("No HEAD response from \(link)")
                return .error
            }

            if headResponse.statusCode >= 400 {
                Log.crawling(id, .info).log("No content (code \(headResponse.statusCode)) in \(link)")
                return .error
            }

            if headResponse.statusCode == 304 {
                Log.crawling(id, .info).log("No change (code 304) in \(link)")
                return .noChange
            }

            let headers = headResponse.allHeaderFields

            let etagFromHeaders = (headers["etag"] ?? headers["Etag"]) as? String

            if let etagFromHeaders, lastEtag == etagFromHeaders {
                Log.crawling(id, .info).log("No change (same etag) in \(link)")
                return .noChange
            }

            let lastModifiedHeaderDate: Date?
            if let lastModifiedHeaderString = (headers["Last-Modified"] ?? headers["last-modified"]) as? String, let lm = Self.httpHeaderDateFormatter.date(from: lastModifiedHeaderString) {
                if let lastModified, lastModified >= lm {
                    Log.crawling(id, .info).log("No change (same date) in \(link)")
                    return .noChange
                }
                lastModifiedHeaderDate = lm
            } else {
                lastModifiedHeaderDate = nil
            }

            guard let mimeType = headResponse.mimeType, mimeType.hasPrefix("text/html") else {
                Log.crawling(id, .error).log("Not HTML in \(link)")
                return .error
            }

            guard let contentResult = try? await Network.getData(from: site) else {
                Log.crawling(id, .error).log("No content response from \(link)")
                return .error
            }

            guard let documentText = String(data: contentResult.0, encoding: contentResult.1.guessedEncoding) else {
                Log.crawling(id, .error).log("Cannot decode text from \(link)")
                return .error
            }

            guard let htmlDoc = try? SwiftSoup.parse(documentText, link) else {
                Log.crawling(id, .error).log("Cannot parse HTML from \(link)")
                return .error
            }

            guard let header = htmlDoc.head() else {
                Log.crawling(id, .error).log("Cannot parse header from \(link)")
                return .error
            }

            let title: String
            if let v = try? htmlDoc.title().trimmingCharacters(in: .whitespacesAndNewlines), v.isPopulated {
                title = v
            } else if let foundTitle = header.metaPropertyContent(for: "og:title") {
                title = foundTitle
            } else {
                Log.crawling(id, .error).log("No title located at \(link)")
                return .error
            }

            guard let textContent = try? htmlDoc.body()?.text() else {
                Log.crawling(id, .error).log("Cannot parse text in \(link)")
                return .error
            }

            let ogImage = header.metaPropertyContent(for: "og:image")
            let imageFileUrl = Task<URL?, Never>.detached { [id] in
                if let ogImage,
                   let thumbnailUrl = try? URL.create(from: ogImage, relativeTo: site, checkExtension: false),
                   let data = try? await Network.getData(from: thumbnailUrl).0,
                   let image = data.asImage?.limited(to: CGSize(width: 512, height: 512)),
                   let dataToSave = image.jpegData {
                    return Self.storeImageData(dataToSave, for: id, sourceUrl: ogImage)
                }
                return nil
            }

            let summaryContent = header.metaPropertyContent(for: "og:description") ?? ""

            var newUrls = Set<IndexEntry>()

            var uniqued = Set<String>()
            let links = try? htmlDoc.select("a[href]")
                .compactMap { try? $0.attr("href").trimmingCharacters(in: .whitespacesAndNewlines) }
                .compactMap { try? URL.create(from: $0, relativeTo: site, checkExtension: true) }
                .filter { $0.host()?.hasSuffix(id) == true }
                .map(\.absoluteString)
                .filter { uniqued.insert($0).inserted }

            for newUrlString in links ?? [] {
                if let index = rejectionCache.firstIndex(of: newUrlString) {
                    let rejectionCount = rejectionCache.count
                    if rejectionCount > 400 {
                        rejectionCache.elements.move(fromOffsets: IndexSet(integer: index), toOffset: rejectionCount)
                        Log.crawling(id, .default).log("\(id) promoted rejected URL: \(newUrlString) - total: \(rejectionCount)")
                    }
                } else {
                    if link != newUrlString, robots?.agent("Bloo", canProceedTo: newUrlString) ?? true {
                        newUrls.insert(.pending(url: newUrlString, isSitemap: false))
                    } else {
                        rejectionCache.append(newUrlString)
                        let rejectionCount = rejectionCache.count
                        // log("\(id) added rejected URL: \(newUrlString) - total: \(rejectionCount)")
                        if rejectionCount == 500 {
                            rejectionCache = OrderedSet(rejectionCache.suffix(300))
                            Log.crawling(id, .default).log("\(id) Trimmed rejection cache: \(rejectionCache.count)")
                        }
                    }
                }
            }

            let createdDateString = header.metaPropertyContent(for: "og:article:published_time") ?? header.datePublished ?? ""
            let creationDate = Self.isoFormatter.date(from: createdDateString) ?? Self.isoFormatter2.date(from: createdDateString) ?? Self.isoFormatter3.date(from: createdDateString)
            let keywords = header
                .metaNameContent(for: "keywords")?.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                ?? Self.generateKeywords(from: textContent)

            let lastModified: Date? = if let lastModifiedHeaderDate {
                lastModifiedHeaderDate
            } else if let creationDate {
                creationDate
            } else {
                await SentenceEmbedding.generateDate(from: textContent)
            }

            var numberOfKeywordsInTitle = 0

            var numberOfKeywordsInDescription = 0

            var numberOfKeywordsInContent = 0

            for keyword in keywords {
                if title.localizedCaseInsensitiveContains(keyword) {
                    numberOfKeywordsInTitle += 1
                }

                if summaryContent.localizedCaseInsensitiveContains(keyword) {
                    numberOfKeywordsInDescription += 1
                }

                if textContent.localizedCaseInsensitiveContains(keyword) {
                    numberOfKeywordsInContent += 1
                }
            }

            let thumbnailUrl = await imageFileUrl.value
            let newContent = IndexEntry.Content(title: title, description: summaryContent, content: textContent, keywords: keywords.joined(separator: ", "), thumbnailUrl: thumbnailUrl?.absoluteString, lastModified: lastModified)
            let indexed = IndexEntry.visited(url: link, lastModified: lastModified, etag: etagFromHeaders)

            let attributes = CSSearchableItemAttributeSet(contentType: .url)
            attributes.keywords = keywords
            attributes.title = newContent.title
            attributes.contentDescription = newContent.description
            attributes.textContent = newContent.content
            attributes.contentModificationDate = newContent.lastModified
            attributes.thumbnailURL = thumbnailUrl
            return .indexed(CSSearchableItem(uniqueIdentifier: link, domainIdentifier: id, attributeSet: attributes), indexed, newUrls, newContent)
        }

        private static func storeImageData(_ data: Data, for id: String, sourceUrl: String) -> URL {
            let uuid = sourceUrl.hashString
            let first = String(uuid[uuid.startIndex ... uuid.index(uuid.startIndex, offsetBy: 2)])
            let second = String(uuid[uuid.index(uuid.startIndex, offsetBy: 3) ... uuid.index(uuid.startIndex, offsetBy: 5)])
            let third = String(uuid.dropFirst(6))

            let domainPath = domainPath(for: id)
            let location = domainPath.appendingPathComponent("thumbnails", isDirectory: true)
                .appendingPathComponent(first, isDirectory: true)
                .appendingPathComponent(second, isDirectory: true)

            let fm = FileManager.default
            if !fm.fileExists(atPath: location.path(percentEncoded: false)) {
                try! fm.createDirectory(at: location, withIntermediateDirectories: true)
            }
            let fileUrl = location.appendingPathComponent(third + ".jpg", isDirectory: false)
            try! data.write(to: fileUrl)
            return fileUrl
        }

        private static func generateKeywords(from text: String) -> [String] {
            let tagger = NLTagger(tagSchemes: [.nameType])
            tagger.string = text
            let range = text.wholeRange
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
}
