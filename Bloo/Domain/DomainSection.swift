import Foundation

extension Domain {
    struct Section: Identifiable {
        let id: String
        let state: State
        let domains: [Domain]

        init(state: State, domains: [Domain]) {
            id = state.title
            self.state = state
            self.domains = domains
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
                    try await $0.start()
                }
            }
        }

        func removeAll(matchingFilter: String) async throws {
            try await allDomains(matchingFilter: matchingFilter) {
                if case .paused(_, _, _, _) = await $0.state {
                    try await $0.remove()
                }
            }
        }

        func startAll(matchingFilter: String) async throws {
            try await allDomains(matchingFilter: matchingFilter) {
                try await $0.start()
            }
        }

        func pauseAll(resumable: Bool, matchingFilter: String) async throws {
            try await allDomains(matchingFilter: matchingFilter) {
                try await $0.pause(resumable: resumable)
            }
        }

        func restartAll(wipingExistingData: Bool, matchingFilter: String) async throws {
            try await allDomains(matchingFilter: matchingFilter) {
                try await $0.restart(wipingExistingData: wipingExistingData)
            }
        }
    }
}
