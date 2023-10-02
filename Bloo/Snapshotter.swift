import CoreSpotlight
import Foundation
import Semalot

final class Snapshotter {
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
            return Snapshot(id: id, state: .paused(0, 0, false, false), items: [], pending: IndexSet(), indexed: IndexSet())
        }.value
    }

    private func commitData(for item: Snapshot) async {
        let domainPath = domainPath(for: item.id)

        if item.state == .deleting {
            let fm = FileManager.default
            if fm.fileExists(atPath: domainPath.path) {
                try! fm.removeItem(at: domainPath)
            }
            log("Removed domain \(item.id)")
            return
        }

        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await CSSearchableIndex.default().indexSearchableItems(item.items)
            }
            group.addTask {
                let path = domainPath.appendingPathComponent("snapshot.json", isDirectory: false)
                try! JSONEncoder().encode(item).write(to: path, options: .atomic)
            }
        }
        log("Saved checkpoint for \(item.id), - \(item.pending.count) pending items, \(item.indexed.count) indexed items")
    }

    func start() {
        guard loopTask == nil else {
            return
        }

        let q = AsyncStream<Snapshot>.makeStream()
        queueContinuation = q.continuation

        loopTask = Task {
            let max: UInt = 4
            let loopLimit = Semalot(tickets: max)
            for await item in q.stream {
                await loopLimit.takeTicket()
                Task.detached { [weak self] in
                    guard let self else { return }
                    await commitData(for: item)
                    loopLimit.returnTicket()
                }
            }
            // ensure queue is drained before continuing
            // TODO: put this in Semalot as a method
            for _ in 0 ..< max {
                await loopLimit.takeTicket()
            }
            for _ in 0 ..< max {
                loopLimit.returnTicket()
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
