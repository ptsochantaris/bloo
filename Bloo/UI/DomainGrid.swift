import Foundation
import SwiftUI

struct DomainGrid: View {
    let section: Domain.Section
    @State private var filter = ""

    private let settings = Settings.shared

    var body: some View {
        if section.domains.isPopulated {
            VStack(alignment: .leading) {
                DomainSectionHeader(section: section, filter: $filter.animation())
                if !settings.isSectionCollapsed(section.id) {
                    LazyVGrid(columns: Constants.gridColumns) {
                        ForEach(section.domains.filter { $0.matchesFilter(filter) }) { domain in
                            DomainRow(domain: domain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .background(.fill.tertiary)
            .cornerRadius(Constants.wideCorner)
        }
    }
}
