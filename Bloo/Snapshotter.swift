import CoreSpotlight
import Foundation

final class Snapshotter {
    struct Item {
        let domainName: String
        let state: DomainState
        let items: [CSSearchableItem]
        let pending: PersistedSet
        let indexed: PersistedSet
        let domainRoot: URL
    }

    private var queueContinuation: AsyncStream<Item>.Continuation?
    private var loopTask: Task<Void, Never>?

    func data(in domainPath: URL) async throws -> (PersistedSet, PersistedSet, DomainState) {
        try await Task.detached {
            let fm = FileManager.default
            if !fm.fileExists(atPath: domainPath.path) {
                try! fm.createDirectory(at: domainPath, withIntermediateDirectories: true)
            }

            let pendingPath = domainPath.appendingPathComponent("pending.json", isDirectory: false)
            let pending = try PersistedSet(path: pendingPath)

            let indexingPath = domainPath.appendingPathComponent("indexing.json", isDirectory: false)
            let indexed = try PersistedSet(path: indexingPath)

            let path = domainPath.appendingPathComponent("state.json", isDirectory: false)
            let newState = try? JSONDecoder().decode(DomainState.self, from: Data(contentsOf: path))
            let state = newState ?? DomainState.paused(0, 0, false, false)

            return (pending, indexed, state)
        }.value
    }

    func start() {
        guard loopTask == nil else {
            return
        }

        let q = AsyncStream<Item>.makeStream()
        queueContinuation = q.continuation

        loopTask = Task.detached {
            for await item in q.stream {
                if item.state == .deleting {
                    log("Removing domain \(item.domainName)")
                    let fm = FileManager.default
                    if fm.fileExists(atPath: item.domainRoot.path) {
                        try! fm.removeItem(at: item.domainRoot)
                    }
                    return
                }

                await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        await item.indexed.write()
                    }
                    group.addTask {
                        await item.pending.write()
                    }
                    group.addTask {
                        try await CSSearchableIndex.default().indexSearchableItems(item.items)

                        let resolved: DomainState = switch item.state {
                        case .done, .paused:
                            item.state
                        case .deleting, .indexing, .loading:
                            .paused(0, 0, false, true)
                        }

                        let path = documentsPath.appendingPathComponent(item.domainName, isDirectory: true).appendingPathComponent("state.json", isDirectory: false)
                        try! JSONEncoder().encode(resolved).write(to: path, options: .atomic)
                    }
                }

                log("Saved checkpoint for \(item.domainName)")
            }
        }
    }

    func shutdown() async {
        if let l = loopTask {
            queueContinuation?.finish()
            queueContinuation = nil
            loopTask = nil
            await l.value
        }
    }

    func clearDomainSpotlight(for domainId: String) async throws {
        try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainId])
    }

    func queue(_ item: Item) {
        assert(queueContinuation != nil)
        queueContinuation?.yield(item)
    }
}
