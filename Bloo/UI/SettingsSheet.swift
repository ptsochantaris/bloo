import SwiftUI

struct SettingsSheet: View {
    private let model: BlooCore

    @Bindable private var settings = Settings.shared
    @Environment(\.dismiss) private var dismiss

    @State private var confirmClear = false
    @State private var confirmReset = false

    private let delayRange = 0.1 ... 10.0

    init(model: BlooCore) {
        self.model = model
    }

    /// Wraps a `TimeInterval` binding so the slider stays continuous (no visible tick marks) while
    /// the stored value is still quantised to the nearest 0.1 second.
    private func roundedBinding(for source: Binding<TimeInterval>) -> Binding<TimeInterval> {
        Binding {
            source.wrappedValue
        } set: { newValue in
            source.wrappedValue = (newValue * 10).rounded() / 10
        }
    }

    /// The human-readable value for the current "Simultaneous calls" setting.
    private var simultaneousCallsLabel: String {
        let value = settings.maxSimultaneousCalls
        return value == 0 ? "Unlimited" : "\(value)"
    }

    /// Maps the discrete `simultaneousCallOptions` to a continuous slider position so the slider can
    /// step through 1, 2, 4, 8, 16 and Unlimited.
    private var simultaneousCallsBinding: Binding<Double> {
        Binding {
            let index = Settings.simultaneousCallOptions.firstIndex(of: settings.maxSimultaneousCalls) ?? Settings.simultaneousCallOptions.count - 1
            return Double(index)
        } set: { newValue in
            let index = min(max(Int(newValue.rounded()), 0), Settings.simultaneousCallOptions.count - 1)
            settings.maxSimultaneousCalls = Settings.simultaneousCallOptions[index]
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Throttling") {
                    VStack(alignment: .leading) {
                        Text(String(format: "Minimum rate for new pages: %.1f sec", settings.indexingDelay))
                        Slider(value: roundedBinding(for: $settings.indexingDelay), in: delayRange)
                    }

                    VStack(alignment: .leading) {
                        Text(String(format: "Minimum rate for checking existing pages: %.1f sec", settings.indexingScanDelay))
                        Slider(value: roundedBinding(for: $settings.indexingScanDelay), in: delayRange)
                    }

                    Toggle("Only Use Efficiency CPU Cores", isOn: Binding<Bool> {
                        settings.indexingTaskPriority == .background
                    } set: { newValue in
                        settings.indexingTaskPriority = newValue ? .background : .medium
                    })

                    VStack(alignment: .leading) {
                        Text("Simultaneous calls: \(simultaneousCallsLabel)")
                        Slider(value: simultaneousCallsBinding, in: 0 ... Double(Settings.simultaneousCallOptions.count - 1), step: 1)
                    }
                }

                Section("Sort \"Done\" Section") {
                    Picker("Sort order", selection: $settings.sortDoneStyle) {
                        ForEach(SortStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                }

                Section("All Items") {
                    Button("Clear all data…", role: .destructive) {
                        confirmClear = true
                    }
                    .confirmationDialog("Clear all indexed data?", isPresented: $confirmClear, titleVisibility: .visible) {
                        Button("Clear Everything", role: .destructive) {
                            runReportingErrors {
                                try await model.removeAll()
                            }
                        }
                    } message: {
                        Text("This will remove all domains and their indexed content.")
                    }

                    Button("Wipe and Reindex All Domains…", role: .destructive) {
                        confirmReset = true
                    }
                    .confirmationDialog("Wipe and reindex all domains?", isPresented: $confirmReset, titleVisibility: .visible) {
                        Button("Reset All Domains", role: .destructive) {
                            runReportingErrors {
                                try await model.resetAll()
                            }
                        }
                    } message: {
                        Text("This will wipe and re-crawl every domain from scratch.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 440)
        #endif
    }
}
