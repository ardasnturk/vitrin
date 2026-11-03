import SwiftUI

/// The first-run tour, in the main window until it is done: a step rail on the left (the Settings window's look),
/// the step on the right, Back / Skip / Continue at the bottom. Every step after the tools can be skipped.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var tour = Onboarding()

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider()
            VStack(spacing: 0) {
                ScrollView {
                    page
                        .frame(maxWidth: 720, alignment: .leading)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 30)
                        .frame(maxWidth: .infinity)
                }
                Divider()
                footer
            }
            .brandWindowBackground(intensity: 0.55)
        }
        .task { await tour.checkTools(cli: model.cli) }
        .onChange(of: model.cli) { Task { await tour.checkTools(cli: model.cli) } }
        .accessibilityIdentifier("onboarding")
    }

    // MARK: rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                IconBadge(symbol: "storefront.fill", colors: [Brand.amber, Brand.coral, Brand.pink], size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Vitrin").font(.title3.bold())
                    Text(L.t("onb.tagline.short")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 46)
            .padding(.bottom, 22)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Onboarding.Step.allCases) { step in
                    Button { tour.step = step } label: { railRow(step) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            Spacer()
            // The first thing a person may need, so it is on every step.
            LanguagePicker(selection: Binding(get: { settings.language }, set: { settings.language = $0; model.applyLanguage() }))
                .labelsHidden()
                .padding(.horizontal, 18).padding(.bottom, 12)
                .accessibilityIdentifier("onboarding.language")
            ProgressBar(fraction: Double(tour.step.rawValue) / Double(Onboarding.Step.allCases.count - 1))
                .padding(.horizontal, 18)
            Text(L.t("onb.stepOf").replacingOccurrences(of: "{n}", with: "\(tour.step.rawValue + 1)").replacingOccurrences(of: "{total}", with: "\(Onboarding.Step.allCases.count)"))
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 18)
        }
        .frame(width: 240)
        .background(.thinMaterial)
    }

    private func railRow(_ step: Onboarding.Step) -> some View {
        let current = step == tour.step
        let passed = step.rawValue < tour.step.rawValue
        return HStack(spacing: 10) {
            IconBadge(symbol: passed ? "checkmark" : step.symbol, colors: passed ? BadgeColors.fresh : colors(for: step), size: 24)
                .opacity(current || passed ? 1 : 0.55)
            Text(L.t(step.titleKey)).font(.callout.weight(current ? .semibold : .regular))
                .foregroundStyle(current ? .primary : .secondary)
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(current ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }

    private func colors(for step: Onboarding.Step) -> [Color] {
        switch step {
        case .welcome: return BadgeColors.brand
        case .tools: return BadgeColors.gray
        case .account: return BadgeColors.cool
        case .apps: return BadgeColors.deep
        case .claude: return BadgeColors.magic
        case .done: return BadgeColors.fresh
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack(spacing: 10) {
            if tour.step != .welcome {
                Button(L.t("onb.back")) { tour.back() }.controlSize(.large)
            }
            Spacer()
            if tour.step != .welcome && tour.step != .done {
                Button(L.t("onb.skip")) { tour.next() }.buttonStyle(.borderless).controlSize(.large)
                    .accessibilityIdentifier("onboarding.skip")
            }
            if tour.step == .done {
                Button { finish() } label: { Label(L.t("onb.open"), systemImage: "arrow.right") }
                    .buttonStyle(GradientButtonStyle(fullWidth: false)).keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding.finish")
            } else {
                Button { tour.next() } label: { Text(tour.step == .welcome ? L.t("onb.start") : L.t("onb.continue")) }
                    .buttonStyle(GradientButtonStyle(fullWidth: false)).keyboardShortcut(.defaultAction)
                    .disabled(tour.step == .tools && tour.missingRequired)
                    .accessibilityIdentifier("onboarding.continue")
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(.bar)
    }

    private func finish() {
        settings.onboardingDone = true
        if model.selectedProjectID == nil, model.selectedAppID == nil { model.showHome = true }
    }

    // MARK: pages

    @ViewBuilder private var page: some View {
        switch tour.step {
        case .welcome: WelcomeStep()
        case .tools: ToolsStep(tour: tour)
        case .account: AccountStep()
        case .apps: AppsStep()
        case .claude: ClaudeStep()
        case .done: DoneStep(tour: tour)
        }
    }
}

/// A step's title block: the badge, the title and one sentence.
private struct StepHeader: View {
    var symbol: String
    var colors: [Color]
    var title: String
    var subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(symbol: symbol, colors: colors, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.largeTitle.bold())
                Text(subtitle).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 8)
    }
}

// MARK: 1 · welcome

private struct WelcomeStep: View {
    private let features: [(symbol: String, colors: [Color], key: String)] = [
        ("square.grid.2x2.fill", BadgeColors.cool, "asc"),
        ("text.word.spacing", BadgeColors.magic, "claude"),
        ("iphone.gen3", BadgeColors.brand, "visuals"),
        ("magnifyingglass", BadgeColors.deep, "research"),
        ("checkmark.seal.fill", BadgeColors.fresh, "review"),
        ("arrow.up.circle.fill", BadgeColors.warm, "upload"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("onb.welcome.title")).font(.largeTitle.bold())
                        Text(L.t("onb.welcome.tagline")).font(.title3).opacity(0.9)
                    }
                }
                Text(L.t("onb.welcome.lead")).font(.callout).opacity(0.9).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            SectionTitle(L.t("onb.welcome.what"))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(features, id: \.key) { f in
                    HStack(alignment: .top, spacing: 12) {
                        IconBadge(symbol: f.symbol, colors: f.colors, size: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L.t("onb.feature.\(f.key)")).font(.headline)
                            Text(L.t("onb.feature.\(f.key).detail")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .glassCard(padding: 14)
                }
            }
            Label(L.t("onb.welcome.privacy"), systemImage: "lock.shield").font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: 2 · tools

private struct ToolsStep: View {
    @Environment(AppModel.self) private var model
    var tour: Onboarding

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(symbol: "wrench.and.screwdriver.fill", colors: BadgeColors.gray, title: L.t("onb.tools.title"), subtitle: L.t("onb.tools.subtitle"))
            VStack(spacing: 0) {
                ForEach(Array(tour.tools.enumerated()), id: \.element.id) { i, tool in
                    if i > 0 { Divider() }
                    row(tool)
                }
                if tour.tools.isEmpty { ProgressView().padding(20) }
            }
            .glassCard(padding: 6)
            HStack {
                Button { Task { await model.locateCLI(); await tour.checkTools(cli: model.cli) } } label: { Label(L.t("onb.tools.again"), systemImage: "arrow.clockwise") }
                    .disabled(tour.checkingTools)
                if tour.checkingTools { ProgressView().controlSize(.small) }
                Spacer()
                SettingsButton { Text(L.t("onb.tools.cliSettings")) }
            }
            if tour.missingRequired { Label(L.t("onb.tools.required"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout) }
        }
    }

    private func row(_ t: Onboarding.Tool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: t.found ? "checkmark.circle.fill" : (t.need == .required ? "xmark.circle.fill" : "circle.dashed"))
                .font(.title3)
                .foregroundStyle(t.found ? .green : (t.need == .required ? .red : .secondary))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(t.name).font(.body.weight(.medium))
                    Pill(L.t("onb.need.\(t.need)"), t.need == .required ? .warn : .neutral)
                }
                Text(L.t(t.purposeKey)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !t.found { CopyCode(text: t.install) }
            }
            Spacer()
            if let p = t.path { Text(p).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 200, alignment: .trailing) }
        }
        .padding(10)
    }
}

// MARK: 3 · account

private struct AccountStep: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(symbol: "key.horizontal.fill", colors: BadgeColors.cool, title: L.t("onb.account.title"), subtitle: L.t("onb.account.subtitle"))
                .task { await model.connection.refresh() }
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(L.t("onb.account.how"))
                NumberedStep(n: 1, title: L.t("onb.account.step1"), detail: L.t("onb.account.step1.detail")) {
                    Button(L.t("settings.openASC")) { NSWorkspace.shared.open(URL(string: "https://appstoreconnect.apple.com/access/integrations/api")!) }.controlSize(.small)
                }
                NumberedStep(n: 2, title: L.t("onb.account.step2"), detail: L.t("onb.account.step2.detail"))
                NumberedStep(n: 3, title: L.t("onb.account.step3"), detail: L.t("onb.account.step3.detail"))
            }
            .glassCard(padding: 16)
            if case .ascLogin(let name, let keyId) = model.connection.state {
                HStack(alignment: .top, spacing: 12) {
                    IconBadge(symbol: "terminal.fill", colors: BadgeColors.fresh, size: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("onb.account.ascFound")).font(.headline)
                        Text("\(name) · Key ID \(keyId)").font(.callout.monospaced()).foregroundStyle(.secondary)
                        Text(L.t("onb.account.ascFoundDetail")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .glassCard(padding: 16)
            }
            AccountForm()
                .glassCard(padding: 16)
            Label(L.t("onb.account.privacy"), systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A numbered instruction: the number in a tinted circle, a title, one line of detail and an optional control.
struct NumberedStep<Accessory: View>: View {
    var n: Int
    var title: String
    var detail: String
    @ViewBuilder var accessory: Accessory
    init(n: Int, title: String, detail: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.n = n
        self.title = title
        self.detail = detail
        self.accessory = accessory()
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.headline).frame(width: 26, height: 26).background(Circle().fill(Color.accentColor.opacity(0.15))).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                accessory
            }
        }
    }
}

/// The App Store Connect key: the form when none is stored, a summary with the team's app count when one is.
/// Saving stores the key, reads the team's apps with it (the check) and restarts the open Studios.
struct AccountForm: View {
    @Environment(AppModel.self) private var model
    @State private var credentials = ASCCredentials.shared
    @State private var keyId = ""
    @State private var issuerId = ""
    @State private var p8: URL?
    @State private var error: String?
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let k = credentials.key, !editing {
                HStack(alignment: .top, spacing: 12) {
                    IconBadge(symbol: "checkmark", colors: BadgeColors.fresh, size: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("onb.account.saved")).font(.headline)
                        Text("Key ID \(k.keyId) · Issuer \(k.issuerId.prefix(8))…").font(.callout.monospaced()).foregroundStyle(.secondary)
                        check
                    }
                    Spacer()
                    Button(L.t("onb.account.change")) { editing = true }
                    Button(L.t("settings.removeKey"), role: .destructive) { credentials.clear(); model.ascApps.clear(); Task { await model.restartSessions() } }
                        .accessibilityIdentifier("settings.removeKey")
                }
            } else {
                SectionTitle(L.t("onb.account.form"))
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text(L.t("settings.keyId")).gridColumnAlignment(.trailing)
                        TextField("", text: $keyId, prompt: Text("ABC123DEFG")).textFieldStyle(.roundedBorder).accessibilityIdentifier("settings.keyId")
                    }
                    GridRow {
                        Text(L.t("settings.issuerId"))
                        TextField("", text: $issuerId, prompt: Text("69a6de7f-0000-47e3-e053-5b8c7c11a4d1")).textFieldStyle(.roundedBorder).accessibilityIdentifier("settings.issuerId")
                    }
                    GridRow {
                        Text(L.t("settings.p8"))
                        HStack {
                            Button(L.t("settings.chooseP8")) { pick() }.accessibilityIdentifier("settings.chooseP8")
                            Text(p8?.lastPathComponent ?? L.t("settings.keyNone")).font(.callout).foregroundStyle(p8 == nil ? .secondary : .primary).lineLimit(1)
                        }
                    }
                }
                if let error { Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                HStack {
                    if editing { Button(L.t("common.cancel")) { editing = false; error = nil } }
                    Spacer()
                    Button { save() } label: { Label(L.t("onb.account.saveCheck"), systemImage: "checkmark.shield") }
                        .buttonStyle(GradientButtonStyle(fullWidth: false))
                        .disabled(keyId.trimmingCharacters(in: .whitespaces).isEmpty || issuerId.trimmingCharacters(in: .whitespaces).isEmpty || p8 == nil)
                        .accessibilityIdentifier("settings.saveKey")
                }
            }
        }
    }

    /// The result of reading the team's apps with the stored key: the check that the key works.
    @ViewBuilder private var check: some View {
        let list = model.ascApps
        if list.loading {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(L.t("onb.account.checking")).font(.callout) }
        } else if let e = list.error {
            Label(e, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            Button(L.t("apps.refresh")) { Task { await model.refreshApps() } }.controlSize(.small)
        } else if list.loadedAt != nil {
            Label(L.t("onb.account.ok").replacingOccurrences(of: "{n}", with: "\(list.apps.count)"), systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green)
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "p8") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L.t("settings.p8")
        if panel.runModal() == .OK {
            p8 = panel.url
            error = nil
            // AuthKey_ABC123DEFG.p8 names its key id: fill it in when the field is empty.
            if keyId.isEmpty, let name = panel.url?.deletingPathExtension().lastPathComponent, name.hasPrefix("AuthKey_") { keyId = String(name.dropFirst("AuthKey_".count)) }
        }
    }

    private func save() {
        guard let p8 else { return }
        do {
            try credentials.save(keyId: keyId, issuerId: issuerId, p8: p8)
            error = nil
            editing = false
            keyId = ""; issuerId = ""; self.p8 = nil
            Task { await model.restartSessions() }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: 4 · apps and projects

private struct AppsStep: View {
    @Environment(AppModel.self) private var model
    @State private var credentials = ASCCredentials.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(symbol: "square.grid.2x2.fill", colors: BadgeColors.deep, title: L.t("onb.apps.title"), subtitle: L.t("onb.apps.subtitle"))
            if model.connection.isConnected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionTitle(L.t("apps.title"))
                        Spacer()
                        if model.ascApps.loading { ProgressView().controlSize(.small) }
                        else { Button { Task { await model.refreshApps() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless) }
                    }
                    if let e = model.ascApps.error { Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout) }
                    ForEach(model.ascApps.apps) { app in
                        appRow(app)
                        if app.id != model.ascApps.apps.last?.id { Divider() }
                    }
                }
                .glassCard(padding: 14)
            } else {
                Label(L.t("onb.apps.noKey"), systemImage: "key.slash").font(.callout).foregroundStyle(.secondary).glassCard(padding: 14)
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(L.t("projects.title"))
                Text(L.t("onb.apps.projects")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                ForEach(model.store.projects) { p in
                    HStack(spacing: 10) {
                        IconBadge(symbol: "folder.fill", colors: BadgeColors.warm, size: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).font(.body.weight(.medium))
                            Text(p.path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if let a = model.ascApp(for: p) { Pill(a.name, .ok) }
                    }
                }
                Button { model.pickProjectFolder() } label: { Label(L.t("projects.add"), systemImage: "folder.badge.plus") }
                    .accessibilityIdentifier("onboarding.addProject")
            }
            .glassCard(padding: 14)
        }
    }

    private func appRow(_ app: ASCApp) -> some View {
        HStack(spacing: 10) {
            IconBadge(symbol: "app.fill", colors: BadgeColors.cool, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.body.weight(.medium)).lineLimit(1)
                Text(app.bundleId).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let v = app.current {
                Text("\(ASCWords.platform(v.platform)) \(v.version)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Pill(ASCWords.state(v.state), ASCWords.tone(v.state))
            }
            if let p = model.linkedProject(for: app) {
                Label(p.name, systemImage: "link").font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 140, alignment: .trailing)
            } else {
                Button(L.t("apps.link")) { model.pickProjectFolder() }.controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: 5 · Claude

private struct ClaudeStep: View {
    @Environment(AppSettings.self) private var settings
    private let options: [(tag: String, key: String)] = [("", "default"), ("fable", "fable"), ("opus", "opus"), ("sonnet", "sonnet"), ("haiku", "haiku")]

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(symbol: "sparkles", colors: BadgeColors.magic, title: L.t("onb.claude.title"), subtitle: L.t("onb.claude.subtitle"))
            VStack(spacing: 8) {
                ForEach(options, id: \.tag) { o in
                    let selected = settings.claudeModel == o.tag
                    Button { settings.claudeModel = o.tag } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected ? "largecircle.fill.circle" : "circle").font(.title3).foregroundStyle(selected ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L.t("onb.model.\(o.key)")).font(.headline)
                                Text(L.t("onb.model.\(o.key).detail")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .glassCard(padding: 12)
                        .overlay { if selected { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Brand.buttonGradient, lineWidth: 1.5) } }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(L.t("onb.claude.note")).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: 6 · done

private struct DoneStep: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    var tour: Onboarding
    @State private var credentials = ASCCredentials.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(symbol: "checkmark.seal.fill", colors: BadgeColors.fresh, title: L.t("onb.done.title"), subtitle: L.t("onb.done.subtitle"))
            VStack(alignment: .leading, spacing: 10) {
                item(ok: !tour.missingRequired, L.t("onb.done.tools"), go: .tools)
                item(ok: model.connection.isConnected && model.ascApps.error == nil, model.connection.isConnected ? L.t("onb.done.key").replacingOccurrences(of: "{n}", with: "\(model.ascApps.apps.count)") : L.t("onb.done.noKey"), go: .account)
                item(ok: !model.store.projects.isEmpty, model.store.projects.isEmpty ? L.t("onb.done.noProjects") : L.t("onb.done.projects").replacingOccurrences(of: "{n}", with: "\(model.store.projects.count)"), go: .apps)
                item(ok: true, L.t("onb.done.model").replacingOccurrences(of: "{model}", with: ClaudeModel.label(settings.claudeModel)), go: .claude)
            }
            .glassCard(padding: 16)
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(L.t("onb.done.next"))
                Label(L.t("onb.done.tip1"), systemImage: "1.circle")
                Label(L.t("onb.done.tip2"), systemImage: "2.circle")
                Label(L.t("onb.done.tip3"), systemImage: "menubar.rectangle")
            }
            .font(.callout)
            .glassCard(padding: 16)
        }
    }

    private func item(ok: Bool, _ text: String, go step: Onboarding.Step) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(ok ? .green : .orange).font(.title3)
            Text(text).font(.callout)
            Spacer()
            if !ok { Button(L.t("onb.done.fix")) { tour.step = step }.controlSize(.small) }
        }
    }
}
