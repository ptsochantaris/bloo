import Foundation

struct DomainSection: Identifiable {
    var id: String { state.title }
    let state: DomainState
    let domains: [Domain]

    init(state: DomainState, domains: [Domain]) {
        self.state = state
        self.domains = domains
    }

    private func allDomains(_ block: @escaping (Domain) async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            for domain in domains {
                group.addTask { @MainActor in
                    await block(domain)
                }
            }
        }
    }

    func startAll() async {
        await allDomains {
            await $0.start()
        }
    }

    func pauseAll() async {
        await allDomains {
            await $0.pause()
        }
    }

    func restartAll() async {
        await allDomains {
            await $0.restart()
        }
    }
}
