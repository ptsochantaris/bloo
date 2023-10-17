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
    let domain: Domain

    var body: some View {
        HStack {
            domain.state.symbol
            Text(domain.id)
                .font(.blooBody)
                .bold()
        }
    }
}

private struct Triangle: View {
    var body: some View {
        Image(systemName: "arrowtriangle.forward.fill")
            .imageScale(.small)
            .font(.blooBody)
            .foregroundColor(.secondary)
            .scaleEffect(x: 0.6, y: 0.9)
            .opacity(0.8)
    }
}

private struct DomainRow: View {
    let domain: Domain

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading) {
            switch domain.state {
            case .loading:
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)

            case let .starting(indexed, pending):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                ProgressView(value: Double(indexed) / max(1, Double(pending + indexed)))
                if pending == 0 {
                    FooterText(text: "Scanning sitemap")
                }

            case let .indexing(indexed, pending, url):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain)
                    Spacer(minLength: 0)
                    HStack(spacing: 2) {
                        Text(pending, format: .number)
                            .font(.blooBody).bold()
                            .foregroundColor(.secondary)
                        Triangle()
                        Text(indexed, format: .number)
                            .font(.blooBody).bold()
                            .bold()
                    }
                }
                ProgressView(value: Double(indexed) / max(1, Double(pending + indexed)))
                FooterText(text: url)

            case let .paused(indexed, pending, transitioning, _):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain)
                    Spacer(minLength: 0)
                    if transitioning {
                        Text("Pausing")
                            .font(.blooBody)
                    } else if indexed > 0 || pending > 0 {
                        HStack(spacing: 2) {
                            Text(pending, format: .number)
                                .font(.blooBody).bold()
                                .foregroundColor(.secondary)
                            Triangle()
                            Text(indexed, format: .number)
                                .font(.blooBody).bold()
                                .bold()
                        }
                    }
                }
                ProgressView(value: Double(indexed) / max(1, Double(pending + indexed)))

            case .deleting:
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain)
                    Spacer(minLength: 0)
                    Text("Deleting")
                        .font(.blooBody)
                }

            case let .done(indexed):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain)
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
        .background(.fill.opacity(cellOpacity))
        .cornerRadius(narrowCorner)
        .contextMenu {
            if domain.state.canStart {
                Button { [weak domain] in
                    Task { [weak domain] in
                        try await domain?.start()
                    }
                } label: {
                    Text("Start")
                }
                Button { [weak domain] in
                    Task { [weak domain] in
                        try await domain?.remove()
                    }
                } label: {
                    Text("Remove")
                }
            } else if domain.state.canStop {
                Button { [weak domain] in
                    Task { [weak domain] in
                        try await domain?.pause(resumable: false)
                    }
                } label: {
                    Text("Pause")
                }
            } else if domain.state.canRestart {
                Button { [weak domain] in
                    Task { [weak domain] in
                        try await domain?.restart(wipingExistingData: false)
                    }
                } label: {
                    Text("Refresh")
                }
                Button { [weak domain] in
                    Task { [weak domain] in
                        try await domain?.remove()
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
}

private struct ResultRow: View {
    let result: Search.Result

    @State var titleText: AttributedString?
    @State var descriptionText: AttributedString?

    @Environment(\.openURL) private var openURL

    init(result: Search.Result) {
        self.result = result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    if let entryDate = result.displayDate {
                        Text(entryDate, style: .date)
                            .font(.blooCaption2)
                            .lineLimit(1)
                            .foregroundColor(.secondary)
                    }

                    Text(titleText ?? AttributedString(result.title))
                        .font(.blooBody)
                        .bold()
                        .lineLimit(2, reservesSpace: true)
                        .task {
                            titleText = await Task.detached { [result] in result.attributedTitle }.value
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
                            EmptyView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }

            Text(descriptionText ?? "")
                .lineLimit(4, reservesSpace: true)
                .font(.blooBody)
                .foregroundStyle(.secondary)
                .task {
                    descriptionText = await Task.detached { [result] in result.attributedDescription }.value
                }

            Spacer(minLength: 0)

            VStack(alignment: .leading) {
                if let matched = result.matchedKeywords {
                    Text(matched)
                        .font(.blooCaption2)
                }

                Text(result.id)
                    .lineLimit(2)
                    .font(.blooCaption2)
                    .foregroundStyle(.accent)
            }
        }
        .onTapGesture {
            if let url = result.url {
                openURL(url)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(.fill.opacity(resultOpacity))
        .cornerRadius(narrowCorner)
    }
}

private struct AdditionRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .font(.blooBody)
                .bold()
            Spacer(minLength: 0)
        }
        .padding()
        .background(.fill.opacity(cellOpacity))
        .cornerRadius(narrowCorner)
    }
}

private struct FilterField: View {
    @Binding var filter: String

    var body: some View {
        TextField("Filter", text: $filter)
            .textFieldStyle(PlainTextFieldStyle())
            .frame(width: 100)
            .padding(.top, 2)
            .padding(.bottom, 2.5)
            .padding(.horizontal, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.fill.tertiary)
            }
        #if canImport(UIKit)
            .offset(x: 0, y: -2)
            .font(.callout)
        #endif
    }
}

private struct DomainHeader: View {
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

            if !actioning {
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
        }
        .padding(.horizontal, titleInset)
    }
}

private struct DomainGrid: View {
    let section: Domain.Section
    @State private var filter = ""

    var body: some View {
        if section.domains.isPopulated {
            VStack(alignment: .leading) {
                DomainHeader(section: section, filter: $filter.animation())
                LazyVGrid(columns: gridColumns) {
                    ForEach(section.domains.filter { $0.matchesFilter(filter) }) { domain in
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

private struct SearchResults: View {
    let results: Search.Engine.State
    let filter: String

    var body: some View {
        switch results {
        case .noResults, .noSearch, .searching:
            ProgressView()
                .padding()

        case let .results(mode, items), let .updating(mode, items):
            switch mode {
            case .all:
                LazyVGrid(columns: gridColumns) {
                    let filtered = filter.isEmpty ? items : items.filter { $0.matchesFilter(filter) }
                    ForEach(filtered) {
                        ResultRow(result: $0)
                    }
                }
            case .limited, .top:
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(items) {
                            ResultRow(result: $0)
                                .frame(width: 320)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }
}

private struct SearchSection: View {
    private let searcher: Search.Engine
    private let title: String
    private let ctaTitle: String?
    private let showProgress: Bool
    private let prefersLargeView: Bool
    private let showResults: Bool
    private let showFilter: Bool

    @State private var filter = ""

    @MainActor
    init(searcher: Search.Engine) {
        self.searcher = searcher

        switch searcher.resultState {
        case .noSearch:
            title = "Search"
            showProgress = false
            ctaTitle = nil
            prefersLargeView = false
            showResults = false
            showFilter = false

        case .searching:
            title = "Searching"
            showProgress = true
            ctaTitle = nil
            prefersLargeView = false
            showResults = false
            showFilter = false

        case let .updating(resultType, _):
            title = "Searching"
            showProgress = true
            ctaTitle = nil

            switch resultType {
            case .all:
                prefersLargeView = false
            case .limited:
                prefersLargeView = false
            case .top:
                prefersLargeView = true
            }
            showResults = true
            showFilter = false

        case let .results(resultType, results):
            switch resultType {
            case .all:
                let c = results.count
                title = c > 1 ? " \(c) Results" : "1 Result"
                showProgress = false
                ctaTitle = "Top Results"
                prefersLargeView = false
                showResults = true
                showFilter = true
            case .limited:
                let c = results.count
                title = c > 1 ? " \(c) Results" : "1 Result"
                showProgress = false
                ctaTitle = nil
                prefersLargeView = false
                showResults = true
                showFilter = false
            case .top:
                title = "Top Results"
                showProgress = false
                ctaTitle = "Show More"
                prefersLargeView = true
                showResults = true
                showFilter = false
            }

        case .noResults:
            title = "No results found"
            showProgress = false
            ctaTitle = nil
            prefersLargeView = false
            showResults = false
            showFilter = false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: hspacing) {
                Text(title)
                    .font(.blooTitle)
                    .foregroundStyle(.secondary)

                Spacer()

                if showProgress {
                    ProgressView()
                        .frame(width: 20, height: 20)
                        .scaleEffect(CGSize(width: 0.8, height: 0.8))

                } else {
                    if showFilter {
                        FilterField(filter: $filter)
                    }

                    if let ctaTitle {
                        Button {
                            searcher.resetQuery(expandIfNeeded: prefersLargeView, collapseIfNeeded: !prefersLargeView)
                        } label: {
                            Text(ctaTitle)
                        }
                    }
                }
            }

            if showResults {
                SearchResults(results: searcher.resultState, filter: filter)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.fill.opacity(backgroundOpacity))
        .cornerRadius(wideCorner)
    }
}

struct StatusIcon: View {
    let name: String
    let color: Color

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            Color.background
            #if os(iOS)
                color.opacity(0.8)
            #else
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

private struct AdditionSection: View {
    let model: BlooCore

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
                    .submitLabel(.done)
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
                            await model.addDomain(first, postAddAction: .start)
                        } else {
                            for result in copy {
                                await model.addDomain(result, postAddAction: .none)
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
                        AdditionRow(text: $0)
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
                        String(text)
                    } else {
                        "https://\(String(text))"
                    }
                }.compactMap {
                    try? URL.create(from: $0, relativeTo: nil, checkExtension: true)
                }.filter {
                    let h = $0.host ?? ""
                    return h.isEmpty ? false : !model.contains(domain: h)
                }.map(\.absoluteString)
                withAnimation(.easeInOut(duration: 0.3)) {
                    results = Set(list).sorted()
                }
            }
        }
    }
}

private struct OverlayMessage: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
            VStack(spacing: 10) {
                Text(title)
                    .font(.title)
                Text(subtitle)
                    .font(.body)
            }
            .padding()
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .foregroundStyle(.windowBackground)
                    .shadow(radius: 4)
            }
        }
        .ignoresSafeArea()
    }
}

private struct ModelStateFeedback: View {
    let model: BlooCore

    var body: some View {
        if model.runState == .stopped {
            OverlayMessage(title: "One Moment…", subtitle: "This operation can take up to a minute")

        } else if model.runState == .backgrounded {
            OverlayMessage(title: "Suspended", subtitle: "This operation will resume when device has enough power and resources to resume it")
        }
    }
}

@MainActor
private struct Admin: View {
    private let model: BlooCore
    @Bindable private var searcher: Search.Engine

    @State private var searchFocused = false
    @FocusState private var additionFocused: Bool

    init(model: BlooCore, windowId: UUID) {
        self.model = model
        searcher = Search.Engine(windowId: windowId)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if model.showAddition {
                    AdditionSection(model: model)
                        .focused($additionFocused)
                }

                if case .noSearch = searcher.resultState {
                    EmptyView()
                } else {
                    SearchSection(searcher: searcher)
                }

                ForEach(model.domainSections) {
                    DomainGrid(section: $0)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .onChange(of: model.clearSearches) { _, _ in
            searcher.searchQuery = ""
        }
        .navigationTitle(searcher.title)
        .searchable(text: $searcher.searchQuery, isPresented: $searchFocused, prompt: "Search for keyword(s)")
        .toolbar {
            ToolbarItem {
                Button {
                    withAnimation {
                        if model.showAddition {
                            additionFocused = false
                            #if os(macOS)
                                searchFocused = true
                            #endif
                        }
                        model.showAddition.toggle()
                        if model.showAddition {
                            additionFocused = true
                            #if os(macOS)
                                searchFocused = false
                            #endif
                        }
                    }
                } label: {
                    Image(systemName: model.showAddition ? "arrow.down.and.line.horizontal.and.arrow.up" : "plus")
                }
            }
        }
    }
}

@MainActor
struct ContentView: View {
    @Environment(\.windowId) private var windowId

    private let model: BlooCore

    init(model: BlooCore) {
        self.model = model
    }

    var body: some View {
        NavigationStack {
            Admin(model: model, windowId: windowId)
            #if os(iOS)
                .background(Color.background)
                .scrollDismissesKeyboard(.immediately)
            #endif
        }
        .overlay {
            ModelStateFeedback(model: model)
        }
        #if os(iOS)
        .preferredColorScheme(.dark)
        #endif
    }
}
