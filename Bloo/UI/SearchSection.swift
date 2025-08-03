import Foundation
import SwiftUI

struct SearchSection: View {
    private let searcher: Search.Engine
    private let title: String
    private let ctaTitle: String?
    private let showProgress: Bool
    private let prefersLargeView: Bool
    private let showResults: Bool
    private let showFilter: Bool

    @State private var filter = ""

    init(searcher: Search.Engine) {
        self.searcher = searcher

        switch searcher.state {
        case .noSearch:
            title = "Search"
            showProgress = false
            ctaTitle = nil
            prefersLargeView = false
            showResults = false
            showFilter = false

        case let .searching(text):
            title = "Searching for '\(text)'"
            showProgress = true
            ctaTitle = nil
            prefersLargeView = false
            showResults = false
            showFilter = false

        case let .updating(text, resultType, _, _):
            title = "Searching for '\(text)'"
            showProgress = true
            ctaTitle = nil

            switch resultType {
            case .all:
                prefersLargeView = false
            case .limited:
                prefersLargeView = false
            case .top:
                prefersLargeView = true
            }
            showResults = true
            showFilter = false

        case let .results(resultType, _, count):
            switch resultType {
            case .all:
                title = count > 1 ? " \(count) Results" : "1 Result"
                showProgress = false
                ctaTitle = "Top Results"
                prefersLargeView = false
                showResults = true
                showFilter = true
            case .limited:
                title = count > 1 ? " \(count) Results" : "1 Result"
                showProgress = false
                ctaTitle = nil
                prefersLargeView = false
                showResults = true
                showFilter = false
            case .top:
                title = "Top Results"
                showProgress = false
                ctaTitle = "Show More"
                prefersLargeView = true
                showResults = true
                showFilter = false
            }

        case .noResults:
            title = "No results found"
            showProgress = false
            ctaTitle = nil
            prefersLargeView = false
            showResults = false
            showFilter = false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: Constants.hspacing) {
                Text(title)
                    .font(.blooTitle)
                    .foregroundStyle(.secondary)

                Spacer()

                if showProgress {
                    ProgressView()
                        .frame(width: 20, height: 20)
                        .scaleEffect(CGSize(width: 0.8, height: 0.8))

                } else {
                    if showFilter {
                        FilterField(filter: $filter)
                    }

                    if let ctaTitle {
                        Button {
                            searcher.resetQuery(expandIfNeeded: prefersLargeView, collapseIfNeeded: !prefersLargeView)
                        } label: {
                            Text(ctaTitle)
                        }
                    }
                }
            }

            if showResults {
                SearchResults(results: searcher.state, filter: filter)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.fill.tertiary)
        .cornerRadius(Constants.wideCorner)
    }
}
