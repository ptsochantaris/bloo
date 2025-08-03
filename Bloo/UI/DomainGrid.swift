import Foundation
import SwiftUI

struct DomainGrid: View {
    let section: Domain.Section
    @State private var filter = ""

    var body: some View {
        if section.domains.isPopulated {
            VStack(alignment: .leading) {
                DomainSectionHeader(section: section, filter: $filter.animation())
                LazyVGrid(columns: Constants.gridColumns) {
                    ForEach(section.domains.filter { $0.matchesFilter(filter) }) { domain in
                        DomainRow(domain: domain)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .background(.fill.tertiary)
            .cornerRadius(Constants.wideCorner)
        }
    }
}
