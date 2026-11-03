import SwiftUI

/// Signing in with an Apple Account for what the API cannot do: the email, the password when asc doesn't have it, and
/// the code Apple sends to a trusted device.
struct AppleAccountForm: View {
    var done: () -> Void
    @State private var session = AppleWebSession.shared
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var running = false
    @State private var error: String?

    private var canSubmit: Bool { !email.trimmingCharacters(in: .whitespaces).isEmpty && (session.passwordStored || !password.isEmpty) && !running }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("web.why")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField(L.t("web.email"), text: $email).textFieldStyle(.roundedBorder).textContentType(.username)
                .accessibilityIdentifier("web.email")
            SecureField(session.passwordStored ? L.t("web.passwordStored") : L.t("web.password"), text: $password).textFieldStyle(.roundedBorder).textContentType(.password)
                .accessibilityIdentifier("web.password")
            if session.needsCode {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("web.codeHint")).font(.callout).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        TextField(L.t("web.code"), text: $code).textFieldStyle(.roundedBorder).frame(maxWidth: 140)
                            .onSubmit { session.submit(code: code); code = "" }
                        Button(L.t("web.sendCode")) { session.submit(code: code); code = "" }.disabled(code.filter(\.isNumber).count < 6)
                    }
                }
            }
            if let error { Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                if running { ProgressView().controlSize(.small) }
                Spacer()
                Button(L.t("web.signIn")) { Task { await signIn() } }.buttonStyle(GradientButtonStyle(fullWidth: false)).disabled(!canSubmit)
                    .accessibilityIdentifier("web.signIn")
            }
        }
        .task {
            await session.refresh()
            if email.isEmpty { email = session.appleID }
        }
    }

    private func signIn() async {
        running = true
        defer { running = false }
        error = nil
        do {
            try await session.signIn(appleID: email.trimmingCharacters(in: .whitespaces), password: password)
            password = ""
            if session.authenticated { done() } else { error = L.t("web.failed") }
        } catch { self.error = error.localizedDescription }
    }
}

/// `asc web api-keys create`: an Admin team key, made and added in one go.
struct AutoKeyCard: View {
    @Environment(AppModel.self) private var model
    var done: () -> Void
    @State private var session = AppleWebSession.shared
    @State private var signingIn = false
    @State private var running = false
    @State private var confirm = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("web.key.title")).font(.headline)
            Text(L.t("web.key.detail")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if session.authenticated {
                if let error { Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                HStack {
                    Button(L.t("web.key.create")) { confirm = true }.buttonStyle(GradientButtonStyle(fullWidth: false)).disabled(running)
                    if running { ProgressView().controlSize(.small) }
                }
            } else if signingIn {
                AppleAccountForm { signingIn = false }
            } else {
                Button(L.t("web.signInWith")) { signingIn = true }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await session.refresh() }
        .confirmationDialog(L.t("web.key.create"), isPresented: $confirm, titleVisibility: .visible) {
            Button(L.t("web.key.create")) { Task { await create() } }
            Button(L.t("common.cancel"), role: .cancel) {}
        } message: { Text(L.t("web.key.confirm")) }
    }

    private func create() async {
        running = true
        defer { running = false }
        error = nil
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vitrin-key-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let name = "Vitrin " + Date().formatted(.iso8601.year().month().day())
            let r = try await session.run(["web", "api-keys", "create", "--name", name, "--role", "ADMIN", "--output-dir", dir.path, "--output", "json"])
            guard r.ok else { error = r.errorLine.replacingOccurrences(of: "Error: ", with: ""); return }
            guard let file = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "p8" }),
                  let keyId = AscKeyFile.keyID(fileName: file.lastPathComponent),
                  let issuer = await AscKeyFile.issuerID(output: r.json) else { error = L.t("web.key.manual"); return }
            try ASCCredentials.shared.save(keyId: keyId, issuerId: issuer, p8: file)
            await model.restartSessions()
            done()
        } catch { self.error = error.localizedDescription }
    }
}

/// What `asc web api-keys create` leaves behind: `AuthKey_<KEY_ID>.p8`, and the team's issuer id, which every key of the
/// team shares, so the current key or asc's login gives it when the output doesn't.
enum AscKeyFile {
    static func keyID(fileName: String) -> String? {
        guard fileName.hasPrefix("AuthKey_"), fileName.hasSuffix(".p8") else { return nil }
        let id = fileName.dropFirst("AuthKey_".count).dropLast(".p8".count)
        return id.isEmpty ? nil : String(id)
    }

    @MainActor static func issuerID(output: JSONValue?) async -> String? {
        let o = output?.objectValue ?? [:]
        for key in ["issuerId", "issuerID", "issuer_id", "issuer"] { if let s = o[key]?.stringValue, !s.isEmpty { return s } }
        if let s = ASCCredentials.shared.key?.issuerId { return s }
        guard let r = try? await AscCLI.run(["auth", "issuer-id"]), r.ok else { return nil }
        let line = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty || line.contains(" ") ? nil : line
    }
}
