import CoreSpotlight
import Foundation

final class Storage {
    private var queueContinuation: AsyncStream<Snapshot>.Continuation?
    private var loopTask: Task<Void, Never>?

    func data(for id: String) async throws -> Snapshot {
        try await Task.detached {
            let domainPath = domainPath(for: id)
            let fm = FileManager.default
            if !fm.fileExists(atPath: domainPath.path) {
                try fm.createDirectory(at: domainPath, withIntermediateDirectories: true)
            }

            let decoder = JSONDecoder()
            let path = domainPath.appendingPathComponent("snapshot.json", isDirectory: false)
            if let data = try? Data(contentsOf: path),
               let snapshot = try? decoder.decode(Snapshot.self, from: data) {
                return snapshot
            }
            return Snapshot(id: id, state: Domain.State.defaultState)
        }.value
    }

    private static func commitData(for item: Snapshot) async {
        let domainPath = domainPath(for: item.id)

        if item.state == .deleting {
            Log.storage(.default).log("Removing domain \(item.id)")
            let fm = FileManager.default
            if fm.fileExists(atPath: domainPath.path) {
                try! fm.removeItem(at: domainPath)
            }
            Log.storage(.default).log("Removed domain \(item.id)")
            return
        }

        let path = domainPath.appendingPathComponent("snapshot.json", isDirectory: false)
        try! JSONEncoder().encode(item).write(to: path, options: .atomic)

        Log.storage(.default).log("Saved checkpoint for \(item.id)")
    }

    func start() {
        guard loopTask == nil else {
            return
        }

        let q = AsyncStream<Snapshot>.makeStream()
        queueContinuation = q.continuation

        loopTask = Task.detached {
            await withDiscardingTaskGroup { group in
                for await item in q.stream {
                    group.addTask {
                        let index = CSSearchableIndex.default()
                        try? await index.deleteSearchableItems(withIdentifiers: Array(item.removedItems))
                        try? await index.indexSearchableItems(item.items)
                        await Self.commitData(for: item)
                    }
                }
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

    func queue(_ item: Snapshot) {
        assert(queueContinuation != nil)
        queueContinuation?.yield(item)
    }
}
