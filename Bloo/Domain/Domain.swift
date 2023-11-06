import Foundation
import SwiftUI

@MainActor
@Observable
final class Domain: Identifiable, Sendable {
    let id: String
    let crawler: Crawler

    var state = State.defaultState {
        didSet {
            if oldValue != state { // only report base enum changes
                Log.crawling(id, .default).log("Domain \(id) state is now \(state.logText)")
            }
        }
    }

    init(startingAt: String, postAddAction: PostAddAction) async throws {
        let url = try URL.create(from: startingAt, relativeTo: nil, checkExtension: true)

        guard let id = url.host() else {
            throw Blooper.malformedUrl
        }

        self.id = id
        crawler = try await Crawler(id: id, url: url.absoluteString)
        crawler.crawlerDelegate = self
        try await crawler.loadFromSnapshot(postAddAction: postAddAction)
    }

    nonisolated func matchesFilter(_ text: String) -> Bool {
        text.isEmpty || id.localizedCaseInsensitiveContains(text)
    }
}
