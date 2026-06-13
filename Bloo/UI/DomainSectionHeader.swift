import Foundation
import SwiftUI

struct DomainSectionHeader: View {
    let section: Domain.Section
    @Binding var filter: String
    @State private var actioning = false

    private let settings = Settings.shared

    var body: some View {
        let collapsed = settings.isSectionCollapsed(section.id)

        HStack(alignment: .top) {
            Button {
                withAnimation {
                    settings.toggleSection(section.id)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                    Text(section.state.title)
                }
                .font(.blooTitle)
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            if !collapsed, section.domains.count > 1 {
                FilterField(filter: $filter)
            }

            Group {
                if section.state.canStart {
                    Button {
                        actioning = true
                        Task {
                            defer { actioning = false }
                            do {
                                try await section.startAll(matchingFilter: filter)
                            } catch {
                                ErrorReporter.shared.report(error)
                            }
                        }
                    } label: {
                        Text(filter.isEmpty ? "Start All" : "Start")
                    }
                } else if section.state.canStop {
                    Button {
                        actioning = true
                        Task {
                            defer { actioning = false }
                            do {
                                try await section.pauseAll(resumable: false, matchingFilter: filter)
                            } catch {
                                ErrorReporter.shared.report(error)
                            }
                        }
                    } label: {
                        Text(filter.isEmpty ? "Pause All" : "Pause")
                    }
                } else if section.state.canRestart {
                    Button {
                        actioning = true
                        Task {
                            defer { actioning = false }
                            do {
                                try await section.restartAll(wipingExistingData: false, matchingFilter: filter)
                            } catch {
                                ErrorReporter.shared.report(error)
                            }
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
