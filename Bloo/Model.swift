import CoreSpotlight
import Foundation
import PopTimer
import SwiftUI
#if os(iOS)
    import BackgroundTasks
#endif

final class Model: ObservableObject {
    enum RunState {
        case stopped, backgrounded, running
    }

    @Published var hasDomains: Bool
    @Published var runState: RunState = .stopped
    @Published var searchState: SearchState = .noSearch
    @Published var domainSections = [DomainSection]() {
        didSet {
            hasDomains = domainSections.isPopulated
        }
    }

    static let shared = Model()

    private let snapshotter = Snapshotter()
    private var currentQuery: CSUserQuery?
    private var lastSearchKey = ""

    private lazy var queryTimer = PopTimer(timeInterval: 0.3) { [weak self] in
        self?.resetQuery(full: false)
    }

    @Published var searchQuery = "" {
        didSet {
            queryTimer.push()
        }
    }

    func queueSnapshot(item: Snapshotter.Item) {
        snapshotter.queue(item)
    }

    func clearDomainSpotlight(for domainId: String) {
        Task {
            do {
                try await snapshotter.clearDomainSpotlight(for: domainId)
            } catch {
                log("Error clearing domain \(domainId): \(error.localizedDescription)")
            }
        }
    }

    func updateSearchRunning(_ newState: SearchState) {
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.3)) {
                searchState = newState
            }
        }
    }

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

                let res = SearchResult(title: title,
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

    @MainActor
    func resetAll() async {
        searchQuery = ""

        await withTaskGroup(of: Void.self) { group in
            for section in domainSections where section.state.canStop {
                group.addTask {
                    await section.restartAll()
                }
            }
        }
    }

    private var initialisedViaLaunch = false
    @MainActor
    func start(fromInitialiser: Bool = false) async {
        guard fromInitialiser || initialisedViaLaunch, runState != .running else {
            return
        }

        initialisedViaLaunch = true
        runState = .running
        snapshotter.start()

        await withTaskGroup(of: Void.self) { group in
            for section in domainSections where section.state.canStart {
                group.addTask {
                    await section.startAll()
                }
            }
        }
    }

    var isRunningAndBusy: Bool {
        runState == .running && domainSections.contains(where: { $0.state.isActive })
    }

    @MainActor
    func waitForIndexingToEnd() async {
        while isRunningAndBusy {
            try? await Task.sleep(for: .seconds(0.5))
        }
    }

    @MainActor
    func shutdown(backgrounded: Bool) async {
        guard runState == .running else {
            return
        }

        if backgrounded {
            if isRunningAndBusy {
                do {
                    let request = BGProcessingTaskRequest(identifier: "build.bru.bloo.background")
                    request.requiresNetworkConnectivity = true
                    request.requiresExternalPower = true
                    try BGTaskScheduler.shared.submit(request)
                    log("Registered for background wakeup")
                } catch {
                    log("Error submitting background processing task: \(error.localizedDescription)")
                }
            }
            runState = .backgrounded
        } else {
            searchQuery = ""
            runState = .stopped
        }

        await withTaskGroup(of: Void.self) { group in
            for section in domainSections where section.state.canStop {
                group.addTask {
                    await section.pauseAll()
                }
            }
        }
        log("All domains are shut down")
        await snapshotter.shutdown()
        log("Snapshots and model are now shut down")
        try? await Task.sleep(for: .milliseconds(100))
    }

    func contains(domain: String) -> Bool {
        let domainList = domainSections.flatMap(\.domains)
        return domainList.contains {
            $0.id == domain
                || domain.hasSuffix(".\($0.id)")
        }
    }

    @MainActor
    func addDomain(_ domain: String, startAfterAdding: Bool) async {
        log("Adding domain: \(domain), willStart: \(startAfterAdding)")
        do {
            let newDomain = try await Task.detached { try await Domain(startingAt: domain) }.value
            sortDomains(adding: newDomain)
            newDomain.setStateChangedHandler { [weak self] _ in
                self?.sortDomains()
            }
            log("Added domain: \(domain), willStart: \(startAfterAdding)")
            if startAfterAdding {
                await newDomain.start()
            }
        } catch {
            log("Error: \(error.localizedDescription)")
        }
    }

    @MainActor
    func sortDomains(adding newDomain: Domain? = nil) {
        var domainList = domainSections.flatMap(\.domains)
        if let newDomain {
            domainList.append(newDomain)
        }
        let newSections = DomainState.allCases.compactMap { state -> DomainSection? in
            let domainsForState = domainList.filter { $0.state == state }.sorted { $0.id < $1.id }
            if domainsForState.isEmpty { return nil }
            return DomainSection(state: state, domains: domainsForState)
        }
        log("Sorted sections: \(newSections.map { $0.state.title }.joined(separator: ", "))")
        withAnimation(.easeInOut(duration: 0.3)) {
            domainSections = newSections
        }
    }

    init() {
        guard CSSearchableIndex.isIndexingAvailable() else {
            // TODO
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
                        await self.addDomain(domain, startAfterAdding: false) // the start call will start these
                    }
                }
            }
            await start(fromInitialiser: true)
        }
    }

    #if os(iOS)
        func backgroundTask(_ task: BGProcessingTask) {
            task.expirationHandler = {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await shutdown(backgrounded: true)
                }
            }
            Task { [weak self] in
                guard let self else { return }
                await start()
                await waitForIndexingToEnd()
                if await UIApplication.shared.applicationState == .background {
                    await shutdown(backgrounded: false)
                }
                log("Background task complete")
                task.setTaskCompleted(success: true)
            }
        }
    #endif
}
