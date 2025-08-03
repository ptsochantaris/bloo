import Foundation
import SwiftUI

struct DomainTitle: View {
    let domain: Domain
    let subtitle: String?

    var body: some View {
        HStack {
            domain.state.symbol
            VStack(alignment: .leading) {
                Text(domain.id)
                    .font(.blooBody)
                    .bold()

                if let subtitle {
                    Text(subtitle)
                        .font(.blooCaption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
