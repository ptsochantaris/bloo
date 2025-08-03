import Foundation
import SwiftUI

struct DomainContextMenu: View {
    let domain: Domain

    @Environment(\.openURL) private var openURL

    var body: some View {
        if domain.state.canStart {
            Button { [weak domain] in
                Task { [weak domain] in
                    try await domain?.crawler.start()
                }
            } label: {
                Text("Start")
            }

            Button { [weak domain] in
                Task { [weak domain] in
                    try await domain?.crawler.remove()
                }
            } label: {
                Text("Remove")
            }

        } else if domain.state.canStop {
            Button { [weak domain] in
                Task { [weak domain] in
                    try await domain?.crawler.pause(resumable: false)
                }
            } label: {
                Text("Pause")
            }

        } else if domain.state.canRestart {
            Button { [weak domain] in
                Task { [weak domain] in
                    try await domain?.crawler.restart(wipingExistingData: false)
                }
            } label: {
                Text("Refresh")
            }

            Button { [weak domain] in
                Task { [weak domain] in
                    try await domain?.crawler.remove()
                }
            } label: {
                Text("Remove")
            }
        }
        Button { [weak domain] in
            Task { [weak domain] in
                if let domain, let url = URL(string: "https://\(domain.id)") {
                    openURL(url)
                }
            }
        } label: {
            Text("Open Site")
        }
    }
}
