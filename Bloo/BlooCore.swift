import CoreSpotlight
import Foundation
import SwiftUI
#if os(iOS)
    import BackgroundTasks
#endif

extension Notification.Name {
    static let BlooClearSearches = Self("BlooClearSearches")
    static let BlooCreateSearch = Self("BlooCreateSearch")
}

@MainActor
@Observable
final class BlooCore {
    enum RunState {
        case stopped, backgrounded, running
    }

    var runState: RunState = .stopped
    var domainSections = [DomainSection]()

    static let shared = BlooCore()

    private var snapshotter = Snapshotter()
    private var initialisedViaLaunch = false

    private func clearSearches() {
        NotificationCenter.default.post(name: .BlooClearSearches, object: nil)
    }

    func newWindowWithSearch(_ text: String) {
        NotificationCenter.default.post(name: .BlooCreateSearch, object: text)
    }

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

    func data(for id: String) async throws -> Snapshot {
        try await snapshotter.data(for: id)
    }

    func resetAll() async {
        clearSearches()

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
