import CoreSpotlight
import Maintini
import SwiftUI

@main
struct BlooApp: App {
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

        @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif canImport(UIKit)
        @Environment(\.scenePhase) private var scenePhase
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
                model.resurrect()

            case .background:
                if model.isRunning {
                    Maintini.startMaintaining()
                    // TODO: schedule background processing
                    Task {
                        await model.shutdown()
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
