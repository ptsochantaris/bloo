import Foundation
import SwiftUI

struct FilterField: View {
    @Binding var filter: String

    var body: some View {
        TextField("Filter", text: $filter)
            .textFieldStyle(PlainTextFieldStyle())
            .frame(width: 100)
            .padding(.top, 2)
            .padding(.bottom, 2.5)
            .padding(.horizontal, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.fill.tertiary)
            }
        #if canImport(UIKit)
            .offset(x: 0, y: -2)
            .font(.callout)
        #endif
    }
}
