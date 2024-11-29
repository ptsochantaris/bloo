import CoreSpotlight
import Foundation

final actor Storage {
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

    private func commitData(for item: Snapshot) async {
        let domainPath = domainPath(for: item.id)

        let index = CSSearchableIndex.isIndexingAvailable() ? CSSearchableIndex.default() : nil

        if item.state == .deleting {
            Log.storage(.default).log("Removing domain \(item.id)")

            let fm = FileManager.default
            if fm.fileExists(atPath: domainPath.path) {
                try! fm.removeItem(at: domainPath)
            }

            if let index {
                do {
                    try await index.deleteSearchableItems(withDomainIdentifiers: [item.id])
                    Log.storage(.default).log("Cleared spotlight data for domain \(item.id)")
                } catch {
                    Log.storage(.error).log("Error clearing domain \(item.id): \(error.localizedDescription)")
                }
            }

            Log.storage(.default).log("Removed domain \(item.id)")

        } else {
            if let index {
                if item.removedItems.isPopulated {
                    try? await index.deleteSearchableItems(withIdentifiers: Array(item.removedItems))
                }
                if item.items.isPopulated {
                    try? await index.indexSearchableItems(item.items)
                }
            }

            let path = domainPath.appendingPathComponent("snapshot.json", isDirectory: false)
            try! JSONEncoder().encode(item).write(to: path, options: .atomic)
            Log.storage(.default).log("Saved checkpoint for \(item.id)")
        }
    }

    func start() {
        guard loopTask == nil else {
            return
        }

        let q = AsyncStream.makeStream(of: Snapshot.self, bufferingPolicy: .unbounded)
        queueContinuation = q.continuation

        loopTask = Task {
            for await item in q.stream {
                await commitData(for: item)
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
        Log.storage(.default).log("Storage shut down")
    }

    func queue(_ item: Snapshot) {
        assert(queueContinuation != nil)
        queueContinuation?.yield(item)
    }
}
