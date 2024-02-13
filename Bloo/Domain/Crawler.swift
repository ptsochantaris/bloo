import CoreSpotlight
import Foundation
import HTMLString
import Maintini
import NaturalLanguage
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
    private var botRejectionCache = BlockList<String>(length: 400)
    private var thumbnailFailureCache = BlockList<URL>(length: 400)
    private var pending: TableWrapper
    private var visited: TableWrapper
    private var db: Connection?
    private static let requestLock = Semalot(tickets: 1)

    @MainActor
    weak var crawlerDelegate: Domain!

    enum IndexResponse {
        case noChange(viaServerCode: Bool), error, disallowed, indexed(CSSearchableItem, IndexEntry, Set<IndexEntry>, IndexEntry.Content), wasSitemap(newContentUrls: Set<IndexEntry>, newSitemapUrls: Set<IndexEntry>)
    }

    init(id: String, url: String) async throws {
        self.id = id
        bootupEntry = .pending(url: url, isSitemap: false, textRowId: nil)

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

    private func parseSitemap(at url: String) async -> IndexResponse {
        guard let xmlData = await HTTP.getData(from: url)?.0 else {
            Log.crawling(id, .error).log("Failed to fetch sitemap data from \(url)")
            return .wasSitemap(newContentUrls: [], newSitemapUrls: [])
        }
        Log.crawling(id, .default).log("Fetched sitemap from \(url)")
        do {
            let (contentUrls, newSitemapUrls) = try await SitemapParser(data: xmlData).extract()
            Log.crawling(id, .default).log("Considering \(newSitemapUrls.count) further sitemap URLs, \(contentUrls.count) potential content URLs from sitemap")

            var newContentUrls = Set<IndexEntry>()
            if let robots {
                for entry in contentUrls {
                    if robots.agent("Bloo", canProceedTo: entry.url) {
                        newContentUrls.insert(entry)
                    } else {
                        Log.crawling(id, .default).log("Rejected URL: \(entry.url)")
                        botRejectionCache.addRejection(for: entry.url)
                    }
                }
            } else {
                newContentUrls = contentUrls
            }
            return .wasSitemap(newContentUrls: newContentUrls, newSitemapUrls: newSitemapUrls)

        } catch {
            Log.crawling(id, .error).log("XML Parser error in \(url) - \(error.localizedDescription)")
            return .wasSitemap(newContentUrls: [], newSitemapUrls: [])
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

        let robotDefaultsUrl = "https://\(id)/robots.txt"
        Log.crawling(id, .default).log("\(id) - Scanning \(robotDefaultsUrl)")
        var robotText = ""
        if let data = await HTTP.getData(from: robotDefaultsUrl)?.0, let remoteText = String(data: data, encoding: .utf8) {
            robotText.append(remoteText.trimmingCharacters(in: .whitespacesAndNewlines))
            robotText.append("\n")
        }

        let localRobotDataUrl = domainPath(for: id).appendingPathComponent("local-robots.txt", isDirectory: false)
        if let localRobotText = try? String(contentsOf: localRobotDataUrl) {
            robotText.append(localRobotText.trimmingCharacters(in: .whitespacesAndNewlines))
            robotText.append("\n")
        }

        robots = Robots.parse(robotText)

        if try counts().indexed == 0 {
            let url = "https://\(id)/sitemap.xml"
            try appendPending(.pending(url: url, isSitemap: true, textRowId: nil))

            if let providedSitemaps = robots?.sitemaps {
                let sitemapEntries = providedSitemaps
                    .map { IndexEntry.pending(url: $0, isSitemap: true, textRowId: nil) }

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
                    Log.crawling(id, .default).log("Restarting crawler for \(id) because of priority change")
                    startGoTask(priority: setPriority, signalStateChange: false)
                }
                return
            }

            let willThrottle = Settings.shared.maxConcurrentIndexingOperations == 1
            if willThrottle {
                await Self.requestLock.takeTicket()
            }

            let start = Date()
            let longPause = try await crawl(entry: next)
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

                let maxWait = longPause ? Settings.shared.indexingDelay : Settings.shared.indexingScanDelay
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
        await signalState(.done(counts.indexed, Date()))
        await snapshot()
    }

    private func crawl(entry: IndexEntry) async throws -> Bool {
        let indexResult = switch entry {
        case let .pending(url, isSitemap, textRowId):
            if isSitemap {
                await parseSitemap(at: url)
            } else {
                try await index(page: url, lastModified: nil, lastEtag: nil, existingTextRowId: textRowId)
            }
        case let .visited(url, lastModified, etag, textRowId):
            try await index(page: url, lastModified: lastModified, lastEtag: etag, existingTextRowId: textRowId)
        }

        switch indexResult {
        case .disallowed, .error:
            spotlightInvalidationQueue.insert(entry.url)
            if let db {
                try pending.delete(url: entry.url, in: db)
            }
            return false

        case let .wasSitemap(newContentUrls, newSitemapUrls):
            try await handleCrawlCompletion(item: entry, content: nil, newEntries: newContentUrls, newSitemapEntries: newSitemapUrls)
            return false

        case .noChange:
            try await handleCrawlCompletion(item: entry, content: nil, newEntries: nil, newSitemapEntries: nil)
            return false

        case let .indexed(csEntry, createdItem, newPendingItems, content):
            spotlightQueue.append(csEntry)
            try await handleCrawlCompletion(item: createdItem, content: content, newEntries: newPendingItems, newSitemapEntries: nil)
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

    private func index(page link: String, lastModified: Date?, lastEtag: String?, existingTextRowId: Int64?) async throws -> IndexResponse {
        guard let site = URL(string: link) else {
            Log.crawling(id, .error).log("Malformed URL: \(link)")
            return .error
        }

        if let robots, !robots.agent("Bloo", canProceedTo: link) {
            return .disallowed
        }

        let counts = try counts()
        await signalState(.indexing(counts.indexed, counts.pending, link), onlyIfActive: true)

        var headRequest = URLRequest(url: site)
        headRequest.httpMethod = "head"

        let headResponse = await HTTP.getData(for: headRequest, lastVisited: lastModified, lastEtag: lastEtag).1

        if headResponse.statusCode >= 300 {
            if headResponse.statusCode == 304 {
                Log.crawling(id, .info).log("No change (code 304) in \(link)")
                return .noChange(viaServerCode: true)
            } else {
                Log.crawling(id, .info).log("No content (code \(headResponse.statusCode)) in \(link)")
                return .error
            }
        }

        let headers = headResponse.allHeaderFields

        let etagFromHeaders = (headers["etag"] ?? headers["Etag"]) as? String

        if let etagFromHeaders, lastEtag == etagFromHeaders {
            Log.crawling(id, .info).log("No change (same etag) in \(link)")
            return .noChange(viaServerCode: false)
        }

        let lastModifiedHeaderDate: Date?
        if let lastModifiedHeaderString = (headers["Last-Modified"] ?? headers["last-modified"]) as? String, let lm = Formatters.httpHeaderDateFormatter.date(from: lastModifiedHeaderString) {
            if let lastModified, lastModified >= lm {
                Log.crawling(id, .info).log("No change (same date) in \(link)")
                return .noChange(viaServerCode: false)
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
              let condensedTextRaw = try? body.text(trimAndNormaliseWhitespace: true),
              let sparseTextRaw = try? body.text(trimAndNormaliseWhitespace: false)
        else {
            Log.crawling(id, .error).log("Cannot parse text in \(link)")
            return .error
        }

        let condensedText = condensedTextRaw.removingHTMLEntities()
        let sparseText = sparseTextRaw.removingHTMLEntities()

        var imageFileTask: Task<(URL?, URL), Never>?
        if let ogImage = header.metaPropertyContent(for: "og:image"),
           let thumbnailUrl = try? URL.create(from: ogImage, relativeTo: site, checkExtension: false),
           !thumbnailFailureCache.checkForRejection(of: thumbnailUrl) {
            imageFileTask = Task { [id] in
                let localFile = try! Self.imageDataPath(for: id, sourceUrl: thumbnailUrl)
                let now = Date.now

                let fm = FileManager.default
                if let attributes = try? fm.attributesOfItem(atPath: localFile.path),
                   let lastModified = attributes[.modificationDate] as? Date,
                   now.timeIntervalSince(lastModified) < 3600 * 24 * 7 {
                    return (localFile, thumbnailUrl)
                }

                Log.crawling(id, .info).log("Will fetch thumbnail to \(localFile.path)")
                guard let data = await HTTP.getImageData(from: thumbnailUrl),
                      let image = data.asImage?.limited(to: CGSize(width: 512, height: 512)),
                      let dataToSave = image.jpegData else {
                    Log.crawling(id, .info).log("Could not fetch thumbnail to \(localFile.path)")
                    return (nil, thumbnailUrl)
                }

                try? dataToSave.write(to: localFile)
                try? fm.setAttributes([.modificationDate: now], ofItemAtPath: localFile.path)
                Log.crawling(id, .info).log("Did fetch thumbnail to \(localFile.path)")
                return (localFile, thumbnailUrl)
            }
        }

        let summaryContent = header.metaPropertyContent(for: "og:description") ?? ""

        let newUrls = try? htmlDoc.select("a[href]")
            .compactMap { try? $0.attr("href").trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { try? URL.create(from: $0, relativeTo: site, checkExtension: true) }
            .filter { $0.host()?.hasSuffix(id) == true }
            .map(\.absoluteString)
            .uniqued()
            .filter { !botRejectionCache.checkForRejection(of: $0) }
            .filter { link != $0 }
            .compactMap { (item: String) -> IndexEntry? in
                if link == item {
                    return nil
                }
                guard let robots else {
                    return .pending(url: item, isSitemap: false, textRowId: nil)
                }
                if robots.agent("Bloo", canProceedTo: item) {
                    return .pending(url: item, isSitemap: false, textRowId: nil)
                } else {
                    Log.crawling(id, .default).log("Rejected URL: \(item)")
                    botRejectionCache.addRejection(for: item)
                    return nil
                }
            }

        let createdDateString = header.metaPropertyContent(for: "og:article:published_time") ?? header.datePublished ?? ""
        let creationDate = Formatters.isoFormatter.date(from: createdDateString) ?? Formatters.isoFormatter2.date(from: createdDateString) ?? Formatters.isoFormatter3.date(from: createdDateString)
        let keywords = Self.generateKeywords(from: condensedText)

//        let keywords = header
//            .metaNameContent(for: "keywords")?.split(separator: ",")
//            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
//            ?? Self.generateKeywords(from: condensedText)

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

        var thumbnailUrl: URL?
        if let thumbnailUrlInfo = await imageFileTask?.value {
            if thumbnailUrlInfo.0 == nil {
                thumbnailFailureCache.addRejection(for: thumbnailUrlInfo.1)
            } else {
                thumbnailUrl = thumbnailUrlInfo.0
            }
        }

        let newContent = IndexEntry.Content(title: title,
                                            description: summaryContent,
                                            sparseContent: sparseText,
                                            condensedContent: condensedText,
                                            keywords: keywords.joined(separator: ", "),
                                            thumbnailUrl: thumbnailUrl?.absoluteString,
                                            lastModified: lastModified)

        let newEntry = IndexEntry.visited(url: link, lastModified: lastModified, etag: etagFromHeaders, textRowId: existingTextRowId)

        let attributes = CSSearchableItemAttributeSet(contentType: .url)
        attributes.keywords = keywords
        attributes.title = newContent.title
        attributes.contentDescription = newContent.description
        attributes.textContent = newContent.condensedContent
        attributes.contentModificationDate = newContent.lastModified
        attributes.thumbnailURL = thumbnailUrl
        return .indexed(CSSearchableItem(uniqueIdentifier: link, domainIdentifier: id, attributeSet: attributes), newEntry, Set(newUrls ?? []), newContent)
    }

    private static func imageDataPath(for id: String, sourceUrl: URL) throws -> URL {
        let uuid = sourceUrl.absoluteString.hashString
        let first = String(uuid[uuid.startIndex ... uuid.index(uuid.startIndex, offsetBy: 2)])
        let second = String(uuid[uuid.index(uuid.startIndex, offsetBy: 3) ... uuid.index(uuid.startIndex, offsetBy: 5)])
        let third = String(uuid.dropFirst(6))

        let domainPath = domainPath(for: id)
        let location = domainPath.appendingPathComponent("thumbnails", isDirectory: true)
            .appendingPathComponent(first, isDirectory: true)
            .appendingPathComponent(second, isDirectory: true)

        let fm = FileManager.default
        if !fm.fileExists(atPath: location.path(percentEncoded: false)) {
            try fm.createDirectory(at: location, withIntermediateDirectories: true)
        }

        return location.appendingPathComponent(third + ".jpg", isDirectory: false)
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
        let etag = res[DB.etagRow]
        let isSitemap = res[DB.isSitemapRow] ?? false
        let lastModified = res[DB.lastModifiedRow]
        let textRowId = res[DB.textRowId]

        let result: IndexEntry = if etag != nil || lastModified != nil {
            .visited(url: url, lastModified: lastModified, etag: etag, textRowId: textRowId)
        } else {
            .pending(url: url, isSitemap: isSitemap, textRowId: textRowId)
        }
        return result
    }

    private func handleCrawlCompletion(item: IndexEntry, content: IndexEntry.Content?, newEntries: Set<IndexEntry>?, newSitemapEntries: Set<IndexEntry>?) async throws {
        guard let db else { return }

        let itemUrl = item.url

        try pending.delete(url: itemUrl, in: db)

        if let content {
            let textTableRowId = try await SearchDB.shared.insert(id: id, url: itemUrl, content: content, existingRowId: item.textRowId)
            let updatedItem = item.withTextRowId(textTableRowId)
            try visited.append(item: updatedItem, in: db)

            Log.crawling(id, .info).log("Visited URL: \(itemUrl)")

        } else {
            try visited.append(item: item, in: db)
        }

        if var newSitemapEntries, newSitemapEntries.isPopulated {
            let stubIndexEntry = IndexEntry.pending(url: itemUrl, isSitemap: false, textRowId: nil)
            newSitemapEntries.remove(stubIndexEntry)
            try visited.subtract(from: &newSitemapEntries, in: db)

            if newSitemapEntries.isPopulated {
                Log.crawling(id, .default).log("Adding \(newSitemapEntries.count) unindexed URLs from sitemap")
                try appendPending(items: newSitemapEntries)
            }
        }

        guard var newEntries, newEntries.isPopulated else {
            return
        }

        try visited.subtract(from: &newEntries, in: db)

        guard newEntries.isPopulated else {
            return
        }

        Log.crawling(id, .default).log("Adding \(newEntries.count) unindexed URLs to pending")
        try appendPending(items: newEntries)
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
}
