import CanProceed
import Foundation
import SwiftUI

struct RobotEditor: View {
    @State var check: CanProceed

    var body: some View {
        Grid(verticalSpacing: 20) {
            GridRow(alignment: .top) {
                Text("Host")
                    .gridColumnAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Text(check.host ?? "<no host>")
                    .gridColumnAlignment(.leading)
                    .bold()
            }

            GridRow(alignment: .top) {
                let sortedSitemaps = check.sitemaps.sorted()
                Text("Sitemaps")
                    .gridColumnAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)

                VStack(alignment: .leading) {
                    ForEach(sortedSitemaps, id: \.self) {
                        Text($0)
                    }
                }
            }

            GridRow(alignment: .top) {
                Text("Agents")
                    .gridColumnAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)

                let sortedAgents = Array(check.agents.keys.map { String($0) }).sorted()
                Grid(alignment: .topLeading, horizontalSpacing: 20) {
                    ForEach(sortedAgents, id: \.self) { agentName in
                        let agent = check.agents[agentName]!
                        GridRow {
                            Text(agentName)
                                .bold()

                            Spacer()
                        }

                        GridRow {
                            VStack(alignment: .leading) {
                                let allowedRecords = Array(agent.allow.enumerated())
                                ForEach(allowedRecords, id: \.offset) { record in
                                    Text(record.element.originalRecordString)
                                }
                            }
                            .foregroundStyle(.green)

                            VStack(alignment: .leading) {
                                let disallowedRecords = Array(agent.disallow.enumerated())
                                ForEach(disallowedRecords, id: \.offset) { record in
                                    Text(record.element.originalRecordString)
                                }
                            }
                            .foregroundStyle(.red)
                        }
                        .padding(.bottom)
                    }
                }
            }
        }
        .fixedSize()
        .padding()
    }
}

#Preview {
    @Previewable var check = CanProceed.parse(
        """
        # Comments should be ignored.
        # Short bot test part 1.
        User-agent: Longbot
        Allow: /cheese
        Allow: /swiss
        Allow: /swissywissy
        Disallow: /swissy
        Crawl-delay: 3
        Sitemap: http://www.bbc.co.uk/news_sitemap.xml
        Sitemap: http://www.bbc.co.uk/video_sitemap.xml
        Sitemap: http://www.bbc.co.uk/sitemap.xml

        User-agent: MoreBot
        Allow: /
        Disallow: /search
        Disallow: /news
        Crawl-delay: 89
        Sitemap: http://www.bbc.co.uk/sitemap.xml

        User-agent: *
        Allow: /news
        Allow: /Testytest
        Allow: /Test/small-test
        Disallow: /
        Disallow: /spec
        Crawl-delay: 64
        Sitemap: http://www.bbc.co.uk/mobile_sitemap.xml

        Sitemap: http://www.bbc.co.uk/test.xml
        host: http://www.bbc.co.uk
        """)

    RobotEditor(check: check)
}
