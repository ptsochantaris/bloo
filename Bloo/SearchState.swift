import Foundation

enum SearchState {
    enum ResultType {
        case limited, top, all
    }

    case noSearch, searching, updating(ResultType, [SearchResult]), results(ResultType, [SearchResult]), noResults

    var results: (ResultType, [SearchResult])? {
        switch self {
        case .noResults, .noSearch, .searching:
            return nil
        case let .updating(type, items), let .results(type, items):
            return (type, items)
        }
    }
}
