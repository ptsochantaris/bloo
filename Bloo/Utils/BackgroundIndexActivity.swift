#if os(iOS)
    import BackgroundTasks
    import Foundation
    import UIKit

    /// Bridges the crawler to iOS 26's continued-processing background task, so an active crawl keeps
    /// running with a system-provided Live Activity (title, subtitle, progress and a Cancel control)
    /// when the user minimises the app.
    ///
    /// The task is submitted at the moment the app *leaves the foreground* (`willResignActive`, the
    /// last foreground instant where submission is permitted), so the Live Activity only appears once
    /// no app window is visible — not while the user is actively in the app. When the app becomes
    /// active again the task is completed (dismissing the Live Activity) without pausing the crawl,
    /// which simply continues in the foreground. Its body monitors the existing crawler actors,
    /// mirrors their aggregate progress into the system UI, and pauses everything only if the user
    /// cancels via that UI.
    ///
    /// Note: the system cancels these tasks when the user deliberately *closes* the app, so this does
    /// not help the close-shutdown case — it only extends the *minimised* (backgrounded) crawl.
    enum BackgroundIndexActivity {
        // Continued-processing identifier rules:
        // - The `Info.plist` `BGTaskSchedulerPermittedIdentifiers` entry is the WILDCARD form
        //   `build.bru.bloo.app.indexing.*`; that only *permits submission* of ids under the prefix.
        // - The prefix MUST begin with the app's bundle id (build.bru.bloo.app) — unlike a regular
        //   BGProcessingTask identifier, continued-processing rejects a prefix without the bundle id
        //   ("invalid identifier form").
        // - `register(...)` and `submit(...)` must both use the SAME CONCRETE id: the system looks up
        //   launch handlers by exact identifier, so registering the wildcard crashes on relaunch with
        //   "No launch handler registered for task with identifier …". We submit one logical job at a
        //   time, so a single fixed concrete id is sufficient.
        private static let taskIdentifier = "build.bru.bloo.app.indexing.crawl"

        // Shared mutable state, touched from the launch handler, the foreground/background
        // notifications, and the monitor loop. A simple unchecked-Sendable box keeps every site in
        // agreement without actor ceremony for these flags.
        private final class State: @unchecked Sendable {
            var submitted = false
            var running = false
            var cancelled = false
            // The app starts in the foreground; the monitor loop dismisses its Live Activity whenever
            // this is true, so a task only stays alive while the app is backgrounded.
            var foreground = true
            // The live task and a one-shot completion guard, so the monitor loop and an external
            // close can't both call setTaskCompleted (and so we can dismiss promptly on close).
            var task: BGContinuedProcessingTask?
            var completed = false
        }

        private static let state = State()

        /// Completes the running task exactly once. `success: false` dismisses the Live Activity as an
        /// interruption (no "completed" checkmark); `success: true` is a genuine finish.
        private static func finish(success: Bool) {
            guard !state.completed else {
                return
            }
            state.completed = true
            state.task?.setTaskCompleted(success: success)
            state.task = nil
        }

        /// Dismisses the Live Activity immediately, e.g. when the user closes the app's window. The
        /// app is being torn down, so completing the task ourselves (quietly) beats the system's
        /// own cancellation, which otherwise leaves a stuck "task failed" Live Activity.
        static func finishImmediately() {
            finish(success: false)
        }

        /// True while a continued-processing task's body is actually running and owning an active
        /// crawl. The background lifecycle checks this to avoid pausing crawling on minimise: when a
        /// continued task is genuinely running it keeps the app alive and the crawl going, and it
        /// performs its own pause/persist (and schedules a headless resume) when it ends, is
        /// cancelled, or the system expires it. A merely-submitted-but-not-yet-started task does not
        /// count, so the normal pause/persist path still protects the crawl in that window.
        static var isActive: Bool {
            state.running
        }

        /// Registers the launch handler. Must run before app launch completes, alongside the other
        /// `BGTaskScheduler` registrations.
        static func register() {
            let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: .main) { task in
                guard let task = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                run(task)
            }
            if !registered {
                Log.app(.error).log("Failed to register continued-processing handler for \(taskIdentifier)")
            }

            // Submit as the app leaves the foreground (still a valid foreground moment) so the Live
            // Activity only shows once no window is visible; mark foreground again — which dismisses
            // the activity — as soon as the app becomes active.
            NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
                state.foreground = false
                submitIfNeeded()
            }
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                state.foreground = true
            }
        }

        /// Submits the continued-processing request if a crawl is currently busy and none is already
        /// in flight. Called as the app resigns active, so the task starts as the app backgrounds.
        static func submitIfNeeded() {
            guard !state.submitted, BlooCore.shared.isRunningAndBusy else {
                return
            }

            let request = BGContinuedProcessingTaskRequest(identifier: taskIdentifier,
                                                           title: "Indexing",
                                                           subtitle: "Crawling sites…")
            request.strategy = .queue

            do {
                try BGTaskScheduler.shared.submit(request)
                state.submitted = true
            } catch {
                Log.app(.error).log("Could not submit continued indexing task: \(error.localizedDescription)")
            }
        }

        private static func run(_ task: BGContinuedProcessingTask) {
            state.cancelled = false
            state.completed = false
            state.running = true
            state.task = task
            task.expirationHandler = {
                state.cancelled = true
                Log.app(.info).log("Background indexing cancelled via system UI")
            }

            let progress = task.progress
            progress.totalUnitCount = 100

            Task {
                defer {
                    state.running = false
                    state.submitted = false
                }

                // If the system launched us straight into the background to redeliver this task
                // (no preceding willResignActive), treat it as backgrounded so it keeps running
                // rather than dismissing immediately.
                let appState = await MainActor.run { UIApplication.shared.applicationState }
                if appState == .background {
                    state.foreground = false
                }

                // Allow a brief window for the crawl to report itself busy right after submission,
                // then exit once the app returns to the foreground (dismiss without pausing), the
                // crawl goes idle (completed), or the user cancels.
                var startupGrace = 3
                while !state.cancelled, !state.foreground, !state.completed {
                    let busy = await MainActor.run { BlooCore.shared.isRunningAndBusy }
                    if busy {
                        startupGrace = 0
                    } else if startupGrace > 0 {
                        startupGrace -= 1
                    } else {
                        break
                    }

                    let counts = await MainActor.run { BlooCore.shared.indexingProgress }
                    if counts.total > 0 {
                        progress.completedUnitCount = Int64(Double(counts.indexed) / Double(counts.total) * 100)
                        task.updateTitle("Indexing", subtitle: "Indexed \(counts.indexed.formatted()) of \(counts.total.formatted()) pages")
                    } else {
                        task.updateTitle("Indexing", subtitle: "Starting…")
                    }

                    try? await Task.sleep(for: .seconds(1))
                }

                if state.completed {
                    // Already dismissed externally (e.g. the window was closed); nothing to do.
                } else if state.cancelled {
                    // User cancelled via the system UI — pause and persist, then end the task as an
                    // interruption (not a completion).
                    do {
                        try await BlooCore.shared.shutdown(backgrounded: true)
                    } catch {
                        Log.app(.error).log("Error pausing crawl after cancel: \(error.localizedDescription)")
                    }
                    finish(success: false)
                } else if state.foreground {
                    // Returned to the foreground — dismiss the Live Activity quietly. Ending with
                    // success (and full progress) makes the system show a "completed" checkmark even
                    // though the crawl is still going, so finish as an interruption instead; the crawl
                    // simply carries on on screen.
                    finish(success: false)
                } else {
                    // The crawl genuinely finished while backgrounded — a real, successful completion.
                    progress.completedUnitCount = progress.totalUnitCount
                    finish(success: true)
                }
            }
        }
    }
#endif
