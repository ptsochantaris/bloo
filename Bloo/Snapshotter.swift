import CoreSpotlight
import Foundation

struct Snapshot: Codable {
    let id: String
    let state: DomainState
    let items: [CSSearchableItem]
    let pending: IndexSet
    let indexed: IndexSet

    init(id: String, state: DomainState, items: [CSSearchableItem], pending: IndexSet, indexed: IndexSet) {
        self.id = id
        self.items = items
        self.pending = pending
        self.indexed = indexed

        switch state {
        case .done, .paused, .deleting:
            self.state = state
        case .indexing, .loading:
            self.state = .paused(0, 0, false, true)
        }
    }

    enum CodingKeys: CodingKey {
        case id, state, pending, indexed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(state, forKey: .state)
        try container.encode(pending, forKey: .pending)
        try container.encode(indexed, forKey: .indexed)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        state = try container.decode(DomainState.self, forKey: .indexed)
        pending = try container.decode(IndexSet.self, forKey: .pending)
        indexed = try container.decode(IndexSet.self, forKey: .indexed)
        items = []
    }
}

final class Snapshotter {
    private var queueContinuation: AsyncStream<Snapshot>.Continuation?
    private var loopTask: Task<Void, Never>?

    func data(for id: String) async throws -> Snapshot {
        try await Task.detached {
            let domainPath = Snapshotter.domainPath(for: id)
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

    static func domainPath(for id: String) -> URL {
        documentsPath.appendingPathComponent(id, isDirectory: true)
    }

    func storeImageData(_ data: Data, for id: String) -> URL {
        let uuid = UUID().uuidString
        let first = String(uuid[uuid.startIndex ... uuid.index(uuid.startIndex, offsetBy: 1)])
        let second = String(uuid[uuid.index(uuid.startIndex, offsetBy: 2) ... uuid.index(uuid.startIndex, offsetBy: 3)])

        let domainPath = Snapshotter.domainPath(for: id)
        let location = domainPath.appendingPathComponent("thumbnails", isDirectory: true)
            .appendingPathComponent(first, isDirectory: true)
            .appendingPathComponent(second, isDirectory: true)

        let fm = FileManager.default
        if !fm.fileExists(atPath: location.path(percentEncoded: false)) {
            try! fm.createDirectory(at: location, withIntermediateDirectories: true)
        }
        let fileUrl = location.appendingPathComponent(uuid + ".jpg", isDirectory: false)
        try! data.write(to: fileUrl)
        return fileUrl
    }

    private func commitData(for item: Snapshot) async {
        let domainPath = Snapshotter.domainPath(for: item.id)

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
                let path = domainPath.appendingPathComponent("snapshot.json", isDirectory: false)
                try! JSONEncoder().encode(item).write(to: path, options: .atomic)
            }
            group.addTask {
                try await CSSearchableIndex.default().indexSearchableItems(item.items)
            }
        }
        log("Saved checkpoint for \(item.id)")
    }

    func start() {
        guard loopTask == nil else {
            return
        }

        let q = AsyncStream<Snapshot>.makeStream()
        queueContinuation = q.continuation

        loopTask = Task.detached { [weak self] in
            guard let self else { return }
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
    }

    func clearDomainSpotlight(for domainId: String) async throws {
        try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainId])
    }

    func queue(_ item: Snapshot) {
        assert(queueContinuation != nil)
        queueContinuation?.yield(item)
    }
}
