import Foundation

extension Domain {
    struct Section: Identifiable {
        var id: String { state.title }
        let state: State
        let domains: [Domain]

        init(state: State, domains: [Domain]) {
            self.state = state
            self.domains = domains
        }

        private func allDomains(_ block: @escaping @Sendable (Domain) async -> Void) async {
            // Heaviest-first to take advantage of completing faster on multiple cores
            await withTaskGroup(of: Void.self) { group in
                var tuples = [(domain: Domain, weight: Int)]()
                for domain in domains {
                    let weight = await domain.weight
                    tuples.append((domain, weight))
                }
                for item in tuples.sorted(by: { $0.weight > $1.weight }) {
                    group.addTask { @MainActor in
                        await block(item.domain)
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

        func restartAll(wipingExistingData: Bool) async {
            await allDomains {
                await $0.restart(wipingExistingData: wipingExistingData)
            }
        }
    }
}
