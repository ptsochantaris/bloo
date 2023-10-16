import CoreSpotlight
import Foundation
import Lista
import SwiftUI
#if os(iOS)
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

    private var domains = [Domain]()

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
            domains.removeAll { $0.shouldDispose }
        }
        return Domain.State.allCases.compactMap {
            if let list = buckets[$0], list.count > 0 {
                Domain.Section(state: $0, domains: Array(list))
            } else {
                nil
            }
        }
    }

    static let shared = BlooCore()

    private let snapshotter = Storage()
    private var initialisedViaLaunch = false

    func queueSnapshot(item: Storage.Snapshot) {
        snapshotter.queue(item)
    }

    func clearDomainSpotlight(for domainId: String) {
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

        try await withThrowingTaskGroup(of: Void.self) { group in
            for section in domainSections {
                group.addTask {
                    try await section.pauseAll(resumable: false, matchingFilter: "")
                    try await section.restartAll(wipingExistingData: true, matchingFilter: "")
                }
            }
            try await group.waitForAll()
        }
    }

    func removeAll() async throws {
        clearSearches.toggle()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for section in domainSections {
                group.addTask {
                    try await section.pauseAll(resumable: false, matchingFilter: "")
                    try await section.removeAll(matchingFilter: "")
                }
            }
            try await group.waitForAll()
        }

        domains.removeAll()
        Task {
            try? await CSSearchableIndex.default().deleteAllSearchableItems()
        }
    }

    func start(fromInitialiser: Bool = false) async {
        guard fromInitialiser || initialisedViaLaunch, runState != .running else {
            return
        }

        initialisedViaLaunch = true
        runState = .running
        snapshotter.start()
    }

    var isRunningAndBusy: Bool {
        runState == .running && domainSections.contains(where: \.state.isActive)
    }

    func waitForIndexingToEnd() async {
        while isRunningAndBusy {
            try? await Task.sleep(for: .seconds(0.5))
        }
    }

    func shutdown(backgrounded: Bool) async throws {
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

        try await withThrowingTaskGroup(of: Void.self) { group in
            for section in domainSections where section.state.canStop {
                group.addTask {
                    try await section.pauseAll(resumable: true, matchingFilter: "")
                }
            }
            try await group.waitForAll()
        }
        Log.app(.default).log("All domains are shut down")
        await snapshotter.shutdown()
        Log.app(.default).log("Storage now shut down")
        try? await Task.sleep(for: .milliseconds(200))
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
        guard CSSearchableIndex.isIndexingAvailable() else {
            // TODO:
            Log.app(.error).log("Spotlight not available")
            return
        }

        Task {
            await start(fromInitialiser: true)

            let directoryList = (try? FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            let domainIds = directoryList
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .map { "https://\($0.lastPathComponent)" }

            await withTaskGroup(of: Void.self) { group in
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
            task.expirationHandler = {
                Task { [weak self] in
                    guard let self else { return }
                    try await shutdown(backgrounded: true)
                }
            }
            Task { [weak self] in
                guard let self else { return }
                await start()
                await waitForIndexingToEnd()
                if UIApplication.shared.applicationState == .background {
                    try await shutdown(backgrounded: false)
                }
                Log.app(.default).log("Background task complete")
                task.setTaskCompleted(success: true)
            }
        }
    #endif
}
