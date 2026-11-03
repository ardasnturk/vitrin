import SwiftUI

/// Connects Apple Ads from inside the app. Apple Ads has its own API users and keys, so three steps stay with the user
/// (inviting the API user, pasting the public key, copying back the ids); the app makes the key pair and signs in.
struct AppleAdsConnect: View {
    var done: () -> Void
    @State private var publicKey: String?
    @State private var clientId = ""
    @State private var teamId = ""
    @State private var keyId = ""
    @State private var running = false
    @State private var error: String?
    private static let adsURL = URL(string: "https://ads.apple.com")!

    private var ready: Bool { [clientId, teamId, keyId].allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(symbol: "megaphone.fill", colors: BadgeColors.brand, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("ads.title")).font(.headline)
                    Text(L.t("ads.why")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .glassCard(padding: 14)
            step(1, L.t("ads.step1.title")) {
                Text(L.t("ads.step1")).font(.callout).fixedSize(horizontal: false, vertical: true)
                Link(destination: Self.adsURL) { Label(L.t("ads.open"), systemImage: "arrow.up.right.square") }.font(.callout)
            }
            step(2, L.t("ads.step2.title")) {
                Text(L.t("ads.step2")).font(.callout).fixedSize(horizontal: false, vertical: true)
                if let publicKey {
                    Text(publicKey).font(.caption.monospaced()).textSelection(.enabled).padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(publicKey, forType: .string)
                    } label: { Label(L.t("ads.copyKey"), systemImage: "doc.on.doc") }
                        .controlSize(.small)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            step(3, L.t("ads.step3.title")) {
                Text(L.t("ads.step3")).font(.callout).fixedSize(horizontal: false, vertical: true)
                field("clientId", "SEARCHADS.…", $clientId)
                field("teamId", "SEARCHADS.…", $teamId)
                field("keyId", "", $keyId)
                if let error { Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                HStack {
                    if running { ProgressView().controlSize(.small) }
                    Spacer()
                    Button(L.t("ads.connect")) { Task { await connect() } }
                        .buttonStyle(GradientButtonStyle(fullWidth: false)).disabled(running || !ready || publicKey == nil)
                        .accessibilityIdentifier("ads.connect")
                }
            }
        }
        .task {
            guard publicKey == nil else { return }
            do { publicKey = try await AppleAdsKey.publicKey() } catch { self.error = error.localizedDescription }
        }
    }

    private func step<Content: View>(_ n: Int, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            StepLine(number: n, text: title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 14)
    }

    /// One id; the block Apple shows, pasted here, fills all three.
    private func field(_ name: String, _ prompt: String, _ value: Binding<String>) -> some View {
        LabeledContent(name) {
            TextField("", text: Binding(get: { value.wrappedValue }, set: { v in
                if let ids = AppleAdsKey.parse(block: v) { clientId = ids.clientId; teamId = ids.teamId; keyId = ids.keyId } else { value.wrappedValue = v }
            }), prompt: Text(prompt))
            .textFieldStyle(.roundedBorder)
        }
    }

    private func connect() async {
        running = true
        defer { running = false }
        error = nil
        let args = ["ads", "auth", "login", "--name", "Vitrin", "--client-id", clientId.trimmingCharacters(in: .whitespaces), "--team-id", teamId.trimmingCharacters(in: .whitespaces),
                    "--key-id", keyId.trimmingCharacters(in: .whitespaces), "--private-key", AppleAdsKey.privateKey.path, "--network"]
        do {
            let r = try await AscCLI.run(args, readOnly: false)
            if r.ok { done() } else { error = r.errorLine.replacingOccurrences(of: "Error: ", with: "") }
        } catch { self.error = error.localizedDescription }
    }
}

/// Apple Ads on the team page: the connection when it is missing, the account when it is there.
struct AppleAdsPage: View {
    @State private var tick = 0
    var body: some View {
        AscLoad(args: ["ads", "auth", "status"], refresh: tick) { doc, reload in
            if (doc.objectValue?["credentials"]?.arrayValue ?? []).isEmpty {
                AppleAdsConnect { tick += 1; reload() }
            } else {
                AscSection(title: L.t("ads.account"), args: ["ads", "me", "view"])
                AscSection(title: L.t("ads.accounts"), args: ["ads", "auth", "discover"])
            }
        }
    }
}

/// Installs asc with Homebrew, without a terminal.
struct InstallAscButton: View {
    var done: () -> Void
    @State private var running = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(L.t("asc.install")) { Task { await install() } }.buttonStyle(GradientButtonStyle(fullWidth: false)).disabled(running)
                if running { ProgressView().controlSize(.small); Text(L.t("asc.installing")).font(.callout).foregroundStyle(.secondary) }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func install() async {
        running = true
        defer { running = false }
        guard let brew = await ShellEnvironment.which("brew") else { error = L.t("asc.noBrew"); return }
        do {
            let r = try await ProcessRunner.run(brew, ["install", "asc"], environment: await ShellEnvironment.environment(), timeout: 600)
            if r.code == 0 { error = nil; done() } else { error = String(r.stderr.suffix(300)) }
        } catch { self.error = error.localizedDescription }
    }
}

/// Installs the Vitrin CLI of this release with the launcher the Claude Code plugin uses, bundled in the app: it
/// verifies the release tarball against the plugin's checksums, installs it for this user, and fetches Chromium.
struct InstallCLIButton: View {
    @Environment(AppModel.self) private var model
    @State private var running = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(L.t("cli.install")) { Task { await install() } }.buttonStyle(GradientButtonStyle(fullWidth: false)).disabled(running)
                    .accessibilityIdentifier("cli.install")
                if running { ProgressView().controlSize(.small); Text(L.t("cli.installing")).font(.callout).foregroundStyle(.secondary) }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
        }
    }

    private func install() async {
        running = true
        defer { running = false }
        error = nil
        do {
            var env = await ShellEnvironment.environment()
            if await ShellEnvironment.which("npm") == nil {
                guard let brew = await ShellEnvironment.which("brew") else { error = L.t("cli.needsNode"); return }
                let r = try await ProcessRunner.run(brew, ["install", "node"], environment: env, timeout: 900)
                guard r.code == 0 else { error = String(r.stderr.suffix(300)); return }
                env = await ShellEnvironment.environment()
            }
            guard let launcher = Bundle.main.url(forResource: "vitrin", withExtension: nil)?.appendingPathComponent("bin/vitrin") else { error = L.t("cli.needsNode"); return }
            env["VITRIN_VERSION"] = model.updates.appVersion
            let r = try await ProcessRunner.run("/bin/bash", [launcher.path, "--version"], environment: env, timeout: 1500)
            guard r.code == 0 else { error = String((r.stderr.isEmpty ? r.stdout : r.stderr).suffix(400)); return }
            await model.locateCLI()
            if let p = model.selectedProject { await model.open(p) }
        } catch { self.error = error.localizedDescription }
    }
}
