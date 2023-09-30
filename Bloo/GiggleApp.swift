import AppKit
import CoreSpotlight
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_: NSApplication, continue userActivity: NSUserActivity, restorationHandler _: @escaping ([NSUserActivityRestoring]) -> Void) -> Bool {
        if let info = userActivity.userInfo {
            if userActivity.activityType == CSSearchableItemActionType, let uid = info[CSSearchableItemActivityIdentifier] as? String, let url = URL(string: uid) {
                NSWorkspace.shared.open(url)
                return true

            } else if userActivity.activityType == CSQueryContinuationActionType, let searchString = info[CSSearchQueryString] as? String {
                Model.shared.searchQuery = searchString
                return true
            }
        }
        return false
    }

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

@main
struct BlooApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
    }
}
