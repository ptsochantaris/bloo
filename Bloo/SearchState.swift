import Foundation

enum SearchState {
    case noSearch, searching, topResults([SearchResult]), moreResults([SearchResult]), noResults

    var resultMode: Bool {
        switch self {
        case .noSearch, .searching:
            false
        case .moreResults, .noResults, .topResults:
            true
        }
    }
}
