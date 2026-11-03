import Foundation

/// How the app runs the Vitrin CLI: `node <bin.js>` (plugin install, developer checkout) or a `vitrin` executable on PATH.
struct CLILocation: Hashable, Sendable {
    enum Kind: String, Sendable { case explicit, plugin, path, checkout }
    var kind: Kind
    /// The executable to start and the arguments before the Vitrin command.
    var executable: String
    var leadingArguments: [String]
    var version: String?
    /// Where it was found, for the Settings window.
    @MainActor var description: String {
        switch kind {
        case .plugin: return "\(L.t("cli.plugin")) · \(leadingArguments.last ?? executable)"
        case .path: return "\(L.t("cli.path")) · \(executable)"
        case .checkout: return "\(L.t("cli.checkout")) · \(leadingArguments.last ?? executable)"
        case .explicit: return "\(L.t("cli.explicit")) · \(leadingArguments.last ?? executable)"
        }
    }
    var displayPath: String { leadingArguments.last ?? executable }
}

enum CLIError: LocalizedError, Sendable {
    case nodeMissing(found: String?)
    case notFound
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .nodeMissing(let found): return found.map { "Node.js 22 or newer is required (found \($0))." } ?? "Node.js 22 or newer is required, but node was not found."
        case .notFound: return "The Vitrin CLI was not found."
        case .failed(let s): return s
        }
    }
}

/// The user's shell environment: a GUI app starts with a bare PATH, so tools like node, asc, ffmpeg and
/// claude are found through the login shell once, then passed to every process the app starts.
enum ShellEnvironment {
    nonisolated(unsafe) private static var cached: [String: String]?

    static func environment() async -> [String: String] {
        if let cached { return cached }
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        if let shellPath = await loginShellPath(), !shellPath.isEmpty { path = shellPath }
        // Homebrew, nvm and the usual user bins, even when the login shell did not say so.
        var extra = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.local/share/vitrin/bin"]
        if let nvm = try? FileManager.default.contentsOfDirectory(atPath: "\(home)/.nvm/versions/node") {
            for v in nvm.sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending }) { extra.append("\(home)/.nvm/versions/node/\(v)/bin") }
        }
        for dir in extra where !path.split(separator: ":").contains(Substring(dir)) && FileManager.default.fileExists(atPath: dir) { path += ":\(dir)" }
        env["PATH"] = path
        cached = env
        return env
    }

    private static func loginShellPath() async -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let r = try? await ProcessRunner.run(shell, ["-lic", "printf %s \"$PATH\""], environment: ProcessInfo.processInfo.environment, timeout: 8)
        guard let r, r.code == 0 else { return nil }
        return r.stdout.split(separator: "\n").last.map(String.init)
    }

    /// `which` in the resolved environment.
    static func which(_ tool: String) async -> String? {
        let env = await environment()
        for dir in (env["PATH"] ?? "").split(separator: ":") {
            let p = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }
}

enum CLILocator {
    static let minimumNode = 22

    /// Node.js 22+: the first `node` on the PATH that is new enough.
    static func node() async throws -> String {
        let env = await ShellEnvironment.environment()
        var found: String?
        for dir in (env["PATH"] ?? "").split(separator: ":") {
            let p = "\(dir)/node"
            guard FileManager.default.isExecutableFile(atPath: p) else { continue }
            if let r = try? await ProcessRunner.run(p, ["--version"], environment: env, timeout: 10), r.code == 0 {
                let v = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                found = found ?? v
                if let major = Int(v.dropFirst().split(separator: ".").first ?? ""), major >= minimumNode { return p }
            }
        }
        throw CLIError.nodeMissing(found: found)
    }

    /// The plugin install: `${VITRIN_HOME:-~/.local/share/vitrin}/<version>/node_modules/@ardasnturk/vitrin/dist/bin.js`, newest version.
    static func pluginInstall() -> String? {
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let base = env["VITRIN_HOME"] ?? "\(env["XDG_DATA_HOME"] ?? "\(home)/.local/share")/vitrin"
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: base) else { return nil }
        for v in versions.filter({ $0.first?.isNumber == true }).sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending }) {
            let entry = "\(base)/\(v)/node_modules/@ardasnturk/vitrin/dist/bin.js"
            if FileManager.default.fileExists(atPath: entry), FileManager.default.fileExists(atPath: "\(base)/\(v)/.vitrin-installed") { return entry }
        }
        return nil
    }

    /// Finds the CLI: the explicit path from Settings, the plugin install, `vitrin` on PATH, then a developer checkout.
    /// A candidate counts only when its `studio` command knows `--token-file` (Vitrin 1.3+); older ones are skipped
    /// and named in the error when nothing newer is found.
    static func locate(settings: (cliPath: String, checkout: String)) async throws -> CLILocation {
        let fm = FileManager.default
        var candidates: [CLILocation] = []
        let explicit = settings.cliPath.trimmingCharacters(in: .whitespaces)
        if !explicit.isEmpty {
            if explicit.hasSuffix(".js") { candidates.append(CLILocation(kind: .explicit, executable: try await node(), leadingArguments: [explicit], version: nil)) }
            else if fm.isExecutableFile(atPath: explicit) { candidates.append(CLILocation(kind: .explicit, executable: explicit, leadingArguments: [], version: nil)) }
            else { throw CLIError.failed("\(explicit) is not a vitrin executable or a bin.js.") }
        }
        var nodeError: Error?
        func withNode(_ entry: String, _ kind: CLILocation.Kind) async {
            do { candidates.append(CLILocation(kind: kind, executable: try await node(), leadingArguments: [entry], version: nil)) } catch { nodeError = error }
        }
        if let entry = pluginInstall() { await withNode(entry, .plugin) }
        if let bin = await ShellEnvironment.which("vitrin") { candidates.append(CLILocation(kind: .path, executable: bin, leadingArguments: [], version: nil)) }
        let checkout = settings.checkout.trimmingCharacters(in: .whitespaces)
        if !checkout.isEmpty {
            let entry = "\(checkout)/packages/cli/dist/bin.js"
            if fm.fileExists(atPath: entry) { await withNode(entry, .checkout) }
            else if candidates.isEmpty { throw CLIError.failed("\(checkout) has no build (packages/cli/dist/bin.js). Run pnpm install && pnpm build there.") }
        }
        if candidates.isEmpty {
            if let nodeError { throw nodeError }
            throw CLIError.notFound
        }
        var tooOld: [String] = []
        for var c in candidates {
            c.version = await version(of: c)
            guard c.version != nil else { continue }
            if await supportsTokenFile(c) { return c }
            tooOld.append("\(c.displayPath) (\(c.version ?? "?"))")
        }
        if !tooOld.isEmpty { throw CLIError.failed("The Vitrin CLI found is too old for this app (needs `vitrin studio --token-file`, Vitrin 1.3 or newer): \(tooOld.joined(separator: ", ")). Update it, or point Settings → Vitrin CLI at a newer one.") }
        throw CLIError.notFound
    }

    /// `vitrin studio --help` mentions `--token-file` from 1.3 on.
    static func supportsTokenFile(_ loc: CLILocation) async -> Bool {
        let env = await ShellEnvironment.environment()
        guard let r = try? await ProcessRunner.run(loc.executable, loc.leadingArguments + ["studio", "--help"], environment: env, timeout: 30) else { return false }
        return r.stdout.contains("--token-file")
    }

    static func version(of loc: CLILocation) async -> String? {
        let env = await ShellEnvironment.environment()
        guard let r = try? await ProcessRunner.run(loc.executable, loc.leadingArguments + ["--version"], environment: env, timeout: 30), r.code == 0 else { return nil }
        let v = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }
}
