import Foundation
import SwiftUI

struct DomainSectionHeader: View {
    let section: Domain.Section
    @Binding var filter: String
    @State private var actioning = false
    @State private var headerWidth: CGFloat = 0

    private let settings = Settings.shared

    private var countText: String {
        let count = section.domains.count
        return count == 1 ? "1 item" : "\(count) items"
    }

    private var totals: Domain.Section.Totals? {
        if case .indexing = section.state {
            section.totals
        } else {
            nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let totals {
                HStack(alignment: .center) {
                    titleButton
                    Spacer(minLength: 0)
                    // The counter needs elbow room next to the title and the controls, so it only
                    // appears when the header is wide enough to hold all three comfortably
                    if headerWidth >= Constants.sectionTotalsMinimumWidth {
                        Counter(pending: totals.pending, indexed: totals.indexed)
                    }
                    controls
                }

                ProgressView(value: totals.progress)

            } else {
                HStack(alignment: .top) {
                    titleButton
                    Spacer(minLength: 0)
                    controls
                }
            }
        }
        .trackingWidth(to: $headerWidth)
        .padding(.horizontal, Constants.titleInset)
    }

    private var titleButton: some View {
        let collapsed = settings.isSectionCollapsed(section.id)

        return Button {
            withAnimation {
                settings.toggleSection(section.id)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.blooTitle)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                VStack(alignment: .leading, spacing: 0) {
                    Text(section.state.title)
                        .font(.blooTitle)
                    Text(countText)
                        .font(.blooCaption2)
                }
            }
            .foregroundStyle(.secondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var controls: some View {
        if !settings.isSectionCollapsed(section.id), section.domains.count > 1 {
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
}
