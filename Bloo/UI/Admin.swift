import Foundation
import SwiftUI

struct Admin: View {
    private let model: BlooCore
    @Bindable private var searcher: Search.Engine

    @State private var showLog = false
    @State private var searchFocused = false
    @State private var logHeight: CGFloat = 300
    @FocusState private var additionFocused: Bool

    init(model: BlooCore, windowId: UUID) {
        self.model = model
        searcher = Search.Engine(windowId: windowId)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 18) {
                    if model.showAddition {
                        AdditionSection(model: model)
                            .focused($additionFocused)
                    }

                    if case .noSearch = searcher.state {
                        EmptyView()
                    } else {
                        SearchSection(searcher: searcher)
                    }

                    ForEach(model.domainSections) {
                        DomainGrid(section: $0)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.clearSearches) { _, _ in
                searcher.searchQuery = ""
            }

            if showLog {
                LogView(store: logStorage, showLog: $showLog, logHeight: $logHeight)
                    .frame(height: logHeight)
            }
        }
        .navigationTitle(searcher.title)
        .toolbar {
            Button {
                withAnimation {
                    showLog.toggle()
                }
            } label: {
                Image(systemName: showLog ? "clipboard.fill" : "pencil.and.list.clipboard")
            }

            Button {
                withAnimation {
                    if model.showAddition {
                        additionFocused = false
                        #if os(macOS)
                            searchFocused = true
                        #endif
                    }
                    model.showAddition.toggle()
                    if model.showAddition {
                        additionFocused = true
                        #if os(macOS)
                            searchFocused = false
                        #endif
                    }
                }
            } label: {
                Image(systemName: model.showAddition ? "arrow.down.and.line.horizontal.and.arrow.up" : "plus")
            }
        }
        .searchable(text: $searcher.searchQuery, isPresented: $searchFocused, placement: .toolbar, prompt: "Search for keyword(s)")
    }
}
