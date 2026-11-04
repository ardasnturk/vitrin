import SwiftUI

/// The Remote Code family Settings window: a 210 pt badge sidebar, a pane header, a grouped form on the brand
/// background. Opens on the Account pane while no key is stored.
struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case account, general, claude, cli, updates
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .account: return "key.horizontal.fill"
            case .general: return "gearshape.fill"
            case .claude: return "sparkles"
            case .cli: return "terminal.fill"
            case .updates: return "arrow.down.circle.fill"
            }
        }
        var colors: [Color] {
            switch self {
            case .account: return BadgeColors.cool
            case .general: return BadgeColors.gray
            case .claude: return BadgeColors.magic
            case .cli: return BadgeColors.deep
            case .updates: return BadgeColors.fresh
            }
        }
        var titleKey: String { self == .claude ? "settings.claude" : "settings.\(rawValue)" }
        var subtitleKey: String { "settings.\(rawValue).subtitle" }
    }

    @State private var pane: Pane = ASCCredentials.shared.isSet ? .general : .account

    var body: some View {
        HStack(spacing: 0) {
            List(Pane.allCases, selection: $pane) { p in
                Label { Text(L.t(p.titleKey)) } icon: { IconBadge(symbol: p.symbol, colors: p.colors) }
                    .padding(.vertical, 3)
                    .tag(p)
                    .accessibilityIdentifier("settings.pane.\(p.rawValue)")
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(width: 210)
            .background(.thinMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                PaneHeader(symbol: pane.symbol, colors: pane.colors, title: Text(L.t(pane.titleKey)), subtitle: Text(L.t(pane.subtitleKey)))
                Group {
                    switch pane {
                    case .account: AccountSettings()
                    case .general: GeneralSettings()
                    case .claude: ClaudeSettings()
                    case .cli: CLISettings()
                    case .updates: UpdateSettings()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .brandWindowBackground()
        }
        .frame(width: 780, height: 560)
        .onAppear { SettingsWindow.bringToFront() }
    }
}

struct ClaudeSettings: View {
    var body: some View {
        Form {
            Section {
                ClaudeModelPicker()
                Text(L.t("settings.claudeModelHint")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var settings = settings
        Form {
            LanguagePicker(selection: $settings.language)
            Text(L.t("settings.languageHint")).font(.caption).foregroundStyle(.secondary)
            Toggle(L.t("settings.menuBar"), isOn: $settings.showMenuBarExtra)
            Toggle(L.t("settings.keepInMenuBar"), isOn: $settings.keepInMenuBar).disabled(!settings.showMenuBarExtra)
            Toggle(L.t("settings.notifications"), isOn: $settings.notifications)
            Toggle(L.t("settings.developerMode"), isOn: $settings.developerMode)
            Text(L.t("settings.developerModeHint")).font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onChange(of: settings.language) { model.applyLanguage() }
    }
}

/// Settings → Claude model: the aliases, or "Other…" with a field for a full model name.
struct ClaudeModelPicker: View {
    @Environment(AppSettings.self) private var settings
    @State private var custom = false
    private static let other = "\u{0}other"
    var body: some View {
        @Bindable var settings = settings
        let known = settings.claudeModel.isEmpty || ClaudeModel.aliases.contains(where: { $0.alias == settings.claudeModel })
        let choice = Binding<String>(
            get: { custom || !known ? Self.other : settings.claudeModel },
            set: { v in
                if v == Self.other { custom = true } else { custom = false; settings.claudeModel = v }
            })
        Picker(L.t("settings.claudeModel"), selection: choice) {
            Text(L.t("settings.claudeModelDefault")).tag("")
            ForEach(ClaudeModel.aliases, id: \.alias) { Text($0.label).tag($0.alias) }
            Text(L.t("settings.claudeModelCustom")).tag(Self.other)
        }
        .accessibilityIdentifier("settings.claudeModel")
        if custom || !known {
            TextField(L.t("settings.claudeModelName"), text: $settings.claudeModel, prompt: Text("claude-opus-5-5"))
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("settings.claudeModelName")
        }
    }
}

/// Settings → Account: the App Store Connect API key, once for every project.
struct AccountSettings: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L.t("settings.accountIntro")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                AccountForm().glassCard(padding: 16)
                VStack(alignment: .leading, spacing: 8) {
                    Text(L.t("settings.keyHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button(L.t("settings.openASC")) { NSWorkspace.shared.open(URL(string: "https://appstoreconnect.apple.com/access/integrations/api")!) }
                }
                .glassCard(padding: 14)
            }
            .padding(20)
        }
    }
}

struct CLISettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @State private var doctor: [DoctorCheck]?
    @State private var uploader: UploaderReport?
    @State private var running = false
    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                LabeledContent(L.t("settings.cliFound")) {
                    if model.locating { ProgressView().controlSize(.small) }
                    else if let cli = model.cli { Text(cli.description).textSelection(.enabled).lineLimit(2).truncationMode(.middle) }
                    else { Text(model.cliError ?? L.t("cli.notFound")).foregroundStyle(.red) }
                }
                TextField(L.t("settings.cliPath"), text: $settings.cliPath, prompt: Text("…/dist/bin.js or /opt/homebrew/bin/vitrin"))
                TextField(L.t("settings.checkout"), text: $settings.vitrinCheckout, prompt: Text("/path/to/vitrin"))
                Text(L.t("settings.cliHint")).font(.caption).foregroundStyle(.secondary)
                if model.cli == nil, !model.locating { ToolInstallButton(tool: .vitrin, prominent: false) }
                Button(L.t("cli.searchAgain")) { Task { await model.locateCLI() } }
            }
            Section(L.t("settings.tools")) {
                Button(running ? L.t("common.running") : L.t("settings.runDoctor")) { Task { await runDoctor() } }.disabled(running || model.cli == nil)
                if let doctor { DoctorChecks(checks: doctor.map { c in .object(["title": .string(c.title), "status": .string(c.status), "detail": c.detail.map(JSONValue.string) ?? .null, "fix": c.fix.map(JSONValue.string) ?? .null]) }) }
                if let u = uploader {
                    ForEach(u.options) { o in
                        HStack {
                            Image(systemName: o.installed ? "checkmark.circle.fill" : "circle").foregroundStyle(o.installed ? .green : .secondary)
                            Text(o.label).font(.callout)
                            if !o.installed {
                                if let tool = LocalTool(hint: o.install) { ToolInstallButton(tool: tool, prominent: false) { Task { await runDoctor() } } } else { CopyCode(text: o.install) }
                            }
                            if u.recommended == o.uploader { Pill(L.t("settings.recommended"), .accent) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// `vitrin doctor --tools --json` in the selected project (or the home folder) and `vitrin uploader --json`.
    private func runDoctor() async {
        guard let cli = model.cli else { return }
        running = true
        defer { running = false }
        let runner = CLIRunner(location: cli)
        let cwd = model.selectedProject?.path
        let extra = cwd.map { ASCCredentials.shared.environment(forProject: $0) } ?? [:]
        let d = try? await runner.json(["doctor", "--tools"], as: DoctorResult.self, cwd: cwd, timeout: 180, extraEnv: extra)
        doctor = d?.value?.checks ?? [DoctorCheck(id: "run", title: "vitrin doctor", status: "fail", detail: d?.result.stderr.split(separator: "\n").last.map(String.init), fix: nil)]
        if cwd != nil, let u = try? await runner.json(["uploader"], as: UploaderReport.self, cwd: cwd, timeout: 180, extraEnv: extra) { uploader = u.value }
    }
}

struct UpdateSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var settings = settings
        let u = model.updates
        Form {
            Section {
                Toggle(L.t("settings.checkUpdates"), isOn: $settings.checkForUpdates)
                LabeledContent(L.t("updates.app"), value: u.appVersion)
                LabeledContent(L.t("updates.cli"), value: u.cliVersion ?? "—")
                UpdateStatus()
                if let at = u.checkedAt { Text("\(L.t("updates.checkedAt")) \(at.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button(L.t("updates.checkNow")) { Task { await u.check(notify: false) } }.disabled(u.isBusy)
                    if let r = u.latest { Button(L.t("updates.openRelease")) { NSWorkspace.shared.open(URL(string: r.html_url)!) } }
                }
                if let r = u.latest, !r.assets.isEmpty {
                    Text(r.assets.map(\.name).joined(separator: ", ")).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Text(L.t("updates.cliHint")).font(.caption).foregroundStyle(.secondary)
                if let v = model.cli?.version, v != u.appVersion { ToolInstallButton(tool: .vitrin, prominent: false) }
            }
        }
        .formStyle(.grouped)
    }
}

/// The update's state with its action: install, progress or the failure.
struct UpdateStatus: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let u = model.updates
        switch u.state {
        case .idle: LabeledContent(L.t("updates.latest"), value: u.latest?.version ?? "—")
        case .checking: LabeledContent(L.t("updates.latest")) { ProgressView().controlSize(.small) }
        case .upToDate: LabeledContent(L.t("updates.latest")) { Label(L.t("updates.upToDate"), systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
        case .available(let v):
            LabeledContent(L.t("updates.availableTitle"), value: v)
            UpdateButton()
        case .downloading(let progress): ProgressView(value: progress) { Text(L.t("updates.downloading")) }
        case .installing: LabeledContent(L.t("updates.installing")) { ProgressView().controlSize(.small) }
        case .failed(let e):
            Text(e).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            if u.latest != nil, UpdateChecker.compare(u.latest?.version ?? "0", u.appVersion) > 0 { UpdateRetry() }
        }
    }
}

struct UpdateButton: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Button(L.t("updates.install")) { Task { await model.updates.install() } }
            .buttonStyle(GradientButtonStyle(fullWidth: false))
            .accessibilityIdentifier("updates.install")
    }
}

/// After a failed install: check again, which brings the install button back.
private struct UpdateRetry: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Button(L.t("common.retry")) { Task { await model.updates.check(notify: false) } }
    }
}
