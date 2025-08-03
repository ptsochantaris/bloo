import Foundation
import SwiftUI

struct ModelStateFeedback: View {
    let model: BlooCore

    var body: some View {
        if model.runState == .stopped {
            OverlayMessage(title: "One Moment…", subtitle: "This operation can take up to a minute")

        } else if model.runState == .backgrounded {
            OverlayMessage(title: "Suspended", subtitle: "This operation will resume when device has enough power and resources to resume it")
        }
    }
}
