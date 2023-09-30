import CoreSpotlight
import Foundation
import Maintini
import Semalot
import SwiftSoup
import SwiftUI

final actor Domain: ObservableObject, Identifiable {
    let id: String

    enum State: Hashable, CaseIterable, Codable {
        case loading(Int), paused(Int, Int, Bool), indexing(Int, Int, URL), done(Int), deleting

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.title == rhs.title
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(title)
        }

        static var allCases: [Domain.State] {
            [.paused(0, 0, false), .loading(0), .indexing(0, 0, URL(filePath: "")), .done(0)]
        }

        @ViewBuilder
        var symbol: some View {
            switch self {
            case .loading:
                StatusIcon(name: "gear", color: .yellow)
            case .deleting:
                StatusIcon(name: "trash", color: .red)
            case .paused:
                StatusIcon(name: "pause", color: .red)
            case .done:
                StatusIcon(name: "checkmark", color: .green)
            case .indexing:
                StatusIcon(name: "magnifyingglass", color: .yellow)
            }
        }

        var canStart: Bool {
            switch self {
            case .paused:
                true
            case .deleting, .done, .indexing, .loading:
                false
            }
        }

        var canRestart: Bool {
            switch self {
            case .done, .paused:
                true
            case .deleting, .indexing, .loading:
                false
            }
        }

        var canStop: Bool {
            switch self {
            case .deleting, .done, .loading, .paused:
                false
            case .indexing:
                true
            }
        }

        var isActive: Bool {
            switch self {
            case .deleting, .done, .paused:
                false
            case .indexing, .loading:
                true
            }
        }

        var title: String {
            switch self {
            case .done: "Done"
            case .indexing: "Indexing"
            case .loading: "Starting"
            case .paused: "Paused"
            case .deleting: "Deleting"
            }
        }

        var logText: String {
            switch self {
            case let .done(count): "Completed, \(count) indexed items"
            case let .indexing(pending, indexed, url): "Indexing (\(pending)/\(indexed): \(url.absoluteString)"
            case .deleting, .loading, .paused: title
            }
        }
    }

    @MainActor
    @Published var state = State.paused(0, 0, false) {
        didSet {
            if oldValue != state { // only handle base enum changes
                log("Domain \(id) state is now \(state.logText)")
                stateChangedHandler?(id)
            }
        }
    }

    private var pending: PersistedSet
    private var indexed: PersistedSet
    private var spotlightQueue = [CSSearchableItem]()
    private let bootupEntry: IndexEntry

    @MainActor
    private var stateChangedHandler: ((String) -> Void)?
    @MainActor
    func setStateChangedHandler(_ handler: ((String) -> Void)?) {
        stateChangedHandler = handler
    }

    private let domainPath: URL

    init(startingAt: String) async throws {
        let url = try URL.create(from: startingAt, relativeTo: nil, checkExtension: true)

        guard let host = url.host() else {
            throw Blooper.malformedUrl
        }

        id = host
        bootupEntry = IndexEntry(url: url)

        domainPath = documentsPath.appendingPathComponent(id, isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: domainPath.path) {
            try! fm.createDirectory(at: domainPath, withIntermediateDirectories: true)
        }

        let pendingPath = domainPath.appendingPathComponent("pending.json", isDirectory: false)
        pending = try PersistedSet(path: pendingPath)

        let indexingPath = domainPath.appendingPathComponent("indexing.json", isDirectory: false)
        indexed = try PersistedSet(path: indexingPath)

        let path = domainPath.appendingPathComponent("state.json", isDirectory: false)
        if let newState = try? JSONDecoder().decode(State.self, from: Data(contentsOf: path)) {
            await MainActor.run {
                state = newState
            }
        }
    }

    private var goTask: Task<Void, Never>?

    func start() {
        let count = pending.count
        Task { @MainActor in
            state = .loading(count)
        }
        goTask = Task {
            await go()
        }
    }

    func pause() async {
        let newState = State.paused(indexed.count, pending.count, true)
        Task { @MainActor in
            state = newState
        }
        if let g = goTask {
            goTask = nil
            await g.value
        }
    }

    func restart() async {
        if await state.isActive {
            return
        }
        log("Resetting domain \(id)")
        pending.removeAll()
        indexed.removeAll()
        Task { @MainActor in
            state = .loading(0)
            let fm = FileManager.default
            if fm.fileExists(atPath: domainPath.path) {
                try! fm.removeItem(at: domainPath)
            }
            try! fm.createDirectory(at: domainPath, withIntermediateDirectories: true)
            await clearSpotlight()
            await start()
        }
    }

    func remove() async {
        pending.removeAll()
        indexed.removeAll()
        Task { @MainActor in
            state = .deleting
            await clearSpotlight()
        }
    }
    
    private func clearSpotlight() async {
        Model.shared.clearDomainSpotlight(for: id)
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
                            log("Failed to fetch sitemap data from \(next.id)")
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

    private func updateLoadingState() {
        let count = pending.count
        Task { @MainActor in
            state = .loading(count)
        }
    }

    private func go() async {
        await Maintini.startMaintaining()
        defer {
            Task {
                await Maintini.endMaintaining()
            }
        }

        updateLoadingState()
        if indexed.isEmpty {
            await parseSitemap()
            pending.insert(bootupEntry)
        }
        pending.subtract(indexed)
        if pending.isEmpty {
            pending.insert(bootupEntry)
        }
        updateLoadingState()

        while let next = pending.removeFirst() {
            let start = Date()

            if let newItem = await index(page: next) {
                spotlightQueue.append(newItem)

                if spotlightQueue.count > 59 {
                    await snapshot()
                }
            }

            let currentState = await state
            guard currentState.isActive else {
                if case let .paused(x, y, busy) = currentState, busy {
                    await MainActor.run {
                        state = .paused(x, y, false)
                    }
                }
                await snapshot()
                return
            }

            let duration = max(0, 1 + start.timeIntervalSinceNow)
            if duration > 0 {
                let msec = UInt64(duration * 1000)
                try? await Task.sleep(nanoseconds: msec * NSEC_PER_MSEC)
            }
        }

        let newState = State.done(indexed.count)
        await MainActor.run {
            state = newState
        }
        await snapshot()
    }

    private func snapshot() async {
        let item = await Snapshotter.Item(id: id, state: state, items: spotlightQueue, pending: pending, indexed: indexed, domainRoot: domainPath)
        spotlightQueue.removeAll(keepingCapacity: true)
        Model.shared.queueSnapshot(item: item)
    }

    private static let isoFormatter = ISO8601DateFormatter()

    private static let isoFormatter2: DateFormatter = {
        // 2023-03-05T17:34:36Z"
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

    private func updateIndexedState(url: URL) {
        let newState = State.indexing(indexed.count, pending.count, url)
        Task { @MainActor in
            if state.isActive {
                state = newState
            }
        }
    }

    private func index(page entry: IndexEntry) async -> CSSearchableItem? {
        // TODO: robots
        // TODO: Run update scans using last-modified

        let url = entry.url

        updateIndexedState(url: url)

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
            lastModified = Domain.httpHeaderDateFormatter.date(from: lastModifiedHeader)
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
            let creationDate = Domain.isoFormatter.date(from: createdDateString) ?? Domain.isoFormatter2.date(from: createdDateString) ?? Domain.isoFormatter3.date(from: createdDateString)
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
