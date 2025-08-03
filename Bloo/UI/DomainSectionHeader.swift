import Foundation
import SwiftUI

struct DomainSectionHeader: View {
    let section: Domain.Section
    @Binding var filter: String
    @State private var actioning = false

    var body: some View {
        HStack(alignment: .top) {
            Text(section.state.title)
                .font(.blooTitle)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if section.domains.count > 1 {
                FilterField(filter: $filter)
            }

            Group {
                if section.state.canStart {
                    Button {
                        actioning = true
                        Task {
                            try await section.startAll(matchingFilter: filter)
                            actioning = false
                        }
                    } label: {
                        Text(filter.isEmpty ? "Start All" : "Start")
                    }
                } else if section.state.canStop {
                    Button {
                        actioning = true
                        Task {
                            try await section.pauseAll(resumable: false, matchingFilter: filter)
                            actioning = false
                        }
                    } label: {
                        Text(filter.isEmpty ? "Pause All" : "Pause")
                    }
                } else if section.state.canRestart {
                    Button {
                        actioning = true
                        Task {
                            try await section.restartAll(wipingExistingData: false, matchingFilter: filter)
                            actioning = false
                        }
                    } label: {
                        Text(filter.isEmpty ? "Refresh All" : "Refresh")
                    }
                }
            }
            .opacity(actioning ? 0.1 : 1)
            .allowsHitTesting(!actioning)
        }
        .padding(.horizontal, Constants.titleInset)
    }
}
