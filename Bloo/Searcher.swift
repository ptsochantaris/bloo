import CoreSpotlight
import Foundation
import PopTimer
import SwiftUI

enum Search: Equatable, Codable {
    case none, top(String), full(String)

    var trimmedText: String {
        switch self {
        case .none: ""
        case let .full(text), let .top(text): text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static var _windowIdToSearch: [UUID: Search]?
    private static let searchesPath = documentsPath.appendingPathComponent("searches.json", isDirectory: false)
    static var windowIdToSearch: [UUID: Search] {
        get {
            if let _windowIdToSearch {
                return _windowIdToSearch
            }
            if let data = try? Data(contentsOf: searchesPath),
               let searches = try? JSONDecoder().decode([UUID: Search].self, from: data) {
                _windowIdToSearch = searches
                return searches
            }
            _windowIdToSearch = [:]
            return [:]
        }
        set {
            _windowIdToSearch = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                try? data.write(to: searchesPath)
            }
        }
    }
}

@Observable
final class Searcher {
    private var lastSearchKey = ""
    private var queryTimer: PopTimer!
    private var currentQuery: CSUserQuery?
    private let windowId: UUID

    init(windowId: UUID) {
        self.windowId = windowId
        queryTimer = PopTimer(timeInterval: 0.4) { [weak self] in
            self?.resetQuery()
        }
        Task {
            switch searchState {
            case .none:
                log("searcher init")

            case let .top(string):
                log("searcher init: \(string)")
                searchQuery = string
                resetQuery(collapseIfNeeded: true, onlyIfChanged: false)

            case let .full(string):
                log("searcher init: \(string)")
                searchQuery = string
                resetQuery(expandIfNeeded: true, onlyIfChanged: false)
            }
            for await _ in NotificationCenter.default.notifications(named: .BlooClearSearches, object: nil) {
                searchQuery = ""
            }
        }
    }

    var searchQuery = "" {
        didSet {
            if searchQuery != oldValue {
                queryTimer.push()
            }
        }
    }

    private var searchState: Search {
        get {
            Search.windowIdToSearch[windowId] ?? .none
        }
        set {
            Search.windowIdToSearch[windowId] = newValue
        }
    }

    var resultState: ResultState = .noSearch

    var title: String {
        switch resultState {
        case .noResults, .noSearch, .searching, .updating:
            return "Bloo"
        case .results:
            let text = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                return "Bloo"
            } else {
                return "\"\(text)\""
            }
        }
    }

    func updateResultState(_ newState: ResultState) {
        Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.3)) {
                resultState = newState
            }
        }
    }

    func resetQuery(expandIfNeeded: Bool = false, collapseIfNeeded: Bool = false, onlyIfChanged: Bool = true) {
        queryTimer.abort()

        let trimmedText = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        let newSearch: Search = if trimmedText.isEmpty {
            .none

        } else {
            switch resultState {
            case .noResults, .noSearch, .searching:
                if expandIfNeeded {
                    .full(trimmedText)
                } else {
                    .top(trimmedText)
                }
            case let .results(displayMode, _), let .updating(displayMode, _):
                switch displayMode {
                case .all:
                    if collapseIfNeeded {
                        .top(trimmedText)
                    } else {
                        .full(trimmedText)
                    }
                case .limited, .top:
                    if expandIfNeeded {
                        .full(trimmedText)
                    } else {
                        .top(trimmedText)
                    }
                }
            }
        }

        if onlyIfChanged, searchState == newSearch {
            return
        }
        searchState = newSearch

        if let q = currentQuery {
            log("Stopping current query")
            q.cancel()
            currentQuery = nil
        }

        let smallChunkSize = 10
        let chunkSize: Int
        let searchText: String
        switch newSearch {
        case .none:
            updateResultState(.noSearch)
            return
        case let .top(text):
            chunkSize = smallChunkSize
            searchText = text
        case let .full(text):
            chunkSize = 1000
            searchText = text
        }
        log("Starting new query: '\(searchText)'")
        let searchTerms = searchText.split(separator: " ").map { String($0) }

        switch resultState {
        case .noResults, .noSearch:
            updateResultState(.searching)
        case let .results(mode, array):
            updateResultState(.updating(mode, array))
        case .searching, .updating:
            break
        }

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

            Task { @MainActor [weak self] in
                guard let self else { return }

                let count = results.count
                switch count {
                case 0:
                    updateResultState(.noResults)
                case 1 ..< smallChunkSize:
                    updateResultState(.results(.limited, results))
                default:
                    switch newSearch {
                    case .none, .top:
                        updateResultState(.results(.top, results))
                    case .full:
                        updateResultState(.results(.all, results))
                    }
                }
            }
        }
    }
}
