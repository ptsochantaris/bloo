import Foundation
import PopTimer
import SwiftUI
import CoreSpotlight

extension Search {
    @Observable
    @MainActor
    final class Engine {
        private var lastSearchKey = ""
        private var queryTimer: PopTimer!
        private let windowId: UUID

        init(windowId: UUID) {
            self.windowId = windowId
            queryTimer = PopTimer(timeInterval: 0.4) { [weak self] in
                self?.resetQuery()
            }

            Task {
                switch searchState {
                case .none:
                    Log.search(.default).log("Initialised - windowId: \(windowId.uuidString)")

                case let .top(string):
                    Log.search(.default).log("Initialised: \(string) - top results - windowId: \(windowId.uuidString)")
                    searchQuery = string
                    resetQuery(collapseIfNeeded: true, onlyIfChanged: false)

                case let .full(string):
                    Log.search(.default).log("Initialised: \(string) - full results - windowId: \(windowId.uuidString)")
                    searchQuery = string
                    resetQuery(expandIfNeeded: true, onlyIfChanged: false)
                }
            }
        }

        deinit {
            Log.search(.default).log("De-initialised - windowId: \(windowId.uuidString)")
        }

        var searchQuery = "" {
            didSet {
                if searchQuery != oldValue {
                    Log.search(.default).log("Search query changed: \(searchQuery)")
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

        var state = EngineState.noSearch

        var title: String {
            switch state {
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

        func updateResultState(_ newState: EngineState) {
            withAnimation(.easeInOut(duration: 0.3)) { [self] in
                state = newState
            }
        }

        private var runningQueryTask: Task<Void, Never>?
        func resetQuery(expandIfNeeded: Bool = false, collapseIfNeeded: Bool = false, onlyIfChanged: Bool = true) {
            queryTimer.abort()

            let trimmedText = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

            let newSearch: Search = if trimmedText.isEmpty {
                .none

            } else {
                switch state {
                case .noResults, .noSearch, .searching:
                    if expandIfNeeded {
                        .full(trimmedText)
                    } else {
                        .top(trimmedText)
                    }
                case let .results(displayMode, _, _), let .updating(_, displayMode, _, _):
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

            let previousTask = runningQueryTask
            runningQueryTask?.cancel()
            runningQueryTask = nil

            searchState = newSearch

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
            Log.search(.default).log("Starting new query: '\(searchText)'")

            switch state {
            case .noResults, .noSearch:
                updateResultState(.searching(searchText))
            case let .results(mode, array, count):
                updateResultState(.updating(searchText, mode, array, count))
            case let .searching(text):
                updateResultState(.searching(text))
            case let .updating(_, mode, array, count):
                updateResultState(.updating(searchText, mode, array, count))
            }

            let context = CSUserQueryContext()
            context.maxResultCount = chunkSize
            context.fetchAttributes = ["title", "contentURL", "contentCreationDate", "contentModificationDate", "thumbnailURL", "keywords", "contentDescription", "contentType"]
            let query = CSUserQuery(userQueryString: searchText, userQueryContext: context)
            let newQueryTask = Task {
                _ = await previousTask?.value

                if Task.isCancelled {
                    Log.search(.info).log("Cancelled search, skipping")
                    return
                }

                var results: [Search.Result] = []
                do {
                    let terms = searchText.split(separator: " ").map { String($0) }
                    for try await result in query.results {
                        let blooResult = Search.Result(searchableItem: result.item, terms: terms)
                        results.append(blooResult)
                        Log.search(.info).log("Received result - \(result.id)")
                    }
                } catch {
                    Log.search(.error).log("Error querying index: \(error)")
                }
                
                let count = query.foundItemCount
                Log.search(.info).log("Total \(count) results")
                
                switch count {
                case 0:
                    updateResultState(.noResults)
                case 1 ..< smallChunkSize:
                    updateResultState(.results(.limited, results, count))
                default:
                    switch newSearch {
                    case .none, .top:
                        updateResultState(.results(.top, results, count))
                    case .full:
                        updateResultState(.results(.all, results, count))
                    }
                }

                if !Task.isCancelled {
                    runningQueryTask = nil
                }
            }

            runningQueryTask = newQueryTask
        }
    }
}
