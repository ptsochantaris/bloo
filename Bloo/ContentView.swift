import CoreSpotlight
import SwiftUI

private let wideCorner: CGFloat = 15
private let narrowCorner: CGFloat = 10
private let gridColumns = [GridItem(.adaptive(minimum: 320, maximum: 640))]

#if canImport(AppKit)

    extension Font {
        static let blooTitle = Font.title2
        static let blooFootnote = Font.footnote
        static let blooCaption = Font.caption
        static let blooCaption2 = Font.caption2
        static let blooBody = Font.body
    }

    private let backgroundOpacity = 0.4
    private let cellOpacity = 0.5
    private let resultOpacity = 0.6
    private let hspacing: CGFloat = 17
    private let titleInset: CGFloat = 4

#elseif canImport(UIKit)

    extension Font {
        static let blooTitle = Font.title3
        static let blooFootnote = Font.footnote
        static let blooCaption = Font.footnote
        static let blooCaption2 = Font.footnote
        static let blooBody = Font.body
    }

    private let backgroundOpacity = 0.5
    private let cellOpacity = 0.6
    private let resultOpacity = 0.7
    private let hspacing: CGFloat = 12
    private let titleInset: CGFloat = 0

#endif

private struct FooterText: View {
    let text: String

    var body: some View {
        Text(text)
            .lineLimit(2, reservesSpace: true)
            .font(.blooCaption2)
            .foregroundStyle(.secondary)
    }
}

private struct DomainTitle: View {
    @ObservedObject var domain: Domain

    var body: some View {
        HStack {
            domain.state.symbol
            Text(domain.id)
                .font(.blooBody)
                .bold()
        }
    }
}

private struct DomainRow: View, Identifiable {
    var id: String { domain.id }

    @ObservedObject var domain: Domain

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch domain.state {
            case let .loading(pending):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain)
                    Spacer(minLength: 0)
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
                        .font(.blooBody)
                        .bold()
                        .foregroundColor(.secondary)
                    Text("|")
                        .font(.blooBody)
                        .foregroundColor(.secondary)
                    Text(pending, format: .number)
                        .font(.blooBody)
                        .bold()
                }
                FooterText(text: url.absoluteString)

            case let .paused(indexed, pending, transitioning):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain)
                    Spacer(minLength: 0)
                    if transitioning {
                        Text("Pausing")
                            .font(.blooBody)
                    } else {
                        if indexed > 0 || pending > 0 {
                            Text(indexed, format: .number)
                                .font(.blooBody)
                                .bold()
                                .foregroundColor(.secondary)
                            Text("|")
                                .font(.blooBody)
                                .foregroundColor(.secondary)
                            Text(pending, format: .number)
                                .font(.blooBody)
                                .bold()
                        }
                    }
                }

            case .deleting:
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain)
                    Spacer(minLength: 0)
                    Text("Deleting")
                        .font(.blooBody)
                    ProgressView()
                        .scaleEffect(x: 0.4, y: 0.4)
                }

            case let .done(indexed):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing) {
                        Text(indexed, format: .number)
                            .font(.blooBody)
                            .bold()
                        Text("indexed")
                            .font(.blooFootnote)
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
    var id: String { result.id }
    let result: SearchResult

    @State var titleText: AttributedString?
    @State var descriptionText: AttributedString?

    @Environment(\.openURL) private var openURL

    init(result: SearchResult) {
        self.result = result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    if let update = result.updatedAt {
                        Text(update, style: .date)
                            .font(.blooCaption2)
                            .lineLimit(1)
                            .foregroundColor(.secondary)
                    }

                    Text(titleText ?? AttributedString(result.title))
                        .font(.blooBody)
                        .bold()
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
                .font(.blooBody)
                .foregroundStyle(.secondary)
                .task {
                    descriptionText = await Task.detached { result.attributedDescription }.value
                }

            Spacer(minLength: 0)

            VStack(alignment: .leading) {
                if let matched = result.matchedKeywords {
                    Text(matched)
                        .font(.blooCaption2)
                }

                Text(result.url.absoluteString)
                    .lineLimit(2)
                    .font(.blooCaption2)
                    .foregroundStyle(.accent)
            }
        }
        .onTapGesture {
            openURL(result.url)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(.fill.opacity(resultOpacity))
        .cornerRadius(narrowCorner)
    }
}

private struct AdditionRow: View {
    let id: String

    var body: some View {
        HStack(spacing: 0) {
            Text(id)
                .font(.blooBody)
                .bold()
            Spacer(minLength: 0)
        }
        .padding()
        .background(.fill.opacity(cellOpacity))
        .cornerRadius(narrowCorner)
    }
}

private struct DomainGrid: View, Identifiable {
    var id: String { section.state.id }
    let section: DomainSection
    @State private var actioning = false

    var body: some View {
        if section.domains.isPopulated {
            VStack(alignment: .leading) {
                HStack(alignment: .top) {
                    Text(section.state.title)
                        .font(.blooTitle)
                        .foregroundStyle(.secondary)

                    if !actioning {
                        Spacer(minLength: 0)

                        if section.state.canStart {
                            Button {
                                actioning = true
                                section.startAll()
                            } label: {
                                Text("Start All")
                            }
                        } else if section.state.canStop {
                            Button {
                                actioning = true
                                section.pauseAll()
                            } label: {
                                Text("Pause All")
                            }
                        } else if section.state.canRestart {
                            Button {
                                actioning = true
                                section.restartAll()
                            } label: {
                                Text("Re-Scan All")
                            }
                        }
                    }
                }
                .padding(.horizontal, titleInset)
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

private struct ResultsSection: View, Identifiable {
    let id = "Results"

    @ObservedObject var model: Model

    var body: some View {
        if model.searchState.resultMode {
            VStack(alignment: .leading, spacing: 16) {
                switch model.searchState {
                case .noResults:
                    Text("No results found")
                        .font(.blooTitle)

                case .noSearch:
                    Color.clear

                case .searching:
                    HStack {
                        ProgressView()
                            .scaleEffect(CGSize(width: 0.7, height: 0.7))

                        Text(" Searching")
                            .font(.blooTitle)
                            .foregroundStyle(.secondary)
                    }
                    .padding()

                case let .topResults(results):
                    HStack {
                        Text("Top Results")
                            .font(.blooTitle)
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
                        .font(.blooTitle)
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

struct StatusIcon: View {
    let name: String
    let color: Color

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            #if os(iOS)
                Color.black
                color.opacity(0.8)
            #else
                Color.black
                color.opacity(colorScheme == .dark ? 0.6 : 0.7)
            #endif

            Image(systemName: name)
                .font(.blooCaption)
                .fontWeight(.black)
                .foregroundStyle(.white)
        }
        .cornerRadius(5)
        .frame(width: 22, height: 22)
    }
}

private struct AdditionSection: View, Identifiable {
    let id = "Addition"

    @ObservedObject var model: Model

    @State private var input = ""
    @State private var results = [String]()

    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: hspacing) {
                Text("Add")
                    .font(.blooTitle)
                    .foregroundStyle(.secondary)

                TextField("Domain name or link", text: $input)
                #if canImport(UIKit)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .padding(8)
                    .background(.fill.opacity(backgroundOpacity))
                    .cornerRadius(8)
                #else
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                #endif

                Button {
                    let copy = results
                    Task {
                        input = ""
                        if copy.count == 1, let first = copy.first {
                            await model.addDomain(first, startAfterAdding: true)
                        } else {
                            for result in copy {
                                await model.addDomain(result, startAfterAdding: false)
                            }
                        }
                    }
                } label: {
                    Text("Create")
                }
            }
            .padding(.horizontal, titleInset)

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
    @ObservedObject var model: Model
    @State private var isSearching = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ResultsSection(model: model)

                    AdditionSection(model: model)

                    ForEach(model.domainSections) {
                        DomainGrid(section: $0)
                    }
                }
                .padding()
                .allowsHitTesting(model.isRunning)
            }
            .searchable(text: $model.searchQuery, isPresented: $isSearching)
            #if os(iOS)
                .background(Color.background)
            #endif
                .navigationTitle("Bloo")
        }
        .opacity(model.isRunning ? 1 : 0.6)
        #if os(macOS)
            .onAppear {
                Task { @MainActor in
                    if model.hasDomains {
                        isSearching = true
                    }
                }
            }
        #elseif os(iOS)
            .preferredColorScheme(.dark)
        #endif
            .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
                if let uid = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String, let url = URL(string: uid) {
                    openURL(url)
                }
            }
            .onContinueUserActivity(CSQueryContinuationActionType) { userActivity in
                if let searchString = userActivity.userInfo?[CSSearchQueryString] as? String {
                    model.searchQuery = searchString
                }
            }
    }
}
