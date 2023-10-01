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
                        try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
                        NSApp.terminate(nil)
                    }
                    return .terminateCancel
                }
                return .terminateNow
            }
        }

        @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif canImport(UIKit)
        final class AppDelegate: NSObject, UIApplicationDelegate {
            func application(_: UIApplication, willFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
                BGTaskScheduler.shared.register(forTaskWithIdentifier: "build.bru.bloo.background", using: nil) { task in
                    Model.shared.backgroundTask(task as! BGProcessingTask)
                }
            }
        }

        @Environment(\.scenePhase) private var scenePhase
        @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    @ObservedObject private var model = Model.shared

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
        #endif
    }
}
