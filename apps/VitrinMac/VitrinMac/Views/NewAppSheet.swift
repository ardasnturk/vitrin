import SwiftUI

/// A new app on App Store Connect. Apple's API can't create one, so this signs in with the Apple Account and runs
/// `asc web apps create`, which also registers the bundle ID when the team's key can.
struct NewAppSheet: View {
    @Environment(AppModel.self) private var model
    var close: () -> Void
    @State private var session = AppleWebSession.shared
    @State private var name = ""
    @State private var bundleID = ""
    @State private var sku = ""
    @State private var skuEdited = false
    @State private var platform = "IOS"
    @State private var locale = "en-US"
    @State private var version = "1.0"
    @State private var knownBundles: [String] = []
    @State private var checking = true
    @State private var running = false
    @State private var confirm = false
    @State private var error: String?

    static let platforms = ["IOS", "MAC_OS", "TV_OS", "UNIVERSAL"]
    /// The languages App Store Connect takes as a primary language.
    static let locales = ["ar-SA", "ca", "cs", "da", "de-DE", "el", "en-AU", "en-CA", "en-GB", "en-US", "es-ES", "es-MX", "fi", "fr-CA", "fr-FR", "he", "hi", "hr", "hu", "id", "it", "ja", "ko", "ms", "nl-NL", "no", "pl", "pt-BR", "pt-PT", "ro", "ru", "sk", "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant"]

    private var ready: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && Self.validBundleID(bundleID) && !sku.trimmingCharacters(in: .whitespaces).isEmpty && !version.isEmpty
    }

    /// `com.example.app`: letters, digits, hyphens and dots, at least two parts.
    nonisolated static func validBundleID(_ s: String) -> Bool {
        s.wholeMatch(of: /[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+/) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconBadge(symbol: "plus.app.fill", colors: BadgeColors.brand, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("newapp.title")).font(.title3.bold())
                    Text(L.t("newapp.detail")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if checking {
                ProgressView().controlSize(.small)
            } else if !session.authenticated && !running {
                AppleAccountForm { }.glassCard(padding: 14)
            } else {
                form
            }
            if session.needsCode && running && session.authenticated {
                AppleAccountCodeRow()
            }
            if let error { Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                if running { ProgressView().controlSize(.small) }
                Spacer()
                Button(L.t("common.cancel"), action: close).keyboardShortcut(.cancelAction).disabled(running)
                if session.authenticated {
                    Button(L.t("newapp.create")) { confirm = true }.buttonStyle(GradientButtonStyle(fullWidth: false)).disabled(!ready || running)
                        .accessibilityIdentifier("newapp.create")
                }
            }
        }
        .padding(20)
        .frame(width: 560)
        .task {
            await session.refresh()
            checking = false
            if let doc = try? await AscCLI.json(["bundle-ids", "list", "--paginate"]) {
                knownBundles = JSONAPI.items(doc).map { JSONAPI.text($0, "identifier") }.filter { !$0.isEmpty && !$0.contains("*") }.sorted()
            }
        }
        .confirmationDialog(L.t("newapp.create"), isPresented: $confirm, titleVisibility: .visible) {
            Button(L.t("newapp.create")) { Task { await create() } }
            Button(L.t("common.cancel"), role: .cancel) {}
        } message: { Text(L.t("newapp.confirm").replacingOccurrences(of: "{name}", with: name)) }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeled(L.t("newapp.name"), info: "info.newapp.name") {
                TextField("", text: $name).textFieldStyle(.roundedBorder).accessibilityIdentifier("newapp.name")
            }
            labeled("Bundle ID", info: "info.newapp.bundle") {
                HStack {
                    TextField("com.example.app", text: Binding(get: { bundleID }, set: { bundleID = $0; if !skuEdited { sku = $0 } }))
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("newapp.bundle")
                    if !knownBundles.isEmpty {
                        Menu(L.t("newapp.existing")) {
                            ForEach(knownBundles, id: \.self) { b in Button(b) { bundleID = b; if !skuEdited { sku = b } } }
                        }
                        .fixedSize()
                    }
                }
            }
            labeled("SKU", info: "info.newapp.sku") {
                TextField("", text: Binding(get: { sku }, set: { sku = $0; skuEdited = true })).textFieldStyle(.roundedBorder).accessibilityIdentifier("newapp.sku")
            }
            HStack(spacing: 12) {
                Picker(AscText.field("platform"), selection: $platform) {
                    ForEach(Self.platforms, id: \.self) { p in Text(AscText.value(p)).tag(p) }
                }
                labeled(L.t("newapp.version"), info: nil) { TextField("1.0", text: $version).textFieldStyle(.roundedBorder).frame(width: 80) }
            }
            Picker(L.t("newapp.language"), selection: $locale) {
                ForEach(Self.locales.sorted { AscText.language($0) < AscText.language($1) }, id: \.self) { l in Text(AscText.language(l)).tag(l) }
            }
        }
        .glassCard(padding: 14)
    }

    private func labeled<Content: View>(_ title: String, info: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) { Text(title).font(.callout); if let info { InfoButton(key: info) } }
            content()
        }
    }

    private func create() async {
        running = true
        defer { running = false }
        error = nil
        let id = bundleID.trimmingCharacters(in: .whitespaces)
        do {
            // --auto-rename would quietly add a suffix to a taken name; the person should decide.
            let r = try await session.run(["web", "apps", "create", "--name", name.trimmingCharacters(in: .whitespaces), "--bundle-id", id, "--sku", sku.trimmingCharacters(in: .whitespaces),
                                           "--platform", platform, "--primary-locale", locale, "--version", version, "--auto-rename=false", "--output", "json"])
            guard r.ok else { error = r.errorLine.replacingOccurrences(of: "Error: ", with: ""); return }
            await model.refreshApps()
            if let app = model.ascApps.apps.first(where: { $0.bundleId == id }) { await model.select(app: app) }
            close()
        } catch { self.error = error.localizedDescription }
    }
}

/// The code field, when a run that was already signed in needs a fresh sign-in on the way.
private struct AppleAccountCodeRow: View {
    @State private var session = AppleWebSession.shared
    @State private var code = ""
    var body: some View {
        HStack {
            Text(L.t("web.codeHint")).font(.callout).fixedSize(horizontal: false, vertical: true)
            TextField(L.t("web.code"), text: $code).textFieldStyle(.roundedBorder).frame(maxWidth: 120)
            Button(L.t("web.sendCode")) { session.submit(code: code); code = "" }.disabled(code.filter(\.isNumber).count < 6)
        }
    }
}
