import Foundation
import SwiftUI

struct SearchResults: View {
    let results: EngineState
    let filter: String

    var body: some View {
        switch results {
        case .noResults, .noSearch, .searching:
            ProgressView()
                .padding()

        case let .results(mode, items, _), let .updating(_, mode, items, _):
            switch mode {
            case .all:
                LazyVGrid(columns: Constants.gridColumns) {
                    let filtered = filter.isEmpty ? items : items.filter { $0.matchesFilter(filter) }
                    ForEach(filtered) {
                        ResultRow(result: $0)
                    }
                }
            case .limited, .top:
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(items) {
                            ResultRow(result: $0)
                                .frame(width: 320)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }
}
