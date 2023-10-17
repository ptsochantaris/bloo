import Foundation
import Lista
import PopTimer
import SwiftUI

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

        var resultState: Engine.State = .noSearch

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

        func updateResultState(_ newState: Engine.State) {
            withAnimation(.easeInOut(duration: 0.3)) { [self] in
                resultState = newState
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

            switch resultState {
            case .noResults, .noSearch:
                updateResultState(.searching)
            case let .results(mode, array):
                updateResultState(.updating(mode, array))
            case .searching, .updating:
                break
            }

            Task.detached { [weak self] in
                guard let self else { return }

                let results = (try? SearchDB.textQuery(searchText, limit: chunkSize)) ?? []

                switch results.count {
                case 0:
                    await updateResultState(.noResults)
                case 1 ..< smallChunkSize:
                    await updateResultState(.results(.limited, results))
                default:
                    switch newSearch {
                    case .none, .top:
                        await updateResultState(.results(.top, results))
                    case .full:
                        await updateResultState(.results(.all, results))
                    }
                }
            }
        }
    }
}
