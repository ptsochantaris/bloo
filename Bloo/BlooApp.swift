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

            func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
                if BlooCore.shared.runState == .running {
                    Task {
                        await BlooCore.shared.shutdown(backgrounded: false)
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
                BGTaskScheduler.shared.register(forTaskWithIdentifier: "build.bru.bloo.background", using: nil) { task in
                    BlooCore.shared.backgroundTask(task as! BGProcessingTask)
                }
                return true
            }
        }

        @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
        @Environment(\.scenePhase) private var scenePhase

    #endif

    private var model = BlooCore.shared
    private var settings = Settings.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    var body: some Scene {
        WindowGroup("Bloo", id: "search", for: UUID.self) { $uuid in
            ContentView(model: model, windowId: uuid)
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
            }
            CommandGroup(after: .appInfo) {
                Menu("All Items…") {
                    Menu("Clear all data") {
                        Button("Confirm: Clear Everything") {
                            Task {
                                await model.removeAll()
                            }
                        }
                    }
                    Menu("Re-index all domains") {
                        Button("Confirm: Reset All Domains") {
                            Task {
                                await model.resetAll()
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
                    await model.start()
                }

            case .background:
                Maintini.startMaintaining()
                Task {
                    await model.shutdown(backgrounded: true)
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
