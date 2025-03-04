import CoreSpotlight
import Maintini
import SwiftUI
#if os(iOS)
    import BackgroundTasks
#endif

@main
struct BlooApp: App {
    #if canImport(AppKit)

        final class AppDelegate: NSObject, NSApplicationDelegate {
            var newSearch: String?

            func applicationDidFinishLaunching(_: Notification) {
                Maintini.setup()
            }

            func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
                if BlooCore.shared.runState == .running {
                    Task {
                        try await BlooCore.shared.shutdown(backgrounded: false)
                        try? await Task.sleep(for: .milliseconds(100))
                        NSApp.terminate(nil)
                    }
                    return .terminateCancel
                }
                return .terminateNow
            }

            func application(_: NSApplication, continue userActivity: NSUserActivity, restorationHandler _: @escaping ([NSUserActivityRestoring]) -> Void) -> Bool {
                if userActivity.activityType == CSSearchableItemActionType, let uid = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String, let url = URL(string: uid) {
                    NSWorkspace.shared.open(url)
                    return true
                }

                if userActivity.activityType == CSQueryContinuationActionType, let searchString = userActivity.userInfo?[CSSearchQueryString] as? String {
                    newSearch = searchString
                    return true
                }

                return false
            }
        }

        @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    #elseif canImport(UIKit)

        final class AppDelegate: NSObject, UIApplicationDelegate {
            func application(_: UIApplication, willFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
                Maintini.setup()
                BGTaskScheduler.shared.register(forTaskWithIdentifier: "build.bru.bloo.background", using: DispatchQueue.main) { task in
                    BlooCore.shared.backgroundTask(task as! BGProcessingTask)
                }
                return true
            }
        }

        @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
        @Environment(\.scenePhase) private var scenePhase

    #endif

    private let model = BlooCore.shared
    private let settings = Settings.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    private struct DelayEntry: Identifiable {
        let id = UUID()
        let value: Double

        func label(prefix: String) -> String {
            String(format: "%@ %.1f sec", prefix, value)
        }
    }

    var body: some Scene {
        WindowGroup("Bloo", id: "search", for: UUID.self) { $uuid in
            ContentView(model: model)
                .environment(\.windowId, uuid)
            #if os(macOS)
                .onChange(of: appDelegate.newSearch) {
                    if let newSearch = appDelegate.newSearch {
                        appDelegate.newSearch = nil
                        openWindow(id: "main", value: newSearch)
                    }
                }
            #elseif os(iOS)
                .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
                    if let uid = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String, let url = URL(string: uid) {
                        openURL(url)
                    }
                }
                .onContinueUserActivity(CSQueryContinuationActionType) { userActivity in
                    if let searchString = userActivity.userInfo?[CSSearchQueryString] as? String {
                        openWindow(id: "main", value: searchString)
                    }
                }
            #endif
        } defaultValue: {
            UUID()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Menu("Throttling…") {
                    let range = Array(stride(from: 0.1, through: 10, by: 0.1)).map {
                        DelayEntry(value: $0)
                    }

                    Menu("Minimum rate for new pages…") {
                        ForEach(range) { item in
                            Toggle(item.label(prefix: "Minimum"), isOn: Binding<Bool> {
                                settings.indexingDelay == item.value
                            } set: { _ in
                                settings.indexingDelay = item.value
                            })
                        }
                    }

                    Menu("Minimum rate for checking existing pages…") {
                        ForEach(range) { item in
                            Toggle(item.label(prefix: "Delay"), isOn: Binding<Bool> {
                                settings.indexingScanDelay == item.value
                            } set: { _ in
                                settings.indexingScanDelay = item.value
                            })
                        }
                    }

                    Toggle("Only Use Efficiency CPU Cores", isOn: Binding<Bool> {
                        settings.indexingTaskPriority == .background
                    } set: { newValue in
                        settings.indexingTaskPriority = newValue ? .background : .medium
                    })

                    Toggle("Minimise Network Usage", isOn: Binding<Bool> {
                        settings.maxConcurrentIndexingOperations == 1
                    } set: { newValue in
                        settings.maxConcurrentIndexingOperations = newValue ? 1 : 0
                    })
                }

                Menu("Sort \"Done\" Section…") {
                    ForEach(SortStyle.allCases) { style in
                        Toggle(style.title, isOn: Binding<Bool> {
                            settings.sortDoneStyle == style
                        } set: { _ in
                            settings.sortDoneStyle = style
                        })
                    }
                }

                Menu("All Items…") {
                    Menu("Clear all data") {
                        Button("Confirm: Clear Everything!") {
                            Task {
                                try await model.removeAll()
                            }
                        }
                    }
                    Menu("Wipe and Reindex All Domains") {
                        Button("Confirm: Reset All Domains!") {
                            Task {
                                try await model.resetAll()
                            }
                        }
                    }
                }
            }
        }
        #if canImport(UIKit)
        .onChange(of: scenePhase) { _, new in
            switch new {
            case .active:
                Task {
                    try! await model.start()
                }

            case .background:
                Maintini.startMaintaining()
                Task {
                    try await model.shutdown(backgrounded: true)
                    Maintini.endMaintaining()
                }

            case .inactive:
                fallthrough

            @unknown default:
                break
            }
        }
        #endif
    }
}
