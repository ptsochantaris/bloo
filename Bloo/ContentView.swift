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
                FooterText(text: url.absoluteString)

            case let .paused(indexed, pending, transitioning, _):
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    DomainTitle(domain: domain)
                    Spacer(minLength: 0)
                    if transitioning {
                        Text("Pausing")
                            .font(.blooBody)
                    } else {
                        if indexed > 0 || pending > 0 {
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
                }

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
                        await domain?.pause(resumable: false)
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

private struct ResultRow: View {
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
                            Color.clear.hidden()
                        @unknown default:
                            Color.clear.hidden()
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

private struct DomainHeader: View {
    let section: DomainSection
    @State private var actioning = false

    var body: some View {
        HStack(alignment: .top) {
            Text(section.state.title)
                .font(.blooTitle)
                .foregroundStyle(.secondary)

            if !actioning {
                Spacer(minLength: 0)

                if section.state.canStart {
                    Button {
                        actioning = true
                        Task {
                            await section.startAll()
                            actioning = false
                        }
                    } label: {
                        Text("Start All")
                    }
                } else if section.state.canStop {
                    Button {
                        actioning = true
                        Task {
                            await section.pauseAll(resumable: false)
                            actioning = false
                        }
                    } label: {
                        Text("Pause All")
                    }
                } else if section.state.canRestart {
                    Button {
                        actioning = true
                        Task {
                            await section.restartAll()
                            actioning = false
                        }
                    } label: {
                        Text("Re-Scan All")
                    }
                }
            }
        }
        .padding(.horizontal, titleInset)
    }
}

private struct DomainGrid: View {
    let section: DomainSection

    var body: some View {
        if section.domains.isPopulated {
            VStack(alignment: .leading) {
                DomainHeader(section: section)
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

private struct SearchResults: View {
    let results: ResultState

    var body: some View {
        switch results {
        case .noResults, .noSearch, .searching:
            ProgressView()
                .padding()

        case let .results(mode, items), let .updating(mode, items):
            switch mode {
            case .all:
                LazyVGrid(columns: gridColumns) {
                    ForEach(items) {
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
    private let searcher: Searcher
    private let title: String
    private let ctaTitle: String?
    private let showProgress: Bool
    private let prefersLargeView: Bool
    private let showResults: Bool

    @MainActor
    init(searcher: Searcher) {
        self.searcher = searcher

        switch searcher.resultState {
        case .noSearch:
            title = "Search"
            showProgress = false
            ctaTitle = nil
            prefersLargeView = false
            showResults = false

        case .searching:
            title = "Searching"
            showProgress = true
            ctaTitle = nil
            prefersLargeView = false
            showResults = false

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

        case let .results(resultType, results):
            switch resultType {
            case .all:
                let c = results.count
                title = c > 1 ? " \(c) Results" : "1 Result"
                showProgress = false
                ctaTitle = "Top Results"
                prefersLargeView = false
                showResults = true
            case .limited:
                let c = results.count
                title = c > 1 ? " \(c) Results" : "1 Result"
                showProgress = false
                ctaTitle = nil
                prefersLargeView = false
                showResults = true
            case .top:
                title = "Top Results"
                showProgress = false
                ctaTitle = "Show More"
                prefersLargeView = true
                showResults = true
            }

        case .noResults:
            title = "No results found"
            showProgress = false
            ctaTitle = nil
            prefersLargeView = false
            showResults = false
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

                } else if let ctaTitle {
                    Button {
                        searcher.resetQuery(expandIfNeeded: prefersLargeView, collapseIfNeeded: !prefersLargeView)
                    } label: {
                        Text(ctaTitle)
                    }
                }
            }

            if showResults {
                SearchResults(results: searcher.resultState)
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

private struct Admin: View {
    let model: BlooCore

    @State private var showAddition = false
    @State private var searchFocused = false
    @FocusState private var additionFocused: Bool
    @Bindable private var searcher: Searcher

    init(model: BlooCore, windowId: UUID) {
        self.model = model
        searcher = Searcher(windowId: windowId)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 18) {
                    if showAddition {
                        AdditionSection(model: model)
                            .focused($additionFocused)
                    }

                    if searcher.resultState.results != nil {
                        SearchSection(searcher: searcher)
                    }

                    ForEach(model.domainSections) {
                        DomainGrid(section: $0)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(searcher.title)
        .searchable(text: $searcher.searchQuery, isPresented: $searchFocused, prompt: "Search for keyword(s)")
        .toolbar {
            ToolbarItem {
                Button {
                    withAnimation {
                        if showAddition {
                            additionFocused = false
                            #if os(macOS)
                                searchFocused = true
                            #endif
                        }
                        showAddition.toggle()
                        if showAddition {
                            additionFocused = true
                            #if os(macOS)
                                searchFocused = false
                            #endif
                        }
                    }
                } label: {
                    Image(systemName: showAddition ? "arrow.down.and.line.horizontal.and.arrow.up" : "plus")
                }
            }
        }
        #if os(macOS)
        .task {
            await Task.yield()
            searchFocused = true
        }
        #endif
    }
}

struct ContentView: View {
    let model: BlooCore
    let windowId: UUID
    @Environment(\.openURL) private var openURL

    var body: some View {
        #if os(macOS)
            NavigationStack {
                Admin(model: model, windowId: windowId)
            }
            .overlay {
                ModelStateFeedback(model: model)
            }
        #elseif os(iOS)
            NavigationStack {
                Admin(model: model, windowId: windowId)
                    .background(Color.background)
                    .scrollDismissesKeyboard(.immediately)
            }
            .overlay {
                ModelStateFeedback(model: model)
            }
            .preferredColorScheme(.dark)
            .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
                if let uid = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String, let url = URL(string: uid) {
                    openURL(url)
                }
            }
            .onContinueUserActivity(CSQueryContinuationActionType) { userActivity in
                if let searchString = userActivity.userInfo?[CSSearchQueryString] as? String {
                    BlooCore.shared.newWindowWithSearch(searchString)
                }
            }
        #endif
    }
}
