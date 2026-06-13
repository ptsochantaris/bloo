import SwiftUI

struct LocalRulesEditor: View {
    let domain: Domain

    @Environment(\.dismiss) private var dismiss

    @State private var rows: [RuleRow] = []
    @State private var loaded = false
    @State private var validationError: String?

    var body: some View {
        #if os(iOS)
            NavigationStack {
                Group {
                    if loaded {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("These rules are appended to \(domain.id)'s own robots.txt and let you include or exclude specific paths. Changes apply the next time crawling starts.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.bottom, 8)

                                ruleRows
                            }
                            .padding()
                        }
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .navigationTitle("Crawling Rules")
                .navigationSubtitle(domain.id)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(!loaded)
                    }
                    ToolbarSpacer(placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            rows.append(RuleRow(directive: .disallow, value: ""))
                        } label: {
                            Label("Add Rule", systemImage: "plus")
                        }
                        .disabled(!loaded)
                    }
                }
                .alert("Incomplete Rules", isPresented: Binding { validationError != nil } set: { if !$0 { validationError = nil } }) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(validationError ?? "")
                }
            }
            .task { await load() }
        #else
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Crawling Rules")
                        .font(.title2)
                        .bold()
                    Text("These rules are appended to \(domain.id)'s own robots.txt and let you include or exclude specific paths. Changes apply the next time crawling starts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if loaded {
                    ScrollView {
                        VStack(spacing: 8) {
                            ruleRows
                        }
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack {
                    Button {
                        rows.append(RuleRow(directive: .disallow, value: ""))
                    } label: {
                        Label("Add Rule", systemImage: "plus")
                    }
                    .disabled(!loaded)

                    if let validationError {
                        Text(validationError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!loaded)
                }
            }
            .padding()
            .frame(minWidth: 460, minHeight: 360)
            .task { await load() }
        #endif
    }

    @ViewBuilder
    private var ruleRows: some View {
        ForEach($rows) { $row in
            HStack(spacing: 8) {
                Picker("", selection: $row.directive) {
                    ForEach(RobotDirective.allCases) { directive in
                        Text(directive.rawValue).tag(directive)
                    }
                }
                .labelsHidden()
                .frame(width: 150)

                TextField(row.directive.placeholder, text: $row.value)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: row.value) { validationError = nil }

                Button {
                    rows.removeAll { $0.id == row.id }
                    validationError = nil
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete this rule")
            }
        }
    }

    private func load() async {
        let existing = await domain.crawler.localRobotText
        let parsed = RuleRow.parse(from: existing)
        rows = parsed.isPopulated ? parsed : [RuleRow(directive: .disallow, value: "")]
        loaded = true
    }

    private func save() {
        for row in rows {
            let trimmed = row.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                validationError = "Please fill in every value before saving."
                return
            }
            if row.directive == .crawlDelay, Int(trimmed) == nil {
                validationError = "Crawl-delay must be a whole number of seconds."
                return
            }
        }

        let text = RuleRow.serialize(rows)
        let domain = domain
        Task {
            await domain.crawler.updateLocalRobotText(text)
        }
        dismiss()
    }
}

enum RobotDirective: String, CaseIterable, Identifiable, Hashable {
    case allow = "Allow"
    case disallow = "Disallow"
    case crawlDelay = "Crawl-delay"
    case sitemap = "Sitemap"
    case host = "Host"

    var id: String {
        rawValue
    }

    /// User-agent is intentionally absent: the local file always belongs to one fixed agent, so its
    /// header is written automatically on save and never exposed as an editable row.
    init?(field: String) {
        switch field.trimmingCharacters(in: .whitespaces).lowercased() {
        case "allow": self = .allow
        case "disallow": self = .disallow
        case "crawl-delay": self = .crawlDelay
        case "sitemap": self = .sitemap
        case "host": self = .host
        default: return nil
        }
    }

    var placeholder: String {
        switch self {
        case .allow, .disallow: "/path"
        case .crawlDelay: "seconds"
        case .sitemap: "https://example.com/sitemap.xml"
        case .host: "example.com"
        }
    }
}

struct RuleRow: Identifiable {
    let id = UUID()
    var directive: RobotDirective
    var value: String

    static func parse(from text: String?) -> [RuleRow] {
        guard let text else { return [] }
        var result: [RuleRow] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            guard let colon = line.firstIndex(of: ":") else {
                continue
            }
            let field = String(line[line.startIndex ..< colon])
            guard let directive = RobotDirective(field: field) else {
                continue
            }
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            result.append(RuleRow(directive: directive, value: value))
        }
        return result
    }

    static func serialize(_ rows: [RuleRow]) -> String {
        let header = "User-agent: \(Crawler.localAgentName)"
        let lines = rows.map { "\($0.directive.rawValue): \($0.value.trimmingCharacters(in: .whitespaces))" }
        return ([header] + lines).joined(separator: "\n")
    }
}
