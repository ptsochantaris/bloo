import Foundation

enum SearchState {
    enum ResultType {
        case limited, top, all
    }

    case noSearch, searching, results(ResultType, [SearchResult]), noResults

    var resultMode: Bool {
        switch self {
        case .noSearch, .searching:
            false
        case .noResults, .results:
            true
        }
    }
}
