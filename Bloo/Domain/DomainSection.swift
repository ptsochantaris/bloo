import Foundation

extension Domain {
    @MainActor
    struct Section: Identifiable {
        let id: String
        let state: State
        let domains: [Domain]

        init(state: State, domains: [Domain], sort: SortStyle) {
            id = state.title
            self.state = state
            self.domains = switch sort {
            case .newestFirst:
                domains.sorted { $1.state.lastRefreshDate < $0.state.lastRefreshDate }
            case .oldestFirst:
                domains.sorted { $0.state.lastRefreshDate < $1.state.lastRefreshDate }
            case .typical:
                domains.sorted { $0.id < $1.id }
            }
        }

        private func allDomains(matchingFilter: String, _ block: @escaping @Sendable (Domain) async throws -> Void) async throws {
            try await withThrowingDiscardingTaskGroup { group in
                for domain in domains.filter({ $0.matchesFilter(matchingFilter) }) {
                    group.addTask {
                        try await block(domain)
                    }
                }
            }
            Log.crawling(id, .info).log("Action for all domains complete")
        }

        func resumeAll(matchingFilter: String) async throws {
            try await allDomains(matchingFilter: matchingFilter) {
                if await $0.state.shouldResume {
                    try await $0.crawler.start()
                }
            }
        }

        func removeAll(matchingFilter: String) async throws {
            try await allDomains(matchingFilter: matchingFilter) {
                if await $0.state.canRemove {
                    try await $0.crawler.remove()
                }
            }
        }

        func startAll(matchingFilter: String) async throws {
            try await allDomains(matchingFilter: matchingFilter) {
                try await $0.crawler.start()
            }
        }

        func pauseAll(resumable: Bool, matchingFilter: String) async throws {
            try await allDomains(matchingFilter: matchingFilter) {
                try await $0.crawler.pause(resumable: resumable)
            }
        }

        func restartAll(wipingExistingData: Bool, matchingFilter: String) async throws {
            try await allDomains(matchingFilter: matchingFilter) {
                try await $0.crawler.restart(wipingExistingData: wipingExistingData)
            }
        }
    }
}
