import SwiftUI

/// App-wide sink for errors that should be shown to the user. A single alert, attached near the
/// root of the view tree via `errorReportingAlert()`, presents whatever is reported here.
@MainActor
@Observable
final class ErrorReporter {
    static let shared = ErrorReporter()

    private init() {}

    struct Report: Identifiable {
        let id = UUID()
        let message: String
    }

    var current: Report?

    func report(_ error: Error) {
        Log.app(.error).log("Surfacing error to user: \(error.localizedDescription)")
        current = Report(message: error.localizedDescription)
    }
}

/// Runs an async throwing operation in a new task, surfacing any thrown error to the user as an
/// alert. Because the task itself no longer throws, it also silences the "unstructured throwing
/// task is not used" warning while making sure errors are never silently dropped.
@MainActor
func runReportingErrors(_ operation: @escaping () async throws -> Void) {
    Task {
        do {
            try await operation()
        } catch {
            ErrorReporter.shared.report(error)
        }
    }
}

extension View {
    func errorReportingAlert() -> some View {
        modifier(ErrorReportingAlert())
    }
}

private struct ErrorReportingAlert: ViewModifier {
    @State private var reporter = ErrorReporter.shared

    func body(content: Content) -> some View {
        content.alert(
            "Something Went Wrong",
            isPresented: Binding {
                reporter.current != nil
            } set: { presented in
                if !presented { reporter.current = nil }
            },
            presenting: reporter.current
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { report in
            Text(report.message)
        }
    }
}
