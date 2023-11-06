import CoreSpotlight
import Foundation
import HTMLString
import Maintini
import NaturalLanguage
import OrderedCollections
import Semalot
import SQLite
import SwiftSoup
import SwiftUI

final actor Crawler {
    private let id: String
    private let bootupEntry: IndexEntry
    private var robots: Robots?
    private var spotlightQueue = [CSSearchableItem]()
    private var spotlightInvalidationQueue = Set<String>()
    private var goTask: Task<Void, Error>?
    private var botRejectionCache = OrderedCollections.OrderedSet<String>()
    private var pending: TableWrapper
    private var visited: TableWrapper
    private var db: Connection?
    private static let requestLock = Semalot(tickets: 1)

    @MainActor
    weak var crawlerDelegate: Domain!

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

    init(id: String, url: String) async throws {
        self.id = id
        bootupEntry = .pending(url: url, isSitemap: false)

        let path = domainPath(for: id)
        let file = path.appending(path: "crawler.sqlite3", directoryHint: .notDirectory)
        let fm = FileManager.default
        if !fm.fileExists(atPath: path.path) {
            try fm.createDirectory(atPath: path.path, withIntermediateDirectories: true)
        }
        let c = try Connection(file.path)
        try c.run(DB.pragmas)
        db = c

        let tableId = id.replacingOccurrences(of: ".", with: "_")

        let pendingTable = Table("pending_\(tableId)")
        pending = try TableWrapper(table: pendingTable, in: c)

        let visitedTable = Table("visited_\(tableId)")
        visited = try TableWrapper(table: visitedTable, in: c)
    }

    deinit {
        Log.crawling(id, .default).log("Domain deleted: \(id)")
    }

    func loadFromSnapshot(postAddAction: Domain.PostAddAction) async throws {
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

    private func signalState(_ state: Domain.State, onlyIfActive: Bool = false) async {
        await MainActor.run {
            if !onlyIfActive || crawlerDelegate.state.isStartingOrIndexing {
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
    private var currentState: Domain.State {
        crawlerDelegate.state
    }

    func start() async throws {
        let counts = try counts()
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

    func pause(resumable: Bool) async throws {
        if let g = goTask {
            Log.crawling(id, .info).log("Pausing")
            let counts = try counts()
            let newState = Domain.State.pausing(counts.indexed, counts.pending, resumable)
            await signalState(newState)
            goTask = nil
            try await g.value
        }
        Log.crawling(id, .info).log("Paused")
    }

    func restart(wipingExistingData: Bool) async throws {
        if await currentState.isNotIdle {
            return
        }
        Log.crawling(id, .default).log("Resetting domain \(id)")
        if wipingExistingData {
            try await removeAll(purge: false)
            await BlooCore.shared.clearDomainSpotlight(for: id)
        } else {
            if let db {
                try pending.clear(purge: true, in: db)
                try visited.cloneAndClear(as: pending, in: db)
            }
        }
        try await start()
        await snapshot()
    }

    func remove() async throws {
        try await removeAll(purge: true)
        db = nil
        await signalState(.deleting)
        await snapshot()
    }

    private func parseSitemap(at url: String) async -> Set<IndexEntry>? {
        guard let xmlData = await HTTP.getData(from: url)?.0 else {
            Log.crawling(id, .error).log("Failed to fetch sitemap data from \(url)")
            return nil
        }
        Log.crawling(id, .default).log("Fetched sitemap from \(url)")
        do {
            let (newUrls, newSitemaps) = try await SitemapParser(data: xmlData).extract()
            Log.crawling(id, .default).log("Considering \(newSitemaps.count) further sitemap URLs")
            try handleSitemapEntries(from: url, newSitemaps: newSitemaps)

            Log.crawling(id, .default).log("Considering \(newUrls.count) potential URLs from sitemap")
            return newUrls

        } catch {
            Log.crawling(id, .error).log("XML Parser error in \(url) - \(error.localizedDescription)")
            try? handleSitemapEntries(from: url, newSitemaps: [])
            return nil
        }
    }

    private func scanRobots() async {
        let url = "https://\(id)/robots.txt"
        Log.crawling(id, .default).log("\(id) - Scanning \(url)")
        if let data = await HTTP.getData(from: url)?.0,
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
            let counts = try counts()
            await signalState(.starting(counts.indexed, counts.pending))
        }

        await scanRobots()

        if try counts().indexed == 0 {
            let url = "https://\(id)/sitemap.xml"
            try appendPending(.pending(url: url, isSitemap: true))

            if let providedSitemaps = robots?.sitemaps {
                let sitemapEntries = providedSitemaps
                    .map { IndexEntry.pending(url: $0, isSitemap: true) }

                try appendPending(items: sitemapEntries)
            }

            try appendPending(bootupEntry)
        }

        if let db {
            try pending.subtract(visited, in: db)
        }

        if try counts().pending == 0 {
            try appendPending(bootupEntry)
        }

        if signalStateChange {
            let counts = try counts()
            await signalState(.starting(counts.indexed, counts.pending))
        }

        var operationCount = 0
        let originalPriority = Settings.shared.indexingTaskPriority
        while let next = try await nextPending() {
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
            let counts = try counts()
            await signalState(.indexing(counts.indexed, counts.pending, next.url), onlyIfActive: true)

            // Detect stop
            let currentState = await currentState
            if currentState.isStartingOrIndexing {
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
                if case let .pausing(x, y, resumeOnLaunch) = currentState {
                    await signalState(.paused(x, y, resumeOnLaunch))
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
        let counts = try counts()
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

        switch indexResult {
        case .error:
            spotlightInvalidationQueue.insert(entry.url)
            try await handleCrawlCompletion(item: nil, changed: false, url: entry.url, content: nil, newEntries: newEntries)
            return false

        case .noChange:
            try await handleCrawlCompletion(item: entry, changed: false, url: entry.url, content: nil, newEntries: newEntries)
            return false

        case let .indexed(csEntry, createdItem, newPendingItems, content):
            spotlightQueue.append(csEntry)
            try await handleCrawlCompletion(item: createdItem, changed: true, url: entry.url, content: content, newEntries: newPendingItems)
            return true
        }
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

    private func index(page link: String, lastModified: Date?, lastEtag: String?) async throws -> IndexResponse {
        guard let site = URL(string: link) else {
            Log.crawling(id, .error).log("Malformed URL: \(link)")
            return .error
        }

        let counts = try counts()
        await signalState(.indexing(counts.indexed, counts.pending, link), onlyIfActive: true)

        var headRequest = URLRequest(url: site)
        headRequest.httpMethod = "head"

        let headResponse = await HTTP.getData(for: headRequest, lastVisited: lastModified, lastEtag: lastEtag).1

        if headResponse.statusCode >= 300 {
            if headResponse.statusCode == 304 {
                Log.crawling(id, .info).log("No change (code 304) in \(link)")
                return .noChange
            } else {
                Log.crawling(id, .info).log("No content (code \(headResponse.statusCode)) in \(link)")
                return .error
            }
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

        let contentResult = await HTTP.getData(from: site)

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

        guard let body = htmlDoc.body(),
              let condensedText = (try? body.text(trimAndNormaliseWhitespace: true))?.removingHTMLEntities(),
              let sparseText = (try? body.text(trimAndNormaliseWhitespace: false))?.removingHTMLEntities()
        else {
            Log.crawling(id, .error).log("Cannot parse text in \(link)")
            return .error
        }

        let ogImage = header.metaPropertyContent(for: "og:image")
        let imageFileUrl = Task<URL?, Never>.detached { [id] in
            if let ogImage,
               let thumbnailUrl = try? URL.create(from: ogImage, relativeTo: site, checkExtension: false),
               let data = await HTTP.getImageData(from: thumbnailUrl),
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
            if let index = botRejectionCache.firstIndex(of: newUrlString) {
                let rejectionCount = botRejectionCache.count
                if rejectionCount > 400 {
                    botRejectionCache.elements.move(fromOffsets: IndexSet(integer: index), toOffset: rejectionCount)
                    Log.crawling(id, .default).log("\(id) promoted rejected URL: \(newUrlString) - total: \(rejectionCount)")
                }
            } else {
                if link != newUrlString, robots?.agent("Bloo", canProceedTo: newUrlString) ?? true {
                    newUrls.insert(.pending(url: newUrlString, isSitemap: false))
                } else {
                    botRejectionCache.append(newUrlString)
                    let rejectionCount = botRejectionCache.count
                    // log("\(id) added rejected URL: \(newUrlString) - total: \(rejectionCount)")
                    if rejectionCount == 500 {
                        botRejectionCache = OrderedSet(botRejectionCache.suffix(300))
                        Log.crawling(id, .default).log("\(id) Trimmed rejection cache: \(botRejectionCache.count)")
                    }
                }
            }
        }

        let createdDateString = header.metaPropertyContent(for: "og:article:published_time") ?? header.datePublished ?? ""
        let creationDate = Self.isoFormatter.date(from: createdDateString) ?? Self.isoFormatter2.date(from: createdDateString) ?? Self.isoFormatter3.date(from: createdDateString)
        let keywords = header
            .metaNameContent(for: "keywords")?.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? Self.generateKeywords(from: condensedText)

        let lastModified: Date? = if let lastModifiedHeaderDate {
            lastModifiedHeaderDate
        } else if let creationDate {
            creationDate
        } else {
            await Embedding.generateDate(from: condensedText)
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

            if condensedText.localizedCaseInsensitiveContains(keyword) {
                numberOfKeywordsInContent += 1
            }
        }

        let thumbnailUrl = await imageFileUrl.value

        let newContent = IndexEntry.Content(title: title,
                                            description: summaryContent,
                                            sparseContent: sparseText,
                                            condensedContent: condensedText,
                                            keywords: keywords.joined(separator: ", "),
                                            thumbnailUrl: thumbnailUrl?.absoluteString,
                                            lastModified: lastModified)

        let indexed = IndexEntry.visited(url: link, lastModified: lastModified, etag: etagFromHeaders)

        let attributes = CSSearchableItemAttributeSet(contentType: .url)
        attributes.keywords = keywords
        attributes.title = newContent.title
        attributes.contentDescription = newContent.description
        attributes.textContent = newContent.condensedContent
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

    private func counts() throws -> (indexed: Int, pending: Int) {
        try (visited.count(in: db), pending.count(in: db))
    }

    private func removeAll(purge: Bool) async throws {
        if let db {
            try visited.clear(purge: purge, in: db)
            try pending.clear(purge: purge, in: db)
        }
        try await SearchDB.shared.purgeDomain(id: id)
    }

    private func nextPending() async throws -> IndexEntry? {
        guard let db, let res = try pending.next(in: db) else {
            return nil
        }
        let url = res[DB.urlRow]
        let isSitemap = res[DB.isSitemapRow] ?? false
        let etag = res[DB.etagRow]
        let lastModified = res[DB.lastModifiedRow]

        let result: IndexEntry = if etag != nil || lastModified != nil {
            .visited(url: url, lastModified: lastModified, etag: etag)
        } else {
            .pending(url: url, isSitemap: isSitemap)
        }
        return result
    }

    private func handleCrawlCompletion(item: IndexEntry?, changed: Bool, url: String, content: IndexEntry.Content?, newEntries: Set<IndexEntry>?) async throws {
        guard let db else { return }
        try pending.delete(url: url, in: db)

        let indexTask = Task { [id] in
            if let content {
                try await SearchDB.shared.insert(id: id, url: url, content: content)
            }
        }

        if let item {
            try visited.append(item: item, in: db)
            if changed {
                Log.crawling(id, .info).log("Visited URL: \(item.url)")
            }
        }

        if var newEntries, newEntries.isPopulated {
            try visited.subtract(from: &newEntries, in: db)
            if newEntries.isPopulated {
                Log.crawling(id, .default).log("Adding \(newEntries.count) unindexed URLs to pending")
                try appendPending(items: newEntries)
            }
        }

        try await indexTask.value
    }

    private func appendPending(_ item: IndexEntry) throws {
        guard let db else { return }
        try pending.append(item: item, in: db)
        try visited.delete(url: item.url, in: db)
    }

    private func appendPending(items: any Collection<IndexEntry>) throws {
        guard let db, items.isPopulated else {
            return
        }
        try pending.append(items: items, in: db)
    }

    private func handleSitemapEntries(from url: String, newSitemaps: Set<IndexEntry>) throws {
        guard let db else { return }
        try pending.delete(url: url, in: db)

        var newSitemaps = newSitemaps

        if newSitemaps.isPopulated {
            let stubIndexEntry = IndexEntry.pending(url: url, isSitemap: false)
            newSitemaps.remove(stubIndexEntry)
            try visited.subtract(from: &newSitemaps, in: db)
        }

        if newSitemaps.isPopulated {
            Log.crawling(id, .default).log("Adding \(newSitemaps.count) unindexed URLs from sitemap")
            try appendPending(items: newSitemaps)
        }
    }
}
