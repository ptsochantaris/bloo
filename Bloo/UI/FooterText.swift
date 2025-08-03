import Foundation
import SwiftUI

struct FooterText: View {
    let text: String
    @State var minHeight: CGFloat = 0

    var body: some View {
        Text(text)
            .lineLimit(2, reservesSpace: true)
            .font(.blooCaption2)
            .foregroundStyle(.secondary)
            .frame(minHeight: minHeight)
            .trackingHeight(to: $minHeight)
    }
}
