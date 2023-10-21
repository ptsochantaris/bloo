import Foundation

extension Search.Engine {
    enum State {
        enum DisplayMode {
            case limited, top, all
        }

        case noSearch, searching, updating(DisplayMode, [Search.Result], Bool), results(DisplayMode, [Search.Result], Bool), noResults

        var results: (DisplayMode, [Search.Result], Bool)? {
            switch self {
            case .noResults, .noSearch, .searching:
                nil
            case let .results(type, items, fuzzy), let .updating(type, items, fuzzy):
                (type, items, fuzzy)
            }
        }
    }
}
