import CoreSpotlight
import Foundation
import PopTimer
import SwiftUI

@Observable
final class Searcher {
    private var lastSearchKey = ""
    private var queryTimer: PopTimer!
    private var currentQuery: CSUserQuery?
    private let windowId: UUID

    init(windowId: UUID) {
        self.windowId = windowId
        queryTimer = PopTimer(timeInterval: 0.4) { [weak self] in
            self?.resetQuery(full: false)
        }
        Task {
            for await _ in NotificationCenter.default.notifications(named: .BlooClearSearches, object: nil) {
                searchQuery = ""
            }
        }
        log("searcher init")
    }

    var searchState: SearchState = .noSearch
    var searchQuery = "" {
        didSet {
            if searchQuery != oldValue {
                queryTimer.push()
            }
        }
    }

    private func updateSearchRunning(_ newState: SearchState) {
        withAnimation(.easeInOut(duration: 0.3)) {
            searchState = newState
        }
    }

    func resetQuery(full: Bool) {
        queryTimer.abort()

        let searchText = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let newKey = "\(searchText)-\(full)"
        if newKey == lastSearchKey {
            return
        }
        lastSearchKey = newKey
        // TODO: - persist and restore the local search

        if let q = currentQuery {
            log("Stopping current query")
            q.cancel()
            currentQuery = nil
        }

        if searchText.isEmpty {
            updateSearchRunning(.noSearch)
            return
        }

        log("Starting new query: '\(searchText)'")
        let searchTerms = searchText.split(separator: " ").map { String($0) }

        switch searchState {
        case .noResults, .noSearch:
            updateSearchRunning(.searching)
        case let .results(resultType, array):
            updateSearchRunning(.updating(resultType, array))
        case .searching, .updating:
            break
        }

        let largeChunkSize = 1000
        let smallChunkSize = 10
        let chunkSize = full ? largeChunkSize : smallChunkSize

        let context = CSUserQueryContext()
        context.fetchAttributes = ["title", "contentDescription", "keywords", "thumbnailURL", "contentModificationDate", "rankingHint"]
        // context.enableRankedResults = true
        context.maxResultCount = chunkSize
        let q = CSUserQuery(userQueryString: searchText, userQueryContext: context)
        currentQuery = q
        q.start()

        Task.detached { [weak self] in
            var check = Set<String>()
            check.reserveCapacity(chunkSize)

            var chunk = ContiguousArray<CSSearchableItem>()
            chunk.reserveCapacity(chunkSize)

            for try await result in q.results {
                let id = result.item.uniqueIdentifier

                // dedup
                guard check.insert(id).inserted else {
                    continue
                }

                chunk.append(result.item)
            }

            let results = chunk.compactMap {
                SearchResult($0, searchTerms: searchTerms)
            }

            Task { @MainActor [weak self, chunk] in
                guard let self else { return }
                if results.count < smallChunkSize {
                    if chunk.isEmpty {
                        updateSearchRunning(.noResults)
                    } else {
                        updateSearchRunning(.results(.limited, results))
                    }
                } else {
                    updateSearchRunning(.results(full ? .all : .top, results))
                }
            }
        }
    }
}
