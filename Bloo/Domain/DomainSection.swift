import Foundation

extension Domain {
    struct Section: Identifiable {
        let id: String
        let state: State
        let domains: [Domain]

        init(state: State, domains: [Domain]) {
            id = state.title
            self.state = state
            self.domains = domains.sorted { $0.id < $1.id }
        }

        private func allDomains(matchingFilter: String, _ block: @escaping @Sendable (Domain) async throws -> Void) async throws {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for domain in domains.filter({ $0.matchesFilter(matchingFilter) }) {
                    group.addTask { @MainActor in
                        try await block(domain)
                    }
                }
                try await group.waitForAll()
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
