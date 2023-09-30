//
//  DomainSection.swift
//  Bloo
//
//  Created by Paul Tsochantaris on 30/09/2023.
//

import Foundation

final class DomainSection: Identifiable, ObservableObject {
    var id: String {
        state.title + domains.map(\.id).joined(separator: "-") + "-" + String(actionable)
    }

    let state: Domain.State
    let domains: [Domain]

    @Published var actionable = true

    init(state: Domain.State, domains: [Domain]) {
        self.state = state
        self.domains = domains
    }

    private func allDomains(_ block: @escaping (Domain) async -> Void) {
        actionable = false
        Task {
            await withTaskGroup(of: Void.self) { group in
                for domain in domains {
                    group.addTask { @MainActor in
                        await block(domain)
                    }
                }
            }
            actionable = true
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
