import CoreSpotlight
import Foundation
import Maintini
import NaturalLanguage
@preconcurrency import OrderedCollections
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

    fileprivate(set) var state = State.paused(0, 0, false, false) {
        didSet {
            if oldValue != state { // only report base enum changes
                Log.crawling(id, .default).log("Domain \(id) state is now \(state.logText)")
            }
        }
    }

    private let crawler: Crawler

    init(startingAt: String) async throws {
        let url = try URL.create(from: startingAt, relativeTo: nil, checkExtension: true)

        guard let id = url.host() else {
            throw Blooper.malformedUrl
        }

        self.id = id

        let snapshot = try await BlooCore.shared.data(for: id)
        state = snapshot.state
        crawler = try await Crawler(id: id, url: url.absoluteString, pending: snapshot.pending, indexed: snapshot.indexed)

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

    var shouldDispose: Bool {
        state == .deleting
    }

    private final actor Crawler {
        let id: String
        private let bootupEntry: IndexEntry
        private var robots: Robots?

        private var pending: OrderedCollections.OrderedSet<IndexEntry>
        private var indexed: OrderedCollections.OrderedSet<IndexEntry>
        private var spotlightQueue = [CSSearchableItem]()
        private var goTask: Task<Void, Never>?

        private var rejectionCache = OrderedCollections.OrderedSet<String>()

        @MainActor
        fileprivate weak var crawlerDelegate: CrawlerDelegate!

        fileprivate init(id: String, url: String, pending: OrderedCollections.OrderedSet<IndexEntry>, indexed: OrderedCollections.OrderedSet<IndexEntry>) async throws {
            self.id = id
            bootupEntry = .pending(url: url, isSitemap: false)
            self.indexed = indexed
            self.pending = pending
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

        fileprivate func start() async {
            let count = pending.count
            await signalState(.loading(count))
            startGoTask(priority: Settings.shared.indexingTaskPriority, signalStateChange: true)
        }

        private func startGoTask(priority: TaskPriority, signalStateChange: Bool) {
            goTask = Task(priority: priority) {
                await go(signalStateChange: signalStateChange)
            }
        }

        fileprivate func pause(resumable: Bool) async {
            let newState = State.paused(indexed.count, pending.count, true, resumable)
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
            Log.crawling(id, .default).log("Resetting domain \(id)")
            pending.removeAll()
            indexed.removeAll()
            await BlooCore.shared.clearDomainSpotlight(for: id)
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
            Log.crawling(id, .default).log("Domain deleted: \(id)")
        }

        private func parseSitemap(at url: String) async {
            guard let xmlData = try? await Network.getData(from: url).0 else {
                Log.crawling(id, .error).log("Failed to fetch sitemap data from \(url)")
                return
            }
            Log.crawling(id, .default).log("Fetched sitemap from \(url)")
            do {
                var (newUrls, newSitemaps) = try await SitemapParser(data: xmlData).extract()
                Log.crawling(id, .default).log("Considering \(newSitemaps.count) further sitemap URLs")
                newSitemaps.subtract(indexed)
                newSitemaps.remove(.pending(url: url, isSitemap: true))
                if newSitemaps.isPopulated {
                    Log.crawling(id, .default).log("Adding \(newSitemaps.count) unindexed URLs from sitemap")
                    pending.formUnion(newSitemaps)
                }

                Log.crawling(id, .default).log("Considering \(newUrls.count) potential URLs from sitemap")
                newUrls.subtract(indexed)
                if newUrls.isPopulated {
                    Log.crawling(id, .default).log("Adding \(newUrls.count) unindexed URLs from sitemap")
                    pending.formUnion(newUrls)
                }

                await signalState(.indexing(indexed.count, pending.count, url), onlyIfActive: true)

            } catch {
                Log.crawling(id, .error).log("XML Parser error in \(url)")
            }
        }

        private static let requestLock = Semalot(tickets: 1)

        // TODO: Run update scans; use if-last-modified in HEAD requests, if available, and weed out the 304s

        private func scanRobots() async {
            let url = "https://\(id)/robots.txt"
            Log.crawling(id, .default).log("\(id) - Scanning \(url)")
            if let data = try? await Network.getData(from: url).0,
               let robotText = String(data: data, encoding: .utf8) {
                robots = Robots.parse(robotText)
            }
        }

        private func go(signalStateChange: Bool) async {
            await Maintini.startMaintaining()
            defer {
                Task {
                    await Maintini.endMaintaining()
                }
            }

            if signalStateChange {
                await signalState(.loading(pending.count))
            }

            await scanRobots()

            if indexed.isEmpty {
                let url = "https://\(id)/sitemap.xml"
                pending.append(.pending(url: url, isSitemap: true))

                if let providedSitemaps = robots?.sitemaps {
                    let sitemapEntries = providedSitemaps
                        .map { IndexEntry.pending(url: $0, isSitemap: true) }
                    pending.formUnion(sitemapEntries)
                }
                pending.append(bootupEntry)
            }
            pending.subtract(indexed)
            if pending.isEmpty {
                pending.append(bootupEntry)
            }

            if signalStateChange {
                await signalState(.loading(pending.count))
            }

            var operationCount = 0
            let originalPriority = Settings.shared.indexingTaskPriority
            while pending.isPopulated {
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

                let next = pending.removeFirst()
                let start = Date()
                switch next {
                case let .pending(nextUrl, isSitemap):
                    if isSitemap {
                        await parseSitemap(at: nextUrl)
                    } else if let newItem = await index(page: next) {
                        spotlightQueue.append(newItem)
                    }
                case .visited:
                    Log.crawling(id, .error).log("Warning: Already visited entry showed up in the `pending` list")
                }

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

                    let duration = max(0, 1 + start.timeIntervalSinceNow)
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
            await signalState(.done(indexed.count))
            await snapshot()
        }

        private func snapshot() async {
            let state = await currentState
            Log.storage(.default).log("Snapshotting \(id) with state \(state)")
            let item = Storage.Snapshot(id: id,
                                        state: state,
                                        items: spotlightQueue,
                                        pending: pending,
                                        indexed: indexed)
            spotlightQueue.removeAll(keepingCapacity: true)
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

        private func index(page entry: IndexEntry) async -> CSSearchableItem? {
            let link = entry.url

            guard let site = URL(string: link) else {
                Log.crawling(id, .error).log("Malformed URL: \(link)")
                return nil
            }

            await signalState(.indexing(indexed.count, pending.count, link), onlyIfActive: true)

            var headRequest = URLRequest(url: site)
            headRequest.httpMethod = "head"

            guard let response = try? await Network.getData(for: headRequest).1 else {
                Log.crawling(id, .error).log("No HEAD response from \(link)")
                return nil
            }

            guard let mimeType = response.mimeType, mimeType.hasPrefix("text/html") else {
                Log.crawling(id, .error).log("Not HTML in \(link)")
                return nil
            }

            guard let contentResult = try? await Network.getData(from: site) else {
                Log.crawling(id, .error).log("No content response from \(link)")
                return nil
            }

            guard let documentText = String(data: contentResult.0, encoding: contentResult.1.guessedEncoding) else {
                Log.crawling(id, .error).log("Cannot decode text from \(link)")
                return nil
            }

            guard let htmlDoc = try? SwiftSoup.parse(documentText, link) else {
                Log.crawling(id, .error).log("Cannot parse HTML from \(link)")
                return nil
            }

            guard let header = htmlDoc.head() else {
                Log.crawling(id, .error).log("Cannot parse header from \(link)")
                return nil
            }

            let title: String
            if let v = try? htmlDoc.title().trimmingCharacters(in: .whitespacesAndNewlines), v.isPopulated {
                title = v
            } else if let foundTitle = header.metaPropertyContent(for: "og:title") {
                title = foundTitle
            } else {
                Log.crawling(id, .error).log("No title located at \(link)")
                return nil
            }

            guard let textContent = try? htmlDoc.body()?.text() else {
                Log.crawling(id, .error).log("Cannot parse text in \(link)")
                return nil
            }

            let ogImage = header.metaPropertyContent(for: "og:image")
            let imageFileUrl = Task<URL?, Never>.detached { [id] in
                if let ogImage,
                   let thumbnailUrl = try? URL.create(from: ogImage, relativeTo: site, checkExtension: false),
                   let data = try? await Network.getData(from: thumbnailUrl).0,
                   let image = data.asImage?.limited(to: CGSize(width: 512, height: 512)),
                   let dataToSave = image.jpegData {
                    return Self.storeImageData(dataToSave, for: id)
                }
                return nil
            }

            let contentDescription = header.metaPropertyContent(for: "og:description")

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

            let lastModified: Date?
            let headers = contentResult.1.allHeaderFields
            if let lastModifiedHeader = (headers["Last-Modified"] ?? headers["last-modified"]) as? String, let lm = Self.httpHeaderDateFormatter.date(from: lastModifiedHeader) {
                lastModified = lm
            } else if let creationDate {
                lastModified = creationDate
            } else {
                lastModified = Self.generateDate(from: textContent)
            }

            var rankHint = 0
            let descriptionInfo = (contentDescription ?? "").isEmpty ? textContent : contentDescription
            let descriptionTokens = Set((descriptionInfo ?? "").split(separator: " "))
            if descriptionTokens.isPopulated, keywords.isPopulated {
                if let lastModified {
                    let time = lastModified.timeIntervalSinceNow
                    if time > -(3600 * 24) {
                        rankHint += 4
                    } else if time > -(3600 * 24 * 7) {
                        rankHint += 3
                    } else if time > -(3600 * 24 * 30) {
                        rankHint += 2
                    } else if time > -(3600 * 24 * 265) {
                        rankHint += 1
                    }
                }

                var numberOfKeywordsInTitle = 0
                var numberOfKeywordsInDescription = 0
                let titleTokens = Set(title.split(separator: " "))
                for keyword in keywords {
                    if titleTokens.contains(where: { $0.localizedCaseInsensitiveCompare(keyword) == .orderedSame }) {
                        numberOfKeywordsInTitle += 1
                    }
                    if descriptionTokens.contains(where: { $0.localizedCaseInsensitiveCompare(keyword) == .orderedSame }) {
                        numberOfKeywordsInDescription += 1
                    }
                }

                switch numberOfKeywordsInTitle {
                case 3...: rankHint += 3
                case 2: rankHint += 2
                case 1: rankHint += 1
                default: break
                }

                if numberOfKeywordsInTitle > 0, numberOfKeywordsInDescription > 0 {
                    rankHint += 1
                }

                switch numberOfKeywordsInDescription {
                case 3...: rankHint += 3
                case 2: rankHint += 2
                case 1: rankHint += 1
                default: break
                }
            }

            indexed.append(.visited(url: link, lastModified: lastModified))
            pending.formUnion(newUrls.subtracting(indexed))

            Log.crawling(id, .info).log("Indexed URL: \(link)")

            let attributes = CSSearchableItemAttributeSet(contentType: .url)
            attributes.keywords = keywords
            attributes.contentDescription = descriptionInfo
            attributes.title = title
            attributes.contentModificationDate = lastModified
            attributes.thumbnailURL = await imageFileUrl.value
            attributes.rankingHint = NSNumber(value: rankHint)
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

        private static func generateDate(from text: String) -> Date? {
            let types: NSTextCheckingResult.CheckingType = [.date]
            guard let detector = try? NSDataDetector(types: types.rawValue) else {
                return nil
            }
            return detector.firstMatch(in: text, range: NSRange(text.startIndex ..< text.endIndex, in: text))?.date
        }

        private static func generateKeywords(from text: String) -> [String] {
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
}