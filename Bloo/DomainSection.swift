import Foundation

struct DomainSection: Identifiable {
    var id: String { state.title }
    let state: DomainState
    let domains: [Domain]

    init(state: DomainState, domains: [Domain]) {
        self.state = state
        self.domains = domains
    }

    private func allDomains(_ block: @escaping @Sendable (Domain) async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            for domain in domains {
                group.addTask { @MainActor in
                    await block(domain)
                }
            }
        }
    }

    func resumeAll() async {
        await allDomains {
            if await $0.state.shouldResume {
                await $0.start()
            }
        }
    }

    func removeAll() async {
        await allDomains {
            if case let .paused(_, _, _, resumable) = await $0.state, resumable {
                await $0.remove()
            }
        }
    }

    func startAll() async {
        await allDomains {
            await $0.start()
        }
    }

    func pauseAll(resumable: Bool) async {
        await allDomains {
            await $0.pause(resumable: resumable)
        }
    }

    func restartAll() async {
        await allDomains {
            await $0.restart()
        }
    }
}
