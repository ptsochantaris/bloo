import SwiftUI

private let wideCorner: CGFloat = 15
private let narrowCorner: CGFloat = 10

private let backgroundOpacity = 0.4
private let cellOpacity = 0.5
private let resultOpacity = 0.6

private struct FooterText: View {
    let text: String

    var body: some View {
        Text(text)
            .lineLimit(2, reservesSpace: true)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

private struct DomainTitle: View {
    @ObservedObject var domain: Domain

    var body: some View {
        HStack {
            domain.state.symbol
            Text(domain.id)
                .font(.headline)
        }
    }
}

private struct DomainRow: View {
    @ObservedObject var domain: Domain

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch domain.state {
            case let .loading(pending):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain)
                    Spacer(minLength: 0)
                    Text(pending, format: .number)
                        .bold()
                }
                .frame(maxHeight: .infinity)
                if pending == 0 {
                    FooterText(text: "Scanning sitemap(s)")
                }

            case let .indexing(indexed, pending, url):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain)
                    Spacer(minLength: 0)
                    Text(indexed, format: .number)
                        .bold()
                        .foregroundColor(.secondary)
                    Text("|")
                        .foregroundColor(.secondary)
                    Text(pending, format: .number)
                        .bold()
                }
                FooterText(text: url.absoluteString)

            case let .paused(indexed, pending, transitioning):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain)
                    Spacer(minLength: 0)
                    if transitioning {
                        Text("Pausing")
                            .foregroundStyle(.accent)
                        ProgressView()
                            .scaleEffect(x: 0.4, y: 0.4)
                            .tint(.accentColor)
                    } else {
                        if indexed > 0 || pending > 0 {
                            Text(indexed, format: .number)
                                .bold()
                                .foregroundColor(.secondary)
                            Text("|")
                                .foregroundColor(.secondary)
                            Text(pending, format: .number)
                                .bold()
                        }
                    }
                }

            case .deleting:
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain)
                    Spacer(minLength: 0)
                    Text("Deleting")
                        .foregroundStyle(.accent)
                    ProgressView()
                        .scaleEffect(x: 0.4, y: 0.4)
                        .tint(.accentColor)
                }

            case let .done(indexed):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing) {
                        Text(indexed, format: .number)
                            .bold()
                        Text("indexed")
                            .font(.footnote)
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxHeight: .infinity)
        .lineLimit(1)
        .background(.fill.opacity(cellOpacity))
        .cornerRadius(narrowCorner)
        .contextMenu {
            if domain.state.canStart {
                Button { [weak domain] in
                    Task { [weak domain] in
                        await domain?.start()
                    }
                } label: {
                    Text("Start")
                }
                Button { [weak domain] in
                    Task { [weak domain] in
                        await domain?.remove()
                    }
                } label: {
                    Text("Remove")
                }
            } else if domain.state.canStop {
                Button { [weak domain] in
                    Task { [weak domain] in
                        await domain?.pause()
                    }
                } label: {
                    Text("Pause")
                }
            } else if domain.state.canRestart {
                Button { [weak domain] in
                    Task { [weak domain] in
                        await domain?.restart()
                    }
                } label: {
                    Text("Re-Scan")
                }
                Button { [weak domain] in
                    Task { [weak domain] in
                        await domain?.remove()
                    }
                } label: {
                    Text("Remove")
                }
            }
        }
    }
}

private struct ResultRow: View, Identifiable {
    let id: String
    let result: SearchResult

    @State var titleText: AttributedString?
    @State var descriptionText: AttributedString?

    init(result: SearchResult) {
        id = result.id
        self.result = result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    if let update = result.updatedAt {
                        Text(update, style: .date)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundColor(.secondary)
                    }

                    Text(titleText ?? AttributedString(result.title))
                        .font(.headline)
                        .lineLimit(2, reservesSpace: true)
                        .task {
                            titleText = await Task.detached { result.attributedTitle }.value
                        }
                }

                Spacer(minLength: 0)

                if let thumbnailUrl = result.thumbnailUrl {
                    AsyncImage(url: thumbnailUrl) { phase in
                        switch phase {
                        case let .success(img):
                            img.resizable()
                                .frame(width: 44, height: 44)
                                .cornerRadius(22)
                                .offset(x: 5, y: -5)
                        case .empty, .failure:
                            Color.clear
                        @unknown default:
                            Color.clear
                        }
                    }
                }
            }

            Text(descriptionText ?? AttributedString(result.descriptionText))
                .lineLimit(14)
                .font(.body)
                .foregroundStyle(.secondary)
                .task {
                    descriptionText = await Task.detached { result.attributedDescription }.value
                }

            Spacer(minLength: 0)

            VStack(alignment: .leading) {
                if let matched = result.matchedKeywords {
                    Text(matched)
                        .font(.caption2)
                }

                Text(result.url.absoluteString)
                    .lineLimit(2)
                    .font(.caption2)
                    .foregroundStyle(.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(.fill.opacity(resultOpacity))
        .cornerRadius(narrowCorner)
        .onTapGesture {
            NSWorkspace.shared.open(result.url)
        }
    }
}

private struct AdditionRow: View {
    let id: String

    var body: some View {
        HStack(spacing: 0) {
            Text(id)
                .font(.headline)
            Spacer(minLength: 0)
        }
        .padding()
        .background(.fill.opacity(cellOpacity))
        .cornerRadius(narrowCorner)
    }
}

private let gridColumns = [GridItem(.adaptive(minimum: 320, maximum: 640))]

private struct DomainGrid: View, Identifiable {
    var id: String { section.id }
    let section: Model.DomainSection

    var body: some View {
        if section.domains.isPopulated {
            VStack(alignment: .leading) {
                HStack(alignment: .top) {
                    Text(" " + section.state.title)
                        .font(.title)
                        .foregroundStyle(.secondary)

                    if section.actionable {
                        Spacer(minLength: 0)

                        if section.state.canStart {
                            Button { [weak section] in
                                section?.startAll()
                            } label: {
                                Text("Start All")
                            }
                        } else if section.state.canStop {
                            Button { [weak section] in
                                section?.pauseAll()
                            } label: {
                                Text("Pause All")
                            }
                        } else if section.state.canRestart {
                            Button { [weak section] in
                                section?.restartAll()
                            } label: {
                                Text("Re-Scan All")
                            }
                        }
                    }
                }
                LazyVGrid(columns: gridColumns) {
                    ForEach(section.domains) { domain in
                        DomainRow(domain: domain)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .background(.fill.opacity(backgroundOpacity))
            .cornerRadius(wideCorner)
        }
    }
}

private struct ResultsSection: View {
    @ObservedObject private var model = Model.shared

    var body: some View {
        if model.searchState.resultMode {
            VStack(alignment: .leading, spacing: 16) {
                switch model.searchState {
                case .noResults:
                    Text("No results found")
                        .font(.title)

                case .noSearch:
                    Color.clear

                case .searching:
                    HStack {
                        ProgressView()
                            .scaleEffect(CGSize(width: 0.7, height: 0.7))

                        Text(" Searching")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                    .padding()

                case let .topResults(results):
                    HStack {
                        Text("Top Results")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button {
                            model.resetQuery(full: true)
                        } label: {
                            Text("See More")
                        }
                    }
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(results) {
                                ResultRow(result: $0)
                                    .frame(width: 320)
                            }
                        }
                    }
                    .scrollClipDisabled()
                    .frame(maxWidth: .infinity)

                case let .moreResults(results):
                    Text(results.count > 1 ? " \(results.count, format: .number) Results" : "1 Result")
                        .font(.title)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: gridColumns) {
                        ForEach(results) {
                            ResultRow(result: $0)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct AdditionSection: View {
    @ObservedObject private var model = Model.shared
    @State private var input = ""
    @State private var results = [String]()

    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 17) {
                Text(" Add")
                    .font(.title)
                    .foregroundStyle(.secondary)

                TextField("Domain name or link", text: $input)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button {
                    Task {
                        let copy = results
                        for result in copy {
                            await model.addDomain(result)
                        }
                        input = ""
                    }
                } label: {
                    Text("Create")
                }
            }
            if results.isPopulated {
                LazyVGrid(columns: gridColumns) {
                    ForEach(results, id: \.self) {
                        AdditionRow(id: $0)
                    }
                }
            }
        }
        .padding()
        .background(.fill.opacity(backgroundOpacity))
        .cornerRadius(wideCorner)
        .onChange(of: input) { _, newValue in
            Task { @MainActor in
                let list = newValue.split(separator: " ").map {
                    $0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                }.map { text -> String in
                    if text.contains("//") {
                        return String(text)
                    } else {
                        return "https://\(String(text))"
                    }
                }.compactMap {
                    try? URL.create(from: $0, relativeTo: nil, checkExtension: true)
                }.filter {
                    let h = $0.host ?? ""
                    return h.isEmpty ? false : !model.contains(domain: h)
                }.map(\.absoluteString)
                results = Set(list).sorted()
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject private var model = Model.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ResultsSection()

                AdditionSection()

                ForEach(model.domainSections) {
                    DomainGrid(section: $0)
                }
            }
            .padding()
        }
        .allowsHitTesting(model.isRunning)
        .opacity(model.isRunning ? 1 : 0.6)
        .searchable(text: $model.searchQuery)
    }
}
