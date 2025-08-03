import CoreSpotlight
import SwiftUI

struct ContentView: View {
    @Environment(\.windowId) private var windowId

    private let model: BlooCore

    init(model: BlooCore) {
        self.model = model
    }

    var body: some View {
        NavigationStack {
            Admin(model: model, windowId: windowId)
            #if os(iOS)
                .background(Color.background)
                .scrollDismissesKeyboard(.immediately)
            #endif
        }
        .overlay {
            ModelStateFeedback(model: model)
        }
        #if os(iOS)
        .preferredColorScheme(.dark)
        #endif
    }
}
