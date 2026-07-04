import Foundation
import SwiftUI

struct Admin: View {
    private let model: BlooCore
    @Bindable private var searcher: Search.Engine

    @State private var showLog = false
    @State private var showSettings = false
    @State private var searchFocused = false
    @State private var logHeight: CGFloat = 300
    @FocusState private var additionFocused: Bool

    init(model: BlooCore, windowId: UUID) {
        self.model = model
        searcher = Search.Engine(windowId: windowId)
    }

    var body: some View {
        GeometryReader { proxy in
            adminBody(availableHeight: proxy.size.height)
        }
    }

    private func adminBody(availableHeight: CGFloat) -> some View {
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
                // Keep some space for the content above, however tall the window is
                let maxLogHeight = availableHeight * 0.90
                LogView(store: logStorage, showLog: $showLog, logHeight: $logHeight, maxHeight: maxLogHeight)
                    .frame(height: max(LogView.minHeight, min(logHeight, maxLogHeight)))
            }
        }
        .navigationTitle(searcher.title)
        .toolbar {
            #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    settingsButton
                }
            #else
                ToolbarItem(placement: .navigation) {
                    settingsButton
                }
            #endif
        }
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
        .sheet(isPresented: $showSettings) {
            SettingsSheet(model: model)
        }
        .focusedSceneValue(\.showSettings, $showSettings)
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
        // On macOS the Settings… menu item carries ⌘, — defining it here too would conflict
        #if !os(macOS)
        .keyboardShortcut(",", modifiers: .command)
        #endif
    }
}

private struct ShowSettingsKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var showSettings: Binding<Bool>? {
        get { self[ShowSettingsKey.self] }
        set { self[ShowSettingsKey.self] = newValue }
    }
}
