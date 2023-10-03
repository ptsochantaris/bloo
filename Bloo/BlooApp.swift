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
            func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
                if Model.shared.runState == .running {
                    Task {
                        await Model.shared.shutdown(backgrounded: false)
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
                    Model.shared.searchQuery = searchString
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
                    Model.shared.backgroundTask(task as! BGProcessingTask)
                }
                return true
            }
        }

        @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
        @Environment(\.scenePhase) private var scenePhase

    #endif

    private var model = Model.shared

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Menu("Re-index all domains") {
                    Button("Confirm") {
                        Task {
                            await model.resetAll()
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
        #elseif canImport(AppKit)
        .windowStyle(HiddenTitleBarWindowStyle())
        #endif
    }
}
