import CoreSpotlight
import Foundation
import Lista
import Maintini

final actor Snapshotter {
    struct Item {
        let id: String
        let state: Domain.State
        let items: [CSSearchableItem]
        let pending: PersistedSet
        let indexed: PersistedSet
        let domainRoot: URL
    }

    private let queue = Lista<Item>()
    private var loopTask: Task<Void, Never>?
    let indexer = CSSearchableIndex.default()

    init() {
        Task {
            await Maintini.startMaintaining()
        }
    }

    func shutdown() async {
        await loopTask?.value
        await Maintini.endMaintaining()
    }

    func queue(_ item: Item) async {
        queue.append(item)
        if loopTask == nil {
            loopTask = Task {
                try? await loop()
                loopTask = nil
            }
        }
    }

    private func loop() async throws {
        while let item = queue.pop() {
            if item.state == .deleting {
                log("Removing domain \(item.id)")
                let fm = FileManager.default
                if fm.fileExists(atPath: item.domainRoot.path) {
                    try! fm.removeItem(at: item.domainRoot)
                }
                return
            }

            await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { [indexer] in
                    try await indexer.indexSearchableItems(item.items)
                }
                group.addTask {
                    await item.indexed.write()
                }
                group.addTask {
                    await item.pending.write()
                }
                group.addTask {
                    let resolved: Domain.State
                    switch item.state {
                    case .done, .paused:
                        resolved = item.state
                    case .deleting, .indexing, .loading:
                        resolved = .paused(0, 0, false)
                    }

                    let path = documentsPath.appendingPathComponent(item.id, isDirectory: true).appendingPathComponent("state.json", isDirectory: false)
                    try! JSONEncoder().encode(resolved).write(to: path, options: .atomic)
                    log("!! Written \(path)")
                }
            }
        }
    }
}
