import SwiftUI

/// An App Store Connect app, managed through the asc CLI: a gradient hero, then tabs for the release status, the
/// store text per language, builds, TestFlight, customer reviews, in-app purchases and subscriptions, and every other
/// asc command. Reads run with `--read-only`; every change is confirmed first and shows the command it runs.
struct AppOverviewView: View {
    @Environment(AppModel.self) private var model
    var app: ASCApp
    @State private var tab: Tab = .status
    /// The version being prepared (else the newest), filled into the forms that take `--version-id`.
    @State private var versionID: String?

    enum Tab: String, CaseIterable, Identifiable {
        case status, metadata, visuals, builds, testflight, reviews, money, analytics, more
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .status: return "gauge.with.dots.needle.67percent"
            case .metadata: return "text.alignleft"
            case .builds: return "shippingbox.fill"
            case .testflight: return "airplane"
            case .reviews: return "star.bubble.fill"
            case .money: return "creditcard.fill"
            case .visuals: return "photo.fill.on.rectangle.fill"
            case .analytics: return "chart.xyaxis.line"
            case .more: return "square.grid.2x2.fill"
            }
        }
        /// The asc command groups shown at the bottom of this tab.
        var groups: [String] {
            switch self {
            case .status: return AscAreas.release
            case .metadata: return AscAreas.listing
            case .visuals: return AscAreas.visuals
            case .builds: return AscAreas.builds
            case .testflight: return AscAreas.testflight
            case .reviews: return AscAreas.reviews
            case .money: return AscAreas.money
            case .analytics: return AscAreas.analytics
            case .more: return AscAreas.more
            }
        }
        var colors: [Color] {
            switch self {
            case .status: return BadgeColors.brand
            case .metadata: return BadgeColors.magic
            case .builds: return BadgeColors.deep
            case .testflight: return BadgeColors.cool
            case .reviews: return BadgeColors.warm
            case .money: return BadgeColors.fresh
            case .visuals: return BadgeColors.warm
            case .analytics: return BadgeColors.deep
            case .more: return BadgeColors.gray
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                hero
                TabStrip(selection: $tab)
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)
            Divider().opacity(0.5)
            Group {
                if !model.connection.isConnected {
                    ConnectHint().padding(24)
                } else {
                    switch tab {
                    case .status: AscStatusTab(app: app)
                    case .metadata: AscMetadataTab(app: app)
                    case .builds: AscBuildsTab(app: app)
                    case .testflight: AscTestFlightTab(app: app)
                    case .reviews: AscReviewsTab(app: app)
                    case .money: AscMoneyTab(app: app)
                    case .visuals: AscVisualsTab(app: app)
                    case .analytics: AscAnalyticsTab(app: app)
                    case .more: TabPage { EmptyView() }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.ascShelf, AscShelfContext(title: L.t("asc.shelf.title"), groups: tab.groups, prefill: ["app": app.id, "version-id": versionID ?? "", "app-id": app.id]))
            .id("\(app.id)-\(tab.rawValue)")
        }
        .task(id: app.id) {
            let editable: Set<String> = ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"]
            if let doc = try? await AscCLI.json(["versions", "list", "--app", app.id, "--limit", "10"]) {
                let vs = JSONAPI.items(doc)
                versionID = (vs.first { editable.contains(JSONAPI.text($0, "appVersionState")) } ?? vs.first)?["id"]?.stringValue
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app.overview")
    }

    private var hero: some View {
        HStack(spacing: 16) {
            AppIcon(app: app, size: 64).shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(app.name).font(.title.bold()).lineLimit(1).minimumScaleFactor(0.7)
                Text(app.bundleId).font(.callout.monospaced()).opacity(0.85).textSelection(.enabled).lineLimit(1)
                FlowLayout(spacing: 6) {
                    ForEach(app.versions) { v in StatusPill(text: Text("\(ASCWords.platform(v.platform)) \(v.version) · \(ASCWords.state(v.state))"), color: ASCWords.tone(v.state).color, onGradient: true) }
                    if let p = model.linkedProject(for: app) { StatusPill(text: Text(L.t("apps.linked").replacingOccurrences(of: "{project}", with: p.name)), color: .white, onGradient: true) }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                Button { NSWorkspace.shared.open(app.ascURL) } label: { Label(L.t("apps.openASC"), systemImage: "arrow.up.right.square") }
                if let p = model.linkedProject(for: app) {
                    Button { Task { await model.open(p) } } label: { Label(L.t("apps.openProject"), systemImage: "folder") }
                } else {
                    Button { model.pickProjectFolder() } label: { Label(L.t("apps.linkProject"), systemImage: "link.badge.plus") }
                        .accessibilityIdentifier("app.linkProject")
                }
            }
            .buttonStyle(.bordered).tint(.white).controlSize(.small)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Capsule tabs that scroll sideways when the window is narrow, instead of a segmented control that overflows.
private struct TabStrip: View {
    @Binding var selection: AppOverviewView.Tab
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(AppOverviewView.Tab.allCases) { t in
                    Button { selection = t } label: {
                        HStack(spacing: 6) {
                            IconBadge(symbol: t.symbol, colors: t.colors, size: 18)
                            Text(L.t("asc.tab.\(t.rawValue)")).font(.callout.weight(selection == t ? .semibold : .regular)).lineLimit(1)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(selection == t ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.clear), in: Capsule())
                        .overlay { if selection == t { Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 0.5) } }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("app.tab.\(t.rawValue)")
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Not connected: how to connect (Vitrin's key or asc's own login), without forcing either.
struct ConnectHint: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol: "key.horizontal.fill", colors: BadgeColors.cool, size: 32)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.connection.state == .missingCLI ? L.t("asc.missing") : L.t("asc.connect.title")).font(.headline)
                Text(L.t("asc.connect.detail")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.connection.state == .missingCLI { CopyCode(text: AscCLI.installHint) }
                HStack {
                    SettingsLink { Text(L.t("account.add")) }.buttonStyle(GradientButtonStyle(fullWidth: false))
                    Button(L.t("onb.tools.again")) { Task { await model.refreshApps() } }
                }
            }
        }
        .glassCard(padding: 16)
        .frame(maxWidth: 720, alignment: .leading)
    }
}

// MARK: shared loading

/// Loads one asc JSON result for a tab and shows a spinner, the error, or the content.
struct AscLoad<Content: View>: View {
    var args: [String]
    /// Bump to read again from outside (another list on the page changed).
    var refresh = 0
    /// Shown instead of asc's message when the read fails (a public lookup for an app not on the App Store yet).
    var errorText: String? = nil
    @ViewBuilder var content: (JSONValue, @escaping () -> Void) -> Content
    @State private var value: JSONValue?
    @State private var error: String?
    @State private var loading = false
    @State private var tick = 0

    var body: some View {
        Group {
            if let value {
                content(value) { tick += 1 }
            } else if let error {
                Label(errorText ?? error, systemImage: errorText == nil ? "exclamationmark.triangle.fill" : "info.circle").foregroundStyle(errorText == nil ? .orange : .secondary).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .glassCard(padding: 14)
            } else {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L.t("asc.loading")).foregroundStyle(.secondary) }
                    .padding(.vertical, 20)
            }
        }
        .task(id: "\(args.joined(separator: " "))#\(tick)#\(refresh)") {
            loading = true
            defer { loading = false }
            do { value = try await AscCLI.json(args); error = nil } catch { self.error = error.localizedDescription }
        }
    }
}

/// JSON:API helpers: the `data` array, a resource's attributes, a value as text.
enum JSONAPI {
    static func items(_ doc: JSONValue) -> [[String: JSONValue]] {
        let d = doc.objectValue?["data"] ?? doc
        return (d.arrayValue ?? (d.objectValue.map { [JSONValue.object($0)] } ?? [])).compactMap(\.objectValue)
    }
    static func attr(_ item: [String: JSONValue], _ key: String) -> JSONValue? { item["attributes"]?.objectValue?[key] }
    static func text(_ item: [String: JSONValue], _ key: String) -> String {
        guard let v = attr(item, key) else { return "" }
        if case .null = v { return "" }
        return v.display
    }
    /// ISO dates as the user's short date and time.
    static func date(_ s: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = f.date(from: s) ?? { f.formatOptions = [.withInternetDateTime]; return f.date(from: s) }()
        return d.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? s
    }
}

/// A column table for a list of resources: each column a title and an attribute key.
struct ResourceTable: View {
    var items: [[String: JSONValue]]
    var columns: [(title: String, key: String, kind: Kind)]
    enum Kind { case text, mono, date, state, bool }
    var empty: String

    var body: some View {
        if items.isEmpty {
            Text(empty).foregroundStyle(.secondary).font(.callout).glassCard(padding: 14)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 12) { ForEach(columns.indices, id: \.self) { i in Text(columns[i].title).frame(maxWidth: .infinity, alignment: .leading) } }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                Divider()
                ForEach(items.indices, id: \.self) { r in
                    HStack(spacing: 12) {
                        ForEach(columns.indices, id: \.self) { i in cell(items[r], columns[i]).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                    .font(.callout)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    if r < items.count - 1 { Divider().opacity(0.5) }
                }
            }
            .glassCard(padding: 4)
        }
    }

    /// Every value in words (`AscText`): a `.mono` column stays monospaced only for codes that have no words.
    @ViewBuilder private func cell(_ item: [String: JSONValue], _ c: (title: String, key: String, kind: Kind)) -> some View {
        let raw = c.key == "id" ? item["id"] : JSONAPI.attr(item, c.key)
        let t = raw.map { AscText.plain(c.key, $0) } ?? ""
        switch c.kind {
        case .text: Text(t.isEmpty ? "—" : t).lineLimit(2).textSelection(.enabled)
        case .mono: Text(t.isEmpty ? "—" : t).font(t == raw?.stringValue ? .callout.monospaced() : .callout).lineLimit(1).textSelection(.enabled)
        case .date: Text(t.isEmpty ? "—" : t).lineLimit(1)
        case .state:
            if let s = raw?.stringValue, !s.isEmpty { Pill(ASCWords.state(s), ASCWords.tone(s)).lineLimit(1) } else { Text("—") }
        case .bool: Image(systemName: raw?.boolValue == true ? "checkmark.circle.fill" : "circle").foregroundStyle(raw?.boolValue == true ? .green : .secondary)
        }
    }
}

/// A scrolling tab body with the family padding.
struct AscShelfContext {
    var title = ""
    var groups: [String] = []
    var prefill: [String: String] = [:]
}
extension EnvironmentValues {
    @Entry var ascShelf = AscShelfContext()
}

struct TabPage<Content: View>: View {
    @Environment(\.ascShelf) private var shelf
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
                // The rest of asc for this place: every command of the tab's groups, as forms.
                if !shelf.groups.isEmpty { AscCommandShelf(title: shelf.title, groups: shelf.groups, prefill: shelf.prefill).padding(.top, 8) }
            }
                .padding(24)
                .frame(maxWidth: 1000, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: status

private struct AscStatusTab: View {
    var app: ASCApp
    var body: some View {
        TabPage {
            AscLoad(args: ["status", "--app", app.id]) { doc, reload in
                let o = doc.objectValue ?? [:]
                let summary = o["summary"]?.objectValue ?? [:]
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        let health = summary["health"]?.stringValue ?? ""
                        IconBadge(symbol: health == "green" ? "checkmark" : health == "red" ? "exclamationmark" : "hourglass", colors: health == "green" ? BadgeColors.fresh : health == "red" ? BadgeColors.alert : BadgeColors.warm, size: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            SectionTitle(L.t("asc.status.next"))
                            Text(summary["nextAction"]?.stringValue ?? "—").font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            ForEach(Array((summary["blockers"]?.arrayValue ?? []).enumerated()), id: \.offset) { _, b in
                                Label(b.objectValue?["message"]?.stringValue ?? b.display, systemImage: "exclamationmark.octagon.fill").foregroundStyle(.red).font(.callout)
                            }
                        }
                        Spacer()
                        Button { reload() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help(L.t("common.refresh"))
                    }
                    .glassCard(padding: 16)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                        statusCard(L.t("asc.status.appstore"), "storefront.fill", BadgeColors.brand, o["appstore"], [("version", "version"), ("state", "state"), ("platform", "platform"), ("createdDate", "date")])
                        statusCard(L.t("asc.status.review"), "checkmark.seal.fill", BadgeColors.fresh, o["review"], [("state", "state"), ("submittedDate", "date"), ("platform", "platform")])
                        statusCard(L.t("asc.status.build"), "shippingbox.fill", BadgeColors.deep, o["builds"]?.objectValue?["latest"], [("version", "version"), ("buildNumber", "build"), ("processingState", "state"), ("uploadedDate", "date")])
                        statusCard("TestFlight", "airplane", BadgeColors.cool, o["testflight"], [("internalBuildState", "state"), ("externalBuildState", "state")])
                        statusCard(L.t("asc.status.phased"), "chart.bar.fill", BadgeColors.warm, o["phasedRelease"], [("configured", "bool"), ("state", "state")])
                    }
                    ReleaseActions(app: app, status: o, reload: reload)
                    ReviewReadiness(appID: app.id)
                    if let v = o["appstore"]?.objectValue?["versionId"]?.stringValue { ReviewContactCard(versionID: v) }
                    SubmissionHistory(appID: app.id)
                    VersionHistory(appID: app.id)
                }
            }
        }
    }

    @ViewBuilder private func statusCard(_ title: String, _ symbol: String, _ colors: [Color], _ value: JSONValue?, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) { IconBadge(symbol: symbol, colors: colors, size: 24); Text(title).font(.headline) }
            if let o = value?.objectValue {
                ForEach(rows, id: \.0) { key, kind in
                    if let v = o[key], v != .null {
                        HStack {
                            Text(L.t("asc.field.\(key)")).foregroundStyle(.secondary)
                            Spacer()
                            switch kind {
                            case "state": Pill(ASCWords.state(v.display), ASCWords.tone(v.display))
                            case "date": Text(JSONAPI.date(v.display))
                            case "bool": Text(v.boolValue == true ? L.t("common.yes") : L.t("common.no"))
                            default: Text(v.display).monospacedDigit()
                            }
                        }
                        .font(.callout)
                    }
                }
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .glassCard(padding: 14)
    }
}

// MARK: metadata

private struct AscMetadataTab: View {
    var app: ASCApp
    @State private var versionID: String?

    var body: some View {
        TabPage {
            AscLoad(args: ["versions", "list", "--app", app.id, "--limit", "20"]) { doc, _ in
                let versions = JSONAPI.items(doc)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        SectionTitle(L.t("asc.meta.version"))
                        Picker("", selection: Binding(get: { versionID ?? versions.first?["id"]?.stringValue ?? "" }, set: { versionID = $0 })) {
                            ForEach(versions.indices, id: \.self) { i in
                                let v = versions[i]
                                Text("\(ASCWords.platform(JSONAPI.text(v, "platform"))) \(JSONAPI.text(v, "versionString")) · \(ASCWords.state(JSONAPI.text(v, "appVersionState")))").tag(v["id"]?.stringValue ?? "")
                            }
                        }
                        .labelsHidden().frame(maxWidth: 360)
                        Spacer()
                    }
                    if let id = versionID ?? versions.first?["id"]?.stringValue {
                        let state = JSONAPI.text(versions.first { $0["id"]?.stringValue == id } ?? [:], "appVersionState")
                        LocalizationEditor(versionID: id, editable: ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"].contains(state), primaryLocale: app.primaryLocale)
                            .id(id)
                    } else {
                        Text(L.t("apps.noVersions")).foregroundStyle(.secondary)
                    }
                    SectionTitle(L.t("asc.meta.appInfo"))
                    AppInfoEditor(appID: app.id)
                    StoreSettings(appID: app.id)
                }
            }
        }
    }
}

/// The version's localizations: the locales on the left, the fields of the chosen one on the right, with the App
/// Store Connect limits; Save sends only the fields that changed (`asc localizations update --id … --confirm`).
private struct LocalizationEditor: View {
    var versionID: String
    var editable: Bool
    var primaryLocale = ""
    @State private var locale: String?
    @State private var drafts: [String: [String: String]] = [:]
    @State private var saving = false
    @State private var message: (String, Bool)?
    @State private var confirm = false

    static let fields: [(key: String, flag: String, limit: Int, multiline: Bool)] = [
        ("promotionalText", "promotional-text", 170, true), ("description", "description", 4000, true),
        ("keywords", "keywords", 100, false), ("whatsNew", "whats-new", 4000, true),
        ("supportUrl", "support-url", 0, false), ("marketingUrl", "marketing-url", 0, false),
    ]

    var body: some View {
        AscLoad(args: ["localizations", "list", "--version", versionID, "--paginate"]) { doc, reload in
            let items = JSONAPI.items(doc).sorted { JSONAPI.text($0, "locale") < JSONAPI.text($1, "locale") }
            let current = locale ?? items.first { JSONAPI.text($0, "locale") == primaryLocale }.map { JSONAPI.text($0, "locale") } ?? items.first.map { JSONAPI.text($0, "locale") }
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items.indices, id: \.self) { i in
                        let l = JSONAPI.text(items[i], "locale")
                        Button { locale = l } label: {
                            HStack {
                                Text(AscText.language(l)).font(.callout).lineLimit(1)
                                Spacer()
                                if drafts[items[i]["id"]?.stringValue ?? ""]?.isEmpty == false { Circle().fill(Color.accentColor).frame(width: 6, height: 6) }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(current == l ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .glassCard(padding: 6)
                .frame(width: 220)
                if let item = items.first(where: { JSONAPI.text($0, "locale") == current }), let id = item["id"]?.stringValue {
                    VStack(alignment: .leading, spacing: 12) {
                        if !editable { Label(L.t("asc.meta.locked"), systemImage: "lock.fill").font(.callout).foregroundStyle(.secondary) }
                        ForEach(Self.fields, id: \.key) { f in
                            field(id: id, item: item, f)
                        }
                        if let (m, ok) = message { Label(m, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(ok ? .green : .red).font(.callout) }
                        HStack {
                            Spacer()
                            if drafts[id]?.isEmpty == false { Button(L.t("common.cancel")) { drafts[id] = nil } }
                            Button { confirm = true } label: { Label(L.t("asc.meta.save"), systemImage: "arrow.up.circle") }
                                .buttonStyle(GradientButtonStyle(fullWidth: false))
                                .disabled(saving || drafts[id]?.isEmpty != false)
                        }
                        .confirmationDialog(L.t("asc.meta.saveConfirm"), isPresented: $confirm, titleVisibility: .visible) {
                            Button(L.t("asc.meta.save")) { Task { await save(id: id, reload: reload) } }
                            Button(L.t("common.cancel"), role: .cancel) {}
                        } message: {
                            Text((drafts[id] ?? [:]).keys.sorted().map { L.t("asc.field.\($0)") }.joined(separator: ", ") + " · \(AscText.language(current ?? ""))")
                        }
                    }
                    .glassCard(padding: 16)
                }
            }
        }
    }

    @ViewBuilder private func field(id: String, item: [String: JSONValue], _ f: (key: String, flag: String, limit: Int, multiline: Bool)) -> some View {
        let original = JSONAPI.text(item, f.key)
        let binding = Binding<String>(
            get: { drafts[id]?[f.key] ?? original },
            set: { v in
                var d = drafts[id] ?? [:]
                if v == original { d[f.key] = nil } else { d[f.key] = v }
                drafts[id] = d
            })
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L.t("asc.field.\(f.key)")).font(.callout.weight(.medium))
                Spacer()
                if f.limit > 0 {
                    let n = binding.wrappedValue.count
                    Text("\(n)/\(f.limit)").font(.caption.monospacedDigit()).foregroundStyle(n > f.limit ? .red : .secondary)
                }
            }
            if f.multiline {
                TextEditor(text: binding).font(.callout).frame(minHeight: f.limit > 1000 ? 140 : 54).scrollContentBackground(.hidden)
                    .padding(6).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8)).disabled(!editable && f.key != "promotionalText")
            } else {
                TextField("", text: binding).textFieldStyle(.roundedBorder).disabled(!editable)
            }
        }
    }

    private func save(id: String, reload: @escaping () -> Void) async {
        guard let d = drafts[id], !d.isEmpty else { return }
        saving = true
        defer { saving = false }
        var args = ["localizations", "update", "--id", id]
        for f in Self.fields { if let v = d[f.key] { args += ["--\(f.flag)", v] } }
        do {
            let r = try await AscCLI.run(args + ["--output", "json"], readOnly: false)
            if r.ok { drafts[id] = nil; message = (L.t("asc.saved"), true); reload() } else { message = (r.errorLine, false) }
        } catch { message = (error.localizedDescription, false) }
    }
}

/// Name, subtitle and privacy URLs per language (`--type app-info`).
private struct AppInfoEditor: View {
    var appID: String
    var body: some View {
        AscLoad(args: ["localizations", "list", "--app", appID, "--type", "app-info", "--paginate"]) { doc, reload in
            let items = JSONAPI.items(doc).sorted { JSONAPI.text($0, "locale") < JSONAPI.text($1, "locale") }
            VStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { i in
                    let it = items[i]
                    let locale = JSONAPI.text(it, "locale")
                    HStack(spacing: 12) {
                        Text(AscText.language(locale)).font(.callout).lineLimit(1).frame(width: 170, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(JSONAPI.text(it, "name")).font(.callout.weight(.medium)).lineLimit(1)
                            Text(JSONAPI.text(it, "subtitle")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        AscActionButton(action: AscActions.appInfoText(app: appID, locale: locale, name: JSONAPI.text(it, "name"), subtitle: JSONAPI.text(it, "subtitle")), done: reload)
                            .controlSize(.small).labelStyle(.iconOnly)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    if i < items.count - 1 { Divider().opacity(0.5) }
                }
                if items.isEmpty { Text(L.t("asc.empty")).foregroundStyle(.secondary).padding(12) }
            }
            .glassCard(padding: 4)
        }
    }
}

// MARK: builds, TestFlight, reviews, money

private struct AscBuildsTab: View {
    var app: ASCApp
    var body: some View {
        TabPage {
            AscLoad(args: ["builds", "list", "--app", app.id, "--limit", "50", "--sort", "-uploadedDate"]) { doc, reload in
                let builds = AscActions.options(doc) { b in "\(JSONAPI.text(b, "version")) · \(ASCWords.state(JSONAPI.text(b, "processingState"))) · \(JSONAPI.date(JSONAPI.text(b, "uploadedDate")))" }
                AscLoad(args: ["testflight", "groups", "list", "--app", app.id]) { gdoc, _ in
                    let groups = AscActions.options(gdoc) { JSONAPI.text($0, "name") }
                    ActionBar(title: L.t("act.section.builds")) {
                        AscActionButton(action: AscActions.addBuildToGroups(builds: builds, groups: groups), done: reload)
                        AscActionButton(action: AscActions.testNotes(builds: builds), done: reload)
                        AscActionButton(action: AscActions.expireBuild(builds: builds), done: reload)
                    }
                }
                ResourceTable(items: JSONAPI.items(doc), columns: [
                    (L.t("asc.field.build"), "version", .mono), (L.t("asc.field.processingState"), "processingState", .state),
                    (L.t("asc.field.uploadedDate"), "uploadedDate", .date), (L.t("asc.field.minOsVersion"), "minOsVersion", .mono), (L.t("asc.field.expired"), "expired", .bool),
                ], empty: L.t("asc.empty"))
            }
        }
    }
}

private struct AscTestFlightTab: View {
    var app: ASCApp
    @State private var tick = 0
    var body: some View {
        TabPage {
            AscLoad(args: ["testflight", "groups", "list", "--app", app.id]) { doc, reload in
                let groups = AscActions.options(doc) { JSONAPI.text($0, "name") }
                ActionBar(title: L.t("act.section.testflight")) {
                    AscActionButton(action: AscActions.inviteTester(app: app.id, groups: groups), done: { reload(); tick += 1 }, prominent: true)
                    AscActionButton(action: AscActions.createGroup(app: app.id), done: reload)
                    AscActionButton(action: AscActions.removeTester(app: app.id), done: { tick += 1 })
                    if !groups.isEmpty { AscActionButton(action: AscActions.deleteGroup(groups: groups), done: reload) }
                }
                SectionTitle(L.t("asc.tf.groups"))
                ResourceTable(items: JSONAPI.items(doc), columns: [
                    (L.t("asc.field.name"), "name", .text), (L.t("asc.field.isInternalGroup"), "isInternalGroup", .bool),
                    (L.t("asc.field.publicLinkEnabled"), "publicLinkEnabled", .bool), (L.t("asc.field.createdDate"), "createdDate", .date),
                ], empty: L.t("asc.empty"))
            }
            SectionTitle(L.t("asc.tf.testers"))
            AscLoad(args: ["testflight", "testers", "list", "--app", app.id, "--limit", "200"], refresh: tick) { doc, _ in
                ResourceTable(items: JSONAPI.items(doc), columns: [
                    (L.t("asc.field.firstName"), "firstName", .text), (L.t("asc.field.lastName"), "lastName", .text),
                    (L.t("asc.field.email"), "email", .mono), (L.t("asc.field.state"), "state", .state),
                ], empty: L.t("asc.empty"))
            }
        }
    }
}

private struct AscReviewsTab: View {
    var app: ASCApp
    @State private var replyTo: [String: JSONValue]?
    @State private var onlyUnanswered = false
    @State private var stars = ""
    var body: some View {
        TabPage {
            AscLoad(args: ["reviews", "ratings", "--app", app.id, "--all"], errorText: L.t("act.ratingsNone")) { doc, _ in
                RatingsCard(doc: doc)
            }
            HStack(spacing: 12) {
                Toggle(L.t("act.onlyUnanswered"), isOn: $onlyUnanswered).toggleStyle(.switch).controlSize(.small)
                Picker(L.t("act.stars"), selection: $stars) {
                    Text(L.t("act.allStars")).tag("")
                    ForEach((1...5).reversed(), id: \.self) { n in Text(String(repeating: "★", count: n)).tag(String(n)) }
                }
                .fixedSize()
                Spacer()
            }
            AscLoad(args: ["reviews", "list", "--app", app.id, "--limit", "100", "--sort", "-createdDate"] + (onlyUnanswered ? ["--only-unresponded"] : []) + (stars.isEmpty ? [] : ["--stars", stars])) { doc, reload in
                let items = JSONAPI.items(doc)
                if items.isEmpty { Text(L.t("asc.reviews.none")).foregroundStyle(.secondary).glassCard(padding: 14) }
                ForEach(items.indices, id: \.self) { i in
                    let r = items[i]
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(String(repeating: "★", count: Int(JSONAPI.attr(r, "rating")?.numberValue ?? 0)) + String(repeating: "☆", count: 5 - Int(JSONAPI.attr(r, "rating")?.numberValue ?? 0))).foregroundStyle(.orange)
                            Text(JSONAPI.text(r, "title")).font(.headline)
                            Spacer()
                            Text("\(JSONAPI.text(r, "reviewerNickname")) · \(JSONAPI.text(r, "territory")) · \(JSONAPI.date(JSONAPI.text(r, "createdDate")))").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(JSONAPI.text(r, "body")).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Button { replyTo = r } label: { Label(L.t("asc.reviews.reply"), systemImage: "arrowshape.turn.up.left") }.controlSize(.small)
                    }
                    .glassCard(padding: 14)
                }
                Color.clear.frame(height: 0).sheet(item: Binding(get: { replyTo.map { ReplyTarget(item: $0) } }, set: { replyTo = $0?.item })) { t in
                    ReplySheet(review: t.item) { replyTo = nil; reload() }
                }
            }
        }
    }
    struct ReplyTarget: Identifiable { var item: [String: JSONValue]; var id: String { item["id"]?.stringValue ?? "" } }
}

private struct ReplySheet: View {
    var review: [String: JSONValue]
    var done: () -> Void
    @State private var text = ""
    @State private var error: String?
    @State private var sending = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("asc.reviews.reply")).font(.title3.bold())
            Text(JSONAPI.text(review, "body")).font(.callout).foregroundStyle(.secondary).lineLimit(6)
            TextEditor(text: $text).font(.callout).frame(minHeight: 120).padding(6).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            Text(L.t("asc.reviews.public")).font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button(L.t("common.cancel")) { done() }.keyboardShortcut(.cancelAction)
                Button(L.t("asc.reviews.send")) { Task { await send() } }.buttonStyle(GradientButtonStyle(fullWidth: false)).disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20).frame(width: 520)
    }
    private func send() async {
        guard let id = review["id"]?.stringValue else { return }
        sending = true
        defer { sending = false }
        do {
            let r = try await AscCLI.run(["reviews", "respond", "--review-id", id, "--response", text.trimmingCharacters(in: .whitespacesAndNewlines), "--output", "json"], readOnly: false)
            if r.ok { done() } else { error = r.errorLine }
        } catch { self.error = error.localizedDescription }
    }
}

private struct AscMoneyTab: View {
    var app: ASCApp
    var body: some View {
        TabPage {
            AscLoad(args: ["pricing", "current", "--app", app.id]) { doc, _ in
                let o = doc.objectValue ?? [:]
                HStack(spacing: 14) {
                    IconBadge(symbol: "dollarsign", colors: BadgeColors.fresh, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        SectionTitle(L.t("act.price"))
                        Text(o["isFree"]?.boolValue == true ? L.t("act.free") : "\(o["customerPrice"]?.display ?? "—") \(o["currency"]?.display ?? "")").font(.title2.bold())
                        Text("\(L.t("act.baseTerritory")): \(o["baseTerritory"]?.display ?? "—") · \(L.t("act.proceeds")): \(o["proceeds"]?.display ?? "—")").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .glassCard(padding: 14)
            }
            SectionTitle(L.t("asc.money.subscriptions"))
            AscLoad(args: ["subscriptions", "list", "--app", app.id, "--paginate"]) { doc, _ in
                ResourceTable(items: JSONAPI.items(doc), columns: [
                    (L.t("asc.field.name"), "name", .text), (L.t("asc.field.productId"), "productId", .mono),
                    (L.t("asc.field.subscriptionPeriod"), "subscriptionPeriod", .mono), (L.t("asc.field.state"), "state", .state),
                ], empty: L.t("asc.empty"))
            }
            SectionTitle(L.t("asc.money.iap"))
            AscLoad(args: ["iap", "list", "--app", app.id, "--paginate"]) { doc, _ in
                ResourceTable(items: JSONAPI.items(doc), columns: [
                    (L.t("asc.field.name"), "name", .text), (L.t("asc.field.productId"), "productId", .mono),
                    (L.t("asc.field.inAppPurchaseType"), "inAppPurchaseType", .mono), (L.t("asc.field.state"), "state", .state),
                ], empty: L.t("asc.empty"))
            }
            Text(L.t("asc.money.more")).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// What can be done with the release right now, from its state in `asc status`: a new version, the readiness check,
/// the build, the submission, its cancellation, the release, the phased rollout and the version's settings.
private struct ReleaseActions: View {
    var app: ASCApp
    var status: [String: JSONValue]
    var reload: () -> Void

    private var appstore: [String: JSONValue] { status["appstore"]?.objectValue ?? [:] }
    private var versionID: String? { appstore["versionId"]?.stringValue }
    private var state: String { appstore["state"]?.stringValue ?? "" }
    private var phased: [String: JSONValue] { status["phasedRelease"]?.objectValue ?? [:] }

    private static let editable: Set<String> = ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"]
    private static let inReview: Set<String> = ["WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_REVIEW"]
    private static let live: Set<String> = ["READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "REPLACED_WITH_NEW_VERSION", "PROCESSING_FOR_DISTRIBUTION"]

    var body: some View {
        ActionBar(title: L.t("act.section.release")) {
            if versionID == nil || Self.live.contains(state) {
                AscActionButton(action: AscActions.createVersion(app: app.id), done: reload, prominent: true)
            }
            if let v = versionID {
                if Self.editable.contains(state) {
                    AscActionButton(action: AscActions.submit(app: app.id, versionID: v), done: reload, prominent: true)
                    AscActionButton(action: AscActions.attachBuild(versionID: v, app: app.id), done: reload)
                    AscActionButton(action: AscActions.updateVersion(versionID: v), done: reload)
                }
                if Self.inReview.contains(state) {
                    AscActionButton(action: AscActions.cancelSubmission(app: app.id, versionID: v), done: reload)
                }
                if state == "PENDING_DEVELOPER_RELEASE" {
                    AscActionButton(action: AscActions.release(versionID: v), done: reload, prominent: true)
                }
                if let pid = phased["id"]?.stringValue {
                    AscActionButton(action: AscActions.phasedUpdate(phasedID: pid), done: reload)
                } else if !Self.live.contains(state) {
                    AscActionButton(action: AscActions.phasedCreate(versionID: v), done: reload)
                }
            }
            AscActionButton(action: AscActions.validate(app: app.id, versionID: versionID), done: reload)
        }
    }
}

/// `asc reviews ratings --all`: the average and the count, overall and per country (the strongest first).
private struct RatingsCard: View {
    var doc: JSONValue
    var body: some View {
        let o = doc.objectValue ?? [:]
        let avg = o["averageRating"]?.numberValue ?? o["average"]?.numberValue ?? o["summary"]?.objectValue?["averageRating"]?.numberValue
        let count = o["totalCount"]?.numberValue ?? o["ratingCount"]?.numberValue
        HStack(alignment: .center, spacing: 16) {
            IconBadge(symbol: "star.fill", colors: BadgeColors.warm, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(avg.map { String(format: "%.2f", $0) } ?? "—").font(.largeTitle.bold().monospacedDigit())
                Text(count.map { L.t("act.ratingCount").replacingOccurrences(of: "{n}", with: String(Int($0))) } ?? L.t("asc.reviews.none")).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            let countries = (o["countries"]?.arrayValue ?? o["byCountry"]?.arrayValue ?? []).compactMap(\.objectValue)
                .sorted { ($0["ratingCount"]?.numberValue ?? 0) > ($1["ratingCount"]?.numberValue ?? 0) }.prefix(6)
            if !countries.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    ForEach(Array(countries.enumerated()), id: \.offset) { _, c in
                        Text("\((c["country"]?.stringValue ?? c["countryCode"]?.stringValue ?? "").uppercased()) · \(c["averageRating"]?.numberValue.map { String(format: "%.1f", $0) } ?? "—") · \(Int(c["ratingCount"]?.numberValue ?? 0))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .glassCard(padding: 16)
    }
}

/// What the store shows: the screenshots of the current version as images, then the other kinds of store media.
private struct AscVisualsTab: View {
    var app: ASCApp
    var body: some View {
        TabPage {
            ScreenshotGallery(app: app)
            AscSection(title: L.t("asc.visuals.pages"), args: ["product-pages", "custom-pages", "list", "--app", app.id], empty: L.t("asc.visuals.noPages"))
            if let v = app.current { AscSection(title: L.t("asc.visuals.experiments"), args: ["product-pages", "experiments", "list", "--version-id", v.id], empty: L.t("asc.visuals.noExperiments")) }
            AscSection(title: L.t("asc.visuals.events"), args: ["app-events", "list", "--app", app.id], empty: L.t("asc.visuals.noEvents"))
        }
    }
}

/// The rest of the store: only what the app has shows up here as a list.
private struct AscMoreTab: View {
    var app: ASCApp
    var body: some View {
        TabPage {
            AscSection(title: L.t("asc.more.appClips"), args: ["app-clips", "list", "--app", app.id], empty: L.t("asc.more.noAppClips"))
            AscSection(title: L.t("asc.more.achievements"), args: ["game-center", "achievements", "list", "--app", app.id], empty: L.t("asc.more.noGameCenter"))
            AscSection(title: L.t("asc.more.leaderboards"), args: ["game-center", "leaderboards", "list", "--app", app.id], empty: L.t("asc.more.noGameCenter"))
            AscSection(title: L.t("asc.more.webhooks"), args: ["webhooks", "list", "--app", app.id], empty: L.t("asc.more.noWebhooks"))
            AscSection(title: L.t("asc.more.assets"), args: ["background-assets", "list", "--app", app.id], empty: L.t("asc.more.noAssets"))
        }
    }
}

/// Sales and usage: the weekly insights from App Store Connect's analytics (asc insights), when available.
private struct AscAnalyticsTab: View {
    var app: ASCApp
    var body: some View {
        TabPage {
            Text(L.t("asc.analytics.intro")).font(.callout).foregroundStyle(.secondary).glassCard(padding: 14)
        }
    }
}
