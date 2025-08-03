import Foundation
import SwiftUI

struct Counter: View {
    let pending: Int
    let indexed: Int

    @State private var minIndexedWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            Text(pending, format: .number)
                .foregroundColor(.secondary)

            Image(systemName: "arrowtriangle.forward.fill")
                .imageScale(.small)
                .foregroundColor(.secondary)
                .scaleEffect(x: 0.6, y: 0.9)
                .opacity(0.8)

            Text(indexed, format: .number)
                .frame(minWidth: minIndexedWidth)
                .trackingWidth(to: $minIndexedWidth)
        }
        .font(.blooBody.bold())
    }
}
