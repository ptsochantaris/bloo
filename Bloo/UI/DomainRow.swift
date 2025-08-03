import Foundation
import SwiftUI

struct DomainRow: View {
    let domain: Domain

    var body: some View {
        VStack(alignment: .leading) {
            switch domain.state {
            case let .starting(indexed, pending):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain, subtitle: nil)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                ProgressView(value: Double(indexed) / max(1, Double(pending + indexed)))
                if pending == 0 {
                    FooterText(text: "Scanning sitemap")
                }

            case let .indexing(indexed, pending, url):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain, subtitle: nil)
                    Spacer(minLength: 0)
                    Counter(pending: pending, indexed: indexed)
                }
                ProgressView(value: Double(indexed) / max(1, Double(pending + indexed)))
                FooterText(text: url)

            case let .pausing(indexed, pending, _):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain, subtitle: nil)
                    Spacer(minLength: 0)
                    Text("Pausing")
                        .font(.blooBody)
                }
                ProgressView(value: Double(indexed) / max(1, Double(pending + indexed)))

            case let .paused(indexed, pending, _):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain, subtitle: nil)
                    Spacer(minLength: 0)
                    if indexed > 0 || pending > 0 {
                        Counter(pending: pending, indexed: indexed)
                    }
                }
                ProgressView(value: Double(indexed) / max(1, Double(pending + indexed)))

            case .deleting:
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain, subtitle: nil)
                    Spacer(minLength: 0)
                    Text("Deleting")
                        .font(.blooBody)
                }

            case let .done(indexed, completionDate):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    VStack {
                        if let completionDate {
                            let completion = Formatters.relativeTime(since: completionDate)
                            DomainTitle(domain: domain, subtitle: "Refreshed \(completion)")
                        } else {
                            DomainTitle(domain: domain, subtitle: nil)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(indexed, format: .number)
                        .font(.blooBody)
                        .bold()
                }
            }
        }
        .padding()
        .frame(maxHeight: .infinity)
        .lineLimit(1)
        .background(.fill.tertiary)
        .cornerRadius(Constants.narrowCorner)
        .contextMenu {
            DomainContextMenu(domain: domain)
        }
    }
}
