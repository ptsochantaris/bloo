import Foundation

enum EngineState {
    enum DisplayMode {
        case limited, top, all
    }

    case noSearch, searching(String), updating(String, DisplayMode, [Search.Result], Int), results(DisplayMode, [Search.Result], Int), noResults

    var results: (DisplayMode, [Search.Result], Int)? {
        switch self {
        case .noResults, .noSearch, .searching:
            nil
        case let .results(type, items, count), let .updating(_, type, items, count):
            (type, items, count)
        }
    }
}
