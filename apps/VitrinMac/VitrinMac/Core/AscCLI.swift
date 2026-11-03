import Foundation
import Observation

/// The `asc` CLI (App Store Connect CLI by Rork) as the app's App Store Connect client: every read and write of the
/// app pages goes through it, so everything asc can do the app can do.
///
/// Authentication is optional and comes from one of two places:
/// - the key stored in Vitrin (Settings → Account), passed as asc's environment credential
///   (ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_PATH, ASC_KEY_TYPE=team; ASC_PROFILE cleared so it wins);
/// - otherwise asc's own login (`asc auth login`, kept in the keychain or ~/.asc/config.json), untouched.
/// Without either, the App Store Connect pages say how to connect and the local project pages work as before.
enum AscCLI {
    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    struct Result: Sendable {
        var code: Int32
        var stdout: String
        var stderr: String
        var ok: Bool { code == 0 }
        /// The JSON asc printed (the first `{` or `[` on stdout onwards), or nil.
        var json: JSONValue? {
            guard let i = stdout.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
            return try? JSONDecoder().decode(JSONValue.self, from: Data(stdout[i...].utf8))
        }
        /// The first meaningful error line, for a one-line message.
        var errorLine: String {
            let lines = (stderr + "\n" + stdout).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return lines.first { $0.lowercased().hasPrefix("error") } ?? lines.first ?? "asc exited with code \(code)"
        }
    }

    /// The asc executable on the login shell's PATH.
    static func path() async -> String? { await ShellEnvironment.which("asc") }

    /// The environment for an asc run: Vitrin's key when one is stored, else nothing (asc uses its own login).
    @MainActor static func authEnvironment(_ credentials: ASCCredentials = .shared) -> [String: String] {
        guard let k = credentials.key else { return [:] }
        return ["ASC_KEY_ID": k.keyId, "ASC_ISSUER_ID": k.issuerId, "ASC_PRIVATE_KEY_PATH": k.keyPath, "ASC_KEY_TYPE": "team",
                "ASC_PRIVATE_KEY_B64": "", "ASC_PRIVATE_KEY": "", "ASC_PROFILE": ""]
    }

    /// Runs `asc <args>`. `readOnly` adds `--read-only`, which makes asc refuse any POST, PATCH, PUT or DELETE.
    @MainActor static func run(_ args: [String], readOnly: Bool = true, timeout: TimeInterval = 180, extraEnv: [String: String] = [:]) async throws -> Result {
        guard let bin = await path() else { throw Failure(message: L.t("asc.missing")) }
        var env = await ShellEnvironment.environment()
        for (k, v) in authEnvironment() { env[k] = v }
        env["NO_COLOR"] = "1"
        // asc reads ASC_READ_ONLY as well; set it explicitly both ways so the user's shell cannot flip it.
        env["ASC_READ_ONLY"] = readOnly ? "1" : "0"
        for (k, v) in extraEnv { env[k] = v }
        let r = try await ProcessRunner.run(bin, args, environment: env, cwd: NSTemporaryDirectory(), timeout: timeout)
        return Result(code: r.code, stdout: r.stdout, stderr: r.stderr)
    }

    /// `asc <args> --output json`, decoded; throws with asc's own message when it fails.
    @MainActor static func json(_ args: [String], readOnly: Bool = true, timeout: TimeInterval = 180) async throws -> JSONValue {
        let r = try await run(args + ["--output", "json"], readOnly: readOnly, timeout: timeout)
        guard r.ok else { throw Failure(message: r.errorLine) }
        guard let j = r.json else { throw Failure(message: r.stdout.isEmpty ? r.errorLine : String(r.stdout.prefix(300))) }
        return j
    }
}

// MARK: connection

/// Who App Store Connect requests run as: Vitrin's stored key, asc's own login, or nobody.
@MainActor @Observable final class AscConnection {
    enum State: Equatable {
        case unknown
        case missingCLI
        case vitrinKey(keyId: String)
        case ascLogin(name: String, keyId: String)
        case none
    }
    private(set) var state: State = .unknown
    private(set) var checking = false

    var isConnected: Bool {
        switch state {
        case .vitrinKey, .ascLogin: return true
        default: return false
        }
    }

    /// Reads which credential asc would use: Vitrin's key first, else `asc auth status`.
    func refresh(credentials: ASCCredentials = .shared) async {
        checking = true
        defer { checking = false }
        guard await AscCLI.path() != nil else {
            state = credentials.key.map { .vitrinKey(keyId: $0.keyId) } ?? .missingCLI
            return
        }
        if let k = credentials.key { state = .vitrinKey(keyId: k.keyId); return }
        state = (try? await Self.ascLogin()) ?? .none
    }

    /// `asc auth status --output json`: the default stored credential, if any. asc exits 1 when none is usable.
    private static func ascLogin() async throws -> State {
        let r = try await AscCLI.run(["auth", "status", "--output", "json"])
        guard let creds = r.json?.objectValue?["credentials"]?.arrayValue, !creds.isEmpty else { return .none }
        let pick = creds.first { $0.objectValue?["isDefault"]?.boolValue == true } ?? creds[0]
        let o = pick.objectValue ?? [:]
        return .ascLogin(name: o["name"]?.stringValue ?? "asc", keyId: o["keyId"]?.stringValue ?? "")
    }
}

// MARK: help

/// One asc command's help page, parsed: its description, usage, subcommands (or the root's command groups) and flags.
/// The command palette builds its tree and forms from these, so it covers every command asc has.
struct AscHelp: Equatable, Sendable {
    struct Entry: Equatable, Hashable, Sendable, Identifiable {
        var name: String
        var summary: String
        var id: String { name }
    }
    struct Group: Equatable, Sendable, Identifiable {
        var title: String
        var entries: [Entry]
        var id: String { title }
    }
    struct Flag: Equatable, Hashable, Sendable, Identifiable {
        var name: String
        var summary: String
        /// `(default: false)` / `(default: true)`: a switch.
        var isBool: Bool
        var defaultValue: String?
        var required: Bool
        var id: String { name }
    }

    var description = ""
    var usage = ""
    var details = ""
    var groups: [Group] = []
    var flags: [Flag] = []

    var subcommands: [Entry] { groups.flatMap(\.entries) }

    /// Parses asc's help layout: `DESCRIPTION`, `USAGE`, free text, `… COMMANDS` / `SUBCOMMANDS` lists
    /// (`  name: summary` or `  name   summary`), `FLAGS` (`  --name   summary (default: x)`).
    static func parse(_ text: String) -> AscHelp {
        var h = AscHelp()
        var section = ""
        var detailLines: [String] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !line.hasPrefix(" "), !trimmed.isEmpty, trimmed == trimmed.uppercased(), trimmed.rangeOfCharacter(from: .letters) != nil {
                section = trimmed
                if section.hasSuffix("COMMANDS") { h.groups.append(Group(title: section, entries: [])) }
                continue
            }
            guard !trimmed.isEmpty else { if section == "TEXT" || section == "USAGE" { detailLines.append("") }; continue }
            switch section {
            case "DESCRIPTION":
                h.description += (h.description.isEmpty ? "" : " ") + trimmed
            case "USAGE":
                if h.usage.isEmpty, line.hasPrefix("  ") { h.usage = trimmed } else { detailLines.append(trimmed) }
            case "FLAGS":
                guard trimmed.hasPrefix("--") else { continue }
                let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                let name = String(parts[0].dropFirst(2))
                let summary = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
                var def: String?
                if let r = summary.range(of: #"\(default: ([^)]*)\)\s*$"#, options: .regularExpression) {
                    def = String(summary[r]).replacingOccurrences(of: "(default: ", with: "").replacingOccurrences(of: ")", with: "").trimmingCharacters(in: .whitespaces)
                }
                h.flags.append(Flag(name: name, summary: summary, isBool: def == "false" || def == "true", defaultValue: def, required: summary.contains("(required)")))
            default:
                if section.hasSuffix("COMMANDS"), line.hasPrefix("  "), let entry = Self.entry(trimmed) {
                    h.groups[h.groups.count - 1].entries.append(entry)
                }
            }
        }
        h.details = detailLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        // "SUBCOMMANDS" reads as one untitled group.
        return h
    }

    /// `name: summary` (root) or `name   summary` (subcommands).
    private static func entry(_ s: String) -> Entry? {
        if let colon = s.firstIndex(of: ":"), !s[..<colon].contains(" ") {
            return Entry(name: String(s[..<colon]), summary: s[s.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }
        let parts = s.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first, !first.hasPrefix("-") else { return nil }
        return Entry(name: String(first), summary: parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "")
    }

    /// Reads `asc <path…> --help` (asc prints help on stdout or stderr depending on the command).
    @MainActor static func load(_ path: [String]) async throws -> AscHelp {
        let r = try await AscCLI.run(path + ["--help"])
        let text = r.stdout.contains("USAGE") ? r.stdout : r.stderr
        guard text.contains("USAGE") else { throw AscCLI.Failure(message: r.errorLine) }
        return parse(text)
    }
}
