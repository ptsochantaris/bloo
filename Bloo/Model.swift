import CoreSpotlight
import Foundation
import PopTimer
import SwiftUI
#if os(iOS)
    import BackgroundTasks
#endif

@MainActor
@Observable
final class Model {
    enum RunState {
        case stopped, backgrounded, running
    }

    var runState: RunState = .stopped
    var searchState: SearchState = .noSearch
    var domainSections = [DomainSection]()

    var searchQuery = "" {
        didSet {
            if searchQuery != oldValue {
                queryTimer?.push()
            }
        }
    }

    static let shared = Model()

    private var snapshotter = Snapshotter()
    private var currentQuery: CSUserQuery?
    private var lastSearchKey = ""
    private var initialisedViaLaunch = false
    private var queryTimer: PopTimer?

    func queueSnapshot(item: Snapshot) {
        snapshotter.queue(item)
    }

    func clearDomainSpotlight(for domainId: String) {
        Task {
            do {
                try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainId])
            } catch {
                log("Error clearing domain \(domainId): \(error.localizedDescription)")
            }
        }
    }

    func updateSearchRunning(_ newState: SearchState) {
        withAnimation(.easeInOut(duration: 0.3)) {
            searchState = newState
        }
    }

    func data(for id: String) async throws -> Snapshot {
        try await snapshotter.data(for: id)
    }

    func resetQuery(full: Bool) {
        queryTimer?.abort()

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

        switch searchState {
        case .noResults, .noSearch:
            updateSearchRunning(.searching)
        case let .results(resultType, array):
            updateSearchRunning(.updating(resultType, array))
        case .searching, .updating:
            break
        }

        let largeChunkSize = 100
        let smallChunkSize = 10
        let chunkSize = full ? largeChunkSize : smallChunkSize

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
                let id = result.item.uniqueIdentifier

                // dedup
                guard check.insert(id).inserted else {
                    continue
                }

                let attributes = result.item.attributeSet
                guard let title = attributes.title, let contentDescription = attributes.contentDescription, let url = URL(string: id) else {
                    continue
                }

                let res = SearchResult(id: url.absoluteString,
                                       title: title,
                                       url: url,
                                       descriptionText: contentDescription,
                                       displayDate: attributes.contentModificationDate,
                                       thumbnailUrl: attributes.thumbnailURL,
                                       keywords: attributes.keywords ?? [],
                                       terms: searchTerms)
                chunk.append(res)
            }

            Task { [chunk] in
                if chunk.count < smallChunkSize {
                    if chunk.isEmpty {
                        updateSearchRunning(.noResults)
                    } else {
                        updateSearchRunning(.results(.limited, chunk))
                    }
                } else {
                    updateSearchRunning(.results(full ? .all : .top, chunk))
                }
            }
        }
    }

    func resetAll() async {
        searchQuery = ""

        await withTaskGroup(of: Void.self) { group in
            for section in domainSections {
                group.addTask {
                    await section.pauseAll(resumable: false)
                    await section.restartAll()
                }
            }
        }
    }

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
                    await section.resumeAll()
                }
            }
        }
    }

    var isRunningAndBusy: Bool {
        runState == .running && domainSections.contains(where: \.state.isActive)
    }

    func waitForIndexingToEnd() async {
        while isRunningAndBusy {
            try? await Task.sleep(for: .seconds(0.5))
        }
    }

    func shutdown(backgrounded: Bool) async {
        guard runState == .running else {
            return
        }

        if backgrounded {
            #if os(iOS)
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
            #endif
            runState = .backgrounded
        } else {
            searchQuery = ""
            runState = .stopped
        }

        await withTaskGroup(of: Void.self) { group in
            for section in domainSections where section.state.canStop {
                group.addTask {
                    await section.pauseAll(resumable: true)
                }
            }
        }
        log("All domains are shut down")
        await snapshotter.shutdown()
        log("Snapshots and model are now shut down")
        try? await Task.sleep(for: .milliseconds(300))
    }

    func contains(domain: String) -> Bool {
        let domainList = domainSections.flatMap(\.domains)
        return domainList.contains {
            $0.id == domain
                || domain.hasSuffix(".\($0.id)")
        }
    }

    func addDomain(_ domain: String, startAfterAdding: Bool) async {
        log("Adding domain: \(domain), willStart: \(startAfterAdding)")
        do {
            let newDomain = try await Domain(startingAt: domain) { [weak self] in
                self?.sortDomains()
            }
            sortDomains(adding: newDomain)
            log("Added domain: \(domain), willStart: \(startAfterAdding)")
            if startAfterAdding {
                await newDomain.start()
            }
        } catch {
            log("Error: \(error.localizedDescription)")
        }
    }

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
        log("Sorted sections: \(newSections.map(\.state.title).joined(separator: ", "))")
        withAnimation(.easeInOut(duration: 0.3)) {
            domainSections = newSections
        }
    }

    init() {
        guard CSSearchableIndex.isIndexingAvailable() else {
            // TODO:
            log("Spotlight not available")
            return
        }

        let directoryList = (try? FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let entryPoints = directoryList
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { "https://\($0.lastPathComponent)" }

        queryTimer = PopTimer(timeInterval: 0.4) { [weak self] in
            self?.resetQuery(full: false)
        }

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
                Task { [weak self] in
                    guard let self else { return }
                    await shutdown(backgrounded: true)
                }
            }
            Task { [weak self] in
                guard let self else { return }
                await start()
                await waitForIndexingToEnd()
                if UIApplication.shared.applicationState == .background {
                    await shutdown(backgrounded: false)
                }
                log("Background task complete")
                task.setTaskCompleted(success: true)
            }
        }
    #endif
}
