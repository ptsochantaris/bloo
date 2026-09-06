import Foundation

extension Domain {
    struct Section: Identifiable {
        /// Combined indexed and pending counts for every domain in a section
        struct Totals {
            let indexed: Int
            let pending: Int

            var progress: Double {
                Double(indexed) / max(1, Double(pending + indexed))
            }
        }

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

        var totals: Totals {
            var indexed = 0
            var pending = 0
            for domain in domains {
                let counts = domain.state.counts
                indexed += counts.indexed
                pending += counts.pending
            }
            return Totals(indexed: indexed, pending: pending)
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
