import CoreSpotlight
import Foundation
import Lista
import Maintini
import SwiftUI
#if canImport(BackgroundTasks)
    import BackgroundTasks
#endif

@MainActor
@Observable
final class BlooCore {
    enum State {
        case stopped, backgrounded, running
    }

    var runState: State = .stopped
    var clearSearches = false
    var showAddition = false

    private var domains = [Domain]() // not Lista, needs to be observable

    var domainSections: [Domain.Section] {
        var disposableDomainPresent = false
        let allCases = Domain.State.allCases

        var buckets = [Domain.State: Lista<Domain>](minimumCapacity: allCases.count)
        for domain in domains {
            if domain.state == .deleting {
                disposableDomainPresent = true
                continue
            }
            if let list = buckets[domain.state] {
                list.append(domain)
            } else {
                buckets[domain.state] = Lista(value: domain)
            }
        }
        if disposableDomainPresent {
            domains.removeAll { $0.state == .deleting }
        }
        return Domain.State.allCases.compactMap {
            if let list = buckets[$0], list.count > 0 {
                switch $0 {
                case .deleting, .indexing, .paused, .pausing, .starting:
                    Domain.Section(state: $0, domains: Array(list), sort: .typical)
                case .done:
                    Domain.Section(state: $0, domains: Array(list), sort: Settings.shared.sortDoneStyle)
                }
            } else {
                nil
            }
        }
    }

    static let shared = BlooCore()

    private let snapshotter = Storage()
    private var initialisedViaLaunch = false

    func queueSnapshot(item: Storage.Snapshot) async {
        await snapshotter.queue(item)
    }

    func clearDomainSpotlight(for domainId: String) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        Task {
            do {
                try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainId])
            } catch {
                Log.app(.error).log("Error clearing domain \(domainId): \(error.localizedDescription)")
            }
        }
    }

    func data(for id: String) async throws -> Storage.Snapshot {
        try await snapshotter.data(for: id)
    }

    func resetAll() async throws {
        clearSearches.toggle()

        try await withThrowingDiscardingTaskGroup { group in
            for section in domainSections {
                group.addTask {
                    try await section.pauseAll(resumable: false, matchingFilter: "")
                    try await section.restartAll(wipingExistingData: true, matchingFilter: "")
                }
            }
        }
    }

    func removeAll() async throws {
        clearSearches.toggle()

        try await withThrowingDiscardingTaskGroup { group in
            for section in domainSections {
                group.addTask {
                    try await section.pauseAll(resumable: false, matchingFilter: "")
                    try await section.removeAll(matchingFilter: "")
                }
            }
        }

        domains.removeAll()
        if CSSearchableIndex.isIndexingAvailable() {
            Task {
                try? await CSSearchableIndex.default().deleteAllSearchableItems()
            }
        }
    }

    func start(fromInitialiser: Bool = false) async throws {
        guard fromInitialiser || initialisedViaLaunch, runState != .running else {
            return
        }

        let restoring = runState == .backgrounded

        initialisedViaLaunch = true
        runState = .running
        await snapshotter.start()
        if restoring {
            try await SearchDB.shared.resume()
        }

        for domain in domains where domain.state.shouldResume {
            try? await domain.crawler.start()
        }
    }

    var isRunningAndBusy: Bool {
        runState == .running && domainSections.contains(where: \.state.isNotIdle)
    }

    func waitForIndexingToEnd() async {
        while isRunningAndBusy {
            try? await Task.sleep(for: .seconds(1.0))
        }
    }

    func shutdown(backgrounded: Bool) async throws {
        guard runState == .running else {
            return
        }

        Maintini.startMaintaining()
        defer {
            Maintini.endMaintaining()
        }

        if backgrounded {
            #if !os(macOS) && canImport(BackgroundTasks)
                if isRunningAndBusy {
                    do {
                        let request = BGProcessingTaskRequest(identifier: "build.bru.bloo.background")
                        request.requiresNetworkConnectivity = true
                        request.requiresExternalPower = true
                        try BGTaskScheduler.shared.submit(request)
                        Log.app(.default).log("Registered for background wakeup")
                    } catch {
                        Log.app(.fault).log("Error submitting background processing task: \(error.localizedDescription)")
                    }
                }
            #endif
            runState = .backgrounded
        } else {
            runState = .stopped
        }

        try await withThrowingDiscardingTaskGroup { group in
            for section in domainSections where section.state.canStop {
                group.addTask {
                    try await section.pauseAll(resumable: true, matchingFilter: "")
                }
            }
        }

        Log.app(.default).log("All domains are shut down")

        try await withThrowingDiscardingTaskGroup { group in
            group.addTask { [snapshotter] in
                await snapshotter.shutdown()
            }
            group.addTask { [runState] in
                if runState != .backgrounded {
                    await SearchDB.shared.shutdown()
                } else {
                    await SearchDB.shared.pause()
                }
            }
        }

        try? await Task.sleep(for: .milliseconds(100))

        Log.app(.default).log("Shutdown complete")
    }

    func contains(domain: String) -> Bool {
        let domainList = domainSections.flatMap(\.domains)
        return domainList.contains {
            $0.id == domain
                || domain.hasSuffix(".\($0.id)")
        }
    }

    func addDomain(_ domain: String, postAddAction: Domain.PostAddAction) async {
        do {
            let newDomain = try await Domain(startingAt: domain, postAddAction: postAddAction)
            withAnimation {
                domains.append(newDomain)
            }
            Log.app(.default).log("Added domain: \(domain), postAddAction: \(postAddAction)")
        } catch {
            Log.app(.error).log("Error: \(error.localizedDescription)")
        }
    }

    init() {
        Task {
            try! await start(fromInitialiser: true)

            let directoryList = (try? FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            let domainIds = directoryList
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .map { "https://\($0.lastPathComponent)" }

            await withDiscardingTaskGroup { group in
                for domainId in domainIds {
                    group.addTask {
                        await self.addDomain(domainId, postAddAction: .resumeIfNeeded)
                    }
                }
            }

            showAddition = domains.isEmpty
        }
    }

    #if os(iOS)
        func backgroundTask(_ task: BGProcessingTask) {
            task.expirationHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    try await self.shutdown(backgrounded: true)
                }
            }

            Task {
                do {
                    try await start()
                    await waitForIndexingToEnd()
                    if UIApplication.shared.applicationState == .background {
                        try await shutdown(backgrounded: false)
                    }
                } catch {
                    Log.app(.error).log("Error starting background task: \(error.localizedDescription)")
                }
                Log.app(.default).log("Background task complete")
                task.setTaskCompleted(success: true)
            }
        }
    #endif
}
