import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label(L.t("settings.general"), systemImage: "gear") }
            AccountSettings().tabItem { Label(L.t("settings.account"), systemImage: "person.crop.circle.badge.checkmark") }
            CLISettings().tabItem { Label(L.t("settings.cli"), systemImage: "terminal") }
            UpdateSettings().tabItem { Label(L.t("settings.updates"), systemImage: "arrow.down.circle") }
        }
        .frame(width: 600, height: 480)
    }
}

struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var settings = settings
        Form {
            Picker(L.t("settings.language"), selection: $settings.language) {
                Text(L.t("settings.languageSystem")).tag(AppLanguage.system)
                Text(L.t("settings.languageProject")).tag(AppLanguage.project)
                Text("English").tag(AppLanguage.en)
                Text("Türkçe").tag(AppLanguage.tr)
            }
            Text(L.t("settings.languageHint")).font(.caption).foregroundStyle(.secondary)
            Toggle(L.t("settings.menuBar"), isOn: $settings.showMenuBarExtra)
            Toggle(L.t("settings.keepInMenuBar"), isOn: $settings.keepInMenuBar).disabled(!settings.showMenuBarExtra)
            Toggle(L.t("settings.notifications"), isOn: $settings.notifications)
            Toggle(L.t("settings.developerMode"), isOn: $settings.developerMode)
            Text(L.t("settings.developerModeHint")).font(.caption).foregroundStyle(.secondary)
            Section("Claude") {
                ClaudeModelPicker()
                Text(L.t("settings.claudeModelHint")).font(.caption).foregroundStyle(.secondary)
            }
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
    @Environment(AppModel.self) private var model
    @State private var credentials = ASCCredentials.shared
    @State private var keyId = ""
    @State private var issuerId = ""
    @State private var p8: URL?
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        Form {
            Section {
                Text(L.t("settings.accountIntro")).font(.callout).foregroundStyle(.secondary)
                if let k = credentials.key {
                    LabeledContent(L.t("settings.keyId"), value: k.keyId)
                    LabeledContent(L.t("settings.issuerId"), value: k.issuerId)
                    LabeledContent(L.t("settings.p8")) { Text(k.keyPath).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled) }
                    Text(L.t("settings.keySaved")).font(.caption).foregroundStyle(.secondary)
                    Button(L.t("settings.removeKey"), role: .destructive) { credentials.clear(); Task { await model.restartSessions() } }.accessibilityIdentifier("settings.removeKey")
                } else {
                    TextField(L.t("settings.keyId"), text: $keyId, prompt: Text("ABC123DEFG")).accessibilityIdentifier("settings.keyId")
                    TextField(L.t("settings.issuerId"), text: $issuerId, prompt: Text("69a6de7f-…")).accessibilityIdentifier("settings.issuerId")
                    LabeledContent(L.t("settings.p8")) {
                        HStack {
                            Text(p8?.lastPathComponent ?? L.t("settings.keyNone")).font(.callout).foregroundStyle(p8 == nil ? .secondary : .primary).lineLimit(1)
                            Button(L.t("settings.chooseP8")) { pick() }.accessibilityIdentifier("settings.chooseP8")
                        }
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    Button(L.t("settings.saveKey")) { save() }.buttonStyle(.borderedProminent).disabled(saving || keyId.isEmpty || issuerId.isEmpty || p8 == nil).accessibilityIdentifier("settings.saveKey")
                }
            }
            Section {
                Text(L.t("settings.keyHint")).font(.caption).foregroundStyle(.secondary)
                Button(L.t("settings.openASC")) { NSWorkspace.shared.open(URL(string: "https://appstoreconnect.apple.com/access/integrations/api")!) }
            }
        }
        .formStyle(.grouped)
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "p8") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L.t("settings.p8")
        if panel.runModal() == .OK { p8 = panel.url; error = nil }
    }

    private func save() {
        guard let p8 else { return }
        saving = true
        defer { saving = false }
        do {
            try credentials.save(keyId: keyId, issuerId: issuerId, p8: p8)
            error = nil
            keyId = ""; issuerId = ""; self.p8 = nil
            Task { await model.restartSessions() }
        } catch {
            self.error = error.localizedDescription
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
                            if !o.installed { CopyCode(text: o.install) }
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
                LabeledContent(L.t("updates.latest")) {
                    switch u.state {
                    case .idle: Text(u.latest?.version ?? "—")
                    case .checking: ProgressView().controlSize(.small)
                    case .upToDate: Label(L.t("updates.upToDate"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .available(let v): Label(L.t("updates.availableBody").replacingOccurrences(of: "{version}", with: v).replacingOccurrences(of: "{current}", with: u.cliVersion ?? u.appVersion), systemImage: "arrow.down.circle.fill").foregroundStyle(.orange)
                    case .failed(let e): Text(e).foregroundStyle(.red)
                    }
                }
                if let at = u.checkedAt { Text("\(L.t("updates.checkedAt")) \(at.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button(L.t("updates.checkNow")) { Task { await u.check(notify: false) } }.disabled(u.state == .checking)
                    if let r = u.latest { Button(L.t("updates.openRelease")) { NSWorkspace.shared.open(URL(string: r.html_url)!) } }
                }
                if let r = u.latest, !r.assets.isEmpty {
                    Text(r.assets.map(\.name).joined(separator: ", ")).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Text(L.t("updates.cliHint")).font(.caption).foregroundStyle(.secondary)
            }
            Section("Sparkle") {
                TextField(L.t("updates.appcast"), text: $settings.appcastURL)
                Text(L.t("updates.sparkleHint")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
