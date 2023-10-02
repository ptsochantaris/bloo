import Foundation

enum SearchState {
    enum ResultType {
        case limited, top, all
    }

    case noSearch, searching, updating(ResultType, [SearchResult]), results(ResultType, [SearchResult]), noResults

    var results: (ResultType, [SearchResult])? {
        switch self {
        case .noResults, .noSearch, .searching:
            nil
        case let .results(type, items), let .updating(type, items):
            (type, items)
        }
    }
}
