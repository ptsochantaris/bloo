import Foundation

enum ResultState {
    enum DisplayMode {
        case limited, top, all
    }

    case noSearch, searching, updating(DisplayMode, [SearchResult]), results(DisplayMode, [SearchResult]), noResults

    var results: (DisplayMode, [SearchResult])? {
        switch self {
        case .noResults, .noSearch, .searching:
            nil
        case let .results(type, items), let .updating(type, items):
            (type, items)
        }
    }
}
