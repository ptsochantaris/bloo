#if canImport(AppKit)
    import AppKit
#endif
import CoreSpotlight
import SwiftUI
import Maintini

#if canImport(AppKit)
    final class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
            if Model.shared.isRunning {
                Task {
                    await Model.shared.shutdown()
                    try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
                    NSApp.terminate(nil)
                }
                return .terminateCancel
            }
            return .terminateNow
        }
    }
#endif

@main
struct BlooApp: App {
    #if canImport(AppKit)
        @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif canImport(UIKit)
        @Environment(\.scenePhase) private var scenePhase
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Menu("Re-index all domains") {
                    Button("Confirm") {
                        Task {
                            await Model.shared.resetAll()
                        }
                    }
                }
            }
        }
        #if canImport(UIKit)
        .onChange(of: scenePhase) { _, new in
            switch new {
            case .active:
                Model.shared.resurrect()

            case .background:
                if Model.shared.isRunning {
                    Maintini.startMaintaining()
                    // TODO: schedule background processing
                    Task {
                        await Model.shared.shutdown()
                        Maintini.endMaintaining()
                    }
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
