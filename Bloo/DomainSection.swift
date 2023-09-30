import Foundation

protocol ModelItem: Hashable, Identifiable {}

extension ModelItem {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct DomainSection: ModelItem {
    let id: String
    let state: DomainState
    let domains: [Domain]

    init(state: DomainState, domains: [Domain]) {
        id = state.id + domains.map(\.id).joined()
        self.state = state
        self.domains = domains
    }

    private func allDomains(_ block: @escaping (Domain) async -> Void) {
        Task {
            await withTaskGroup(of: Void.self) { group in
                for domain in domains {
                    group.addTask { @MainActor in
                        await block(domain)
                    }
                }
            }
        }
    }

    func startAll() {
        allDomains {
            await $0.start()
        }
    }

    func pauseAll() {
        allDomains {
            await $0.pause()
        }
    }

    func restartAll() {
        allDomains {
            await $0.restart()
        }
    }
}
