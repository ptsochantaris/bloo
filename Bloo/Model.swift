import CoreSpotlight
import Foundation
import PopTimer
import SwiftUI

struct IndexEntry: Equatable, Hashable, Identifiable, Codable {
    let id: String
    let url: URL
    let lastModified: Date?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    init(url: URL, lastModified: Date? = nil) {
        id = url.absoluteString
        self.url = url
        self.lastModified = lastModified
    }
}

struct SearchResult: Identifiable, Hashable {
    let id: String
    let title: String
    let url: URL
    let descriptionText: String
    let updatedAt: Date?
    let thumbnailUrl: URL?
    let terms: [String]
    let keywords: [String]

    init(id: String, title: String, url: URL, descriptionText: String, updatedAt: Date?, thumbnailUrl: URL?, keywords: [String], terms: [String]) {
        self.id = id
        self.title = title
        self.url = url
        self.descriptionText = descriptionText
        self.updatedAt = updatedAt
        self.thumbnailUrl = thumbnailUrl
        self.terms = terms
        self.keywords = keywords
    }

    var attributedTitle: AttributedString {
        title.highlightedAttributedStirng(terms)
    }

    var attributedDescription: AttributedString {
        descriptionText.highlightedAttributedStirng(terms)
    }

    var matchedKeywords: String? {
        var res = [String]()
        for term in terms {
            if let found = keywords.first(where: { $0.localizedCaseInsensitiveCompare(term) == .orderedSame }) {
                res.append("#\(found)")
            }
        }
        return res.isEmpty ? nil : res.joined(separator: ", ")
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

final class Model: ObservableObject {
    enum SearchState {
        case noSearch, searching, topResults([SearchResult]), moreResults([SearchResult]), noResults

        var resultMode: Bool {
            switch self {
            case .noSearch, .searching:
                false
            case .moreResults, .noResults, .topResults:
                true
            }
        }
    }

    @Published var isRunning = true
    @Published var searchState: SearchState = .noSearch
    @Published var domainSections = [DomainSection]() {
        didSet {
            hasDomains = domainSections.isPopulated
        }
    }

    var hasDomains: Bool

    private lazy var queryTimer = PopTimer(timeInterval: 0.3) { [weak self] in
        self?.resetQuery(full: false)
    }

    private var currentQuery: CSUserQuery?

    final class DomainSection: Identifiable, ObservableObject {
        var id: String {
            state.title + domains.map(\.id).joined(separator: "-") + "-" + String(actionable)
        }

        let state: Domain.State
        let domains: [Domain]

        @Published var actionable = true

        init(state: Domain.State, domains: [Domain]) {
            self.state = state
            self.domains = domains
        }

        private func allDomains(_ block: @escaping (Domain) async -> Void) {
            actionable = false
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for domain in domains {
                        group.addTask { @MainActor in
                            await block(domain)
                        }
                    }
                }
                actionable = true
            }
        }

        func startAll() {
            allDomains {
                await $0.start()
            }
        }

        func pauseAll() {
            allDomains {
                await $0.pause()
            }
        }

        func restartAll() {
            allDomains {
                await $0.restart()
            }
        }
    }

    func updateSearchRunning(_ newState: SearchState) {
        Task { @MainActor in
            searchState = newState
        }
    }

    private var lastSearchKey = ""
    func resetQuery(full: Bool) {
        queryTimer.abort()

        let newSearch = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let newKey = "\(newSearch)-\(full)"
        if newKey == lastSearchKey {
            return
        }
        lastSearchKey = newKey

        if let q = currentQuery {
            log("Stopping current query")
            q.cancel()
            currentQuery = nil
        }

        let searchText = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if searchText.isEmpty {
            updateSearchRunning(.noSearch)
            return
        }

        log("Starting new query: '\(searchText)'")
        let searchTerms = searchText.split(separator: " ").map { String($0) }

        updateSearchRunning(.searching)

        let chunkSize = full ? 100 : 10

        let context = CSUserQueryContext()
        context.fetchAttributes = ["title", "contentDescription", "keywords", "thumbnailURL", "contentModificationDate"]
        context.enableRankedResults = true
        context.maxResultCount = chunkSize
        let q = CSUserQuery(userQueryString: searchText, userQueryContext: context)
        currentQuery = q
        q.start()

        Task {
            var check = Set<String>()
            check.reserveCapacity(chunkSize)

            var chunk = [SearchResult]()
            chunk.reserveCapacity(chunkSize)

            for try await result in q.results {
                // dedup
                let id = result.id
                guard check.insert(id).inserted else {
                    continue
                }

                let attributes = result.item.attributeSet
                guard let title = attributes.title, let contentDescription = attributes.contentDescription, let url = URL(string: id) else {
                    continue
                }

                let res = SearchResult(id: id,
                                       title: title,
                                       url: url,
                                       descriptionText: contentDescription,
                                       updatedAt: attributes.contentModificationDate,
                                       thumbnailUrl: attributes.thumbnailURL,
                                       keywords: attributes.keywords ?? [],
                                       terms: searchTerms)
                chunk.append(res)
            }

            Task { @MainActor [chunk] in
                if chunk.isEmpty {
                    updateSearchRunning(.noResults)
                } else if full {
                    updateSearchRunning(.moreResults(chunk))
                } else {
                    updateSearchRunning(.topResults(chunk))
                }
            }
        }
    }

    @Published var searchQuery = "" {
        didSet {
            queryTimer.push()
        }
    }

    let snapshotter = Snapshotter()

    static let shared = Model()

    @MainActor
    func resetAll() async {
        searchQuery = ""

        await withTaskGroup(of: Void.self) { group in
            for section in domainSections where !section.state.isActive {
                group.addTask {
                    section.restartAll()
                }
            }
        }
    }

    func resurrect() {
        isRunning = true
    }

    @MainActor
    func shutdown() async {
        guard isRunning else {
            return
        }

        searchQuery = ""

        await withTaskGroup(of: Void.self) { group in
            Task { @MainActor in
                isRunning = false
            }
            for section in domainSections {
                for domain in section.domains {
                    group.addTask { @MainActor in
                        if domain.state.isActive {
                            await domain.pause()
                        }
                    }
                }
            }
        }
        await Task.yield()
        log("All domains are shut down")
        await snapshotter.shutdown()
        log("Snapshots are now shut down")
        await Task.yield()
        try? await Task.sleep(for: .seconds(0.3))
    }

    func contains(domain: String) -> Bool {
        let domainList = domainSections.flatMap(\.domains)
        return domainList.contains {
            $0.id == domain
                || domain.hasSuffix(".\($0.id)")
        }
    }

    @MainActor
    func addDomain(_ domain: String) async {
        do {
            let newDomain = try await Task.detached { try await Domain(startingAt: domain) }.value
            sortDomains(adding: newDomain)
            newDomain.setStateChangedHandler { [weak self] _ in
                self?.sortDomains()
            }
        } catch {
            log("Error: \(error.localizedDescription)")
        }
    }

    @MainActor
    func sortDomains(adding newDomain: Domain? = nil) {
        log("Sorting domains")
        var domainList = domainSections.flatMap(\.domains)
        if let newDomain {
            domainList.append(newDomain)
        }
        domainSections = Domain.State.allCases.map { state in
            let domainsForState = domainList.filter { $0.state == state }.sorted { $0.id < $1.id }
            return DomainSection(state: state, domains: domainsForState)
        }
    }

    init() {
        guard CSSearchableIndex.isIndexingAvailable() else {
            log("Spotlight not available")
            hasDomains = false
            return
        }

        let directoryList = (try? FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let entryPoints = directoryList
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { "https://\($0.lastPathComponent)" }

        hasDomains = entryPoints.isPopulated

        Task {
            await withTaskGroup(of: Void.self) { group in
                for domain in entryPoints {
                    group.addTask {
                        await self.addDomain(domain)
                    }
                }
            }
        }
    }
}
