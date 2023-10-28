import Foundation

extension Search.Engine {
    enum State {
        enum DisplayMode {
            case limited, top, all
        }

        case noSearch, searching(String), updating(String, DisplayMode, [Search.Result]), results(DisplayMode, [Search.Result]), noResults

        var results: (DisplayMode, [Search.Result])? {
            switch self {
            case .noResults, .noSearch, .searching:
                nil
            case let .results(type, items), let .updating(_, type, items):
                (type, items)
            }
        }
    }
}
