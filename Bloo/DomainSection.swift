import Foundation

struct DomainSection: Identifiable {
    var id: String { state.title }
    let state: DomainState
    let domains: [Domain]

    init(state: DomainState, domains: [Domain]) {
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
