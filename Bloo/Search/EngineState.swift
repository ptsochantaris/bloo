import Foundation

extension Search.Engine {
    enum State {
        enum DisplayMode {
            case limited, top, all
        }

        case noSearch, searching(String), updating(String, DisplayMode, [Search.Result], Bool), results(DisplayMode, [Search.Result], Bool), noResults

        var results: (DisplayMode, [Search.Result], Bool)? {
            switch self {
            case .noResults, .noSearch, .searching:
                nil
            case let .results(type, items, fuzzy), let .updating(_, type, items, fuzzy):
                (type, items, fuzzy)
            }
        }
    }
}
