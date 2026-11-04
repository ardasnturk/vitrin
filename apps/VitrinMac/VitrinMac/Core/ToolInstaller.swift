import CryptoKit
import Foundation
import Observation

/// The command-line tools the app needs, each of which it can install by itself.
enum LocalTool: String, CaseIterable, Sendable {
    case node, vitrin, claude, asc, ffmpeg

    var name: String {
        switch self {
        case .node: return "Node.js"
        case .vitrin: return "Vitrin CLI"
        case .claude: return "Claude Code"
        case .asc: return "asc CLI"
        case .ffmpeg: return "ffmpeg"
        }
    }

    var installKey: String {
        switch self {
        case .vitrin: return "cli.install"
        case .asc: return "asc.install"
        case .node, .claude, .ffmpeg: return "tool.install.\(rawValue)"
        }
    }

    /// The tool an install hint from the CLI names; nil for hints that belong to a project (`pod install`).
    init?(hint: String) {
        if hint.contains("claude-code") { self = .claude }
        else if hint.hasSuffix(" asc") { self = .asc }
        else if hint.hasSuffix(" ffmpeg") { self = .ffmpeg }
        else { return nil }
    }
}

/// Installs the tools with no terminal: Homebrew where the Mac has it, and otherwise the tool's own release, checked
/// against its published checksum and kept under the Vitrin folder, which `ShellEnvironment` puts on the PATH. One
/// install runs at a time (brew and npm hold locks), and the state lives here, not in a view, so leaving the page
/// keeps the progress.
@MainActor @Observable final class ToolInstaller {
    enum Failure: LocalizedError {
        case output(String)
        var errorDescription: String? { if case .output(let s) = self { return s } else { return nil } }
    }

    enum VitrinStage: Equatable { case download, packages, browser(Int?) }

    private(set) var running: LocalTool?
    private(set) var status = ""
    private(set) var errors: [LocalTool: String] = [:]
    var busy: Bool { running != nil }

    /// Installs the tools in order; a failure stays on its own tool and the rest still run. `settle` runs after each
    /// one with its spinner still up, so a tool turns green before the next starts and no button comes back meanwhile.
    func install(_ tools: [LocalTool], appVersion: String, settle: () async -> Void) async {
        guard !busy else { return }
        for tool in tools {
            running = tool
            errors[tool] = nil
            status = installing(tool.name)
            do { try await run(tool, appVersion: appVersion) } catch { errors[tool] = error.localizedDescription }
            ShellEnvironment.invalidate()
            await settle()
        }
        running = nil
        status = ""
    }

    private func installing(_ name: String) -> String { L.t("tool.installing").replacingOccurrences(of: "{name}", with: name) }

    private func run(_ tool: LocalTool, appVersion: String) async throws {
        switch tool {
        case .node: try await installNode()
        case .vitrin: try await installVitrin(version: appVersion)
        case .claude: try await installClaude()
        case .asc: try await installAsc()
        case .ffmpeg: try await installFFmpeg()
        }
    }

    // MARK: Node.js

    private func installNode() async throws {
        if await brewInstall("node"), (try? await CLILocator.node()) != nil { return }
        status = installing(LocalTool.node.name)
        try await Self.downloadNode()
    }

    /// The environment with a new enough Node.js first on the PATH, installing it when the Mac has none. First matters:
    /// the launcher and npm take whichever `node` comes first, and that can be an old one further up.
    private func nodeEnvironment() async throws -> [String: String] {
        if (try? await CLILocator.node()) == nil {
            status = installing(LocalTool.node.name)
            try await installNode()
            ShellEnvironment.invalidate()
        }
        let node = try await CLILocator.node()
        var env = await ShellEnvironment.environment()
        env["PATH"] = "\((node as NSString).deletingLastPathComponent):\(env["PATH"] ?? "")"
        return env
    }

    // MARK: Vitrin CLI

    /// The launcher the Claude Code plugin uses, bundled in the app: it verifies the release tarball against the
    /// plugin's checksums, installs it for this user, and fetches Chromium.
    private func installVitrin(version: String) async throws {
        var env = try await nodeEnvironment()
        guard let launcher = Bundle.main.url(forResource: "vitrin", withExtension: nil)?.appendingPathComponent("bin/vitrin") else {
            throw Failure.output("The Vitrin launcher is missing from this app.")
        }
        env["VITRIN_VERSION"] = version
        status = L.t("cli.installing")
        try await execute("/bin/sh", [launcher.path, "--version"], env: env, timeout: 1500) { [weak self] log in
            guard let self else { return }
            switch Self.vitrinStage(log: log) {
            case .download: self.status = L.t("cli.installing")
            case .packages: self.status = L.t("cli.stage.packages")
            case .browser(let percent): self.status = L.t("cli.stage.browser") + (percent.map { " \($0)%" } ?? "")
            }
        }
    }

    nonisolated static func vitrinStage(log: String) -> VitrinStage {
        if let r = log.range(of: "installing Playwright Chromium", options: .backwards) {
            return .browser(log[r.upperBound...].matches(of: /(\d+)%/).last.flatMap { Int($0.output.1) })
        }
        return log.contains("checksum verified") ? .packages : .download
    }

    // MARK: Claude Code

    private func installClaude() async throws {
        let env = try await nodeEnvironment()
        let bin = (try await CLILocator.node() as NSString).deletingLastPathComponent
        var args = ["install", "-g", "--no-fund", "--no-audit", "@anthropic-ai/claude-code"]
        // The nodejs.org installer's global folder belongs to root; a user-owned prefix needs no sudo.
        let global = ((bin as NSString).deletingLastPathComponent as NSString).appendingPathComponent("lib/node_modules")
        if !FileManager.default.isWritableFile(atPath: global) { args += ["--prefix", CLILocator.home] }
        try await execute("\(bin)/npm", args, env: env, timeout: 600)
    }

    // MARK: asc

    private func installAsc() async throws {
        if await brewInstall("asc") { return }
        try await Self.downloadAsc()
    }

    // MARK: ffmpeg

    /// ffmpeg and ffprobe. There is no official macOS build, so without Homebrew they come from the `-static` npm packages.
    private func installFFmpeg() async throws {
        if await brewInstall("ffmpeg") { return }
        let env = try await nodeEnvironment()
        let bin = (try await CLILocator.node() as NSString).deletingLastPathComponent
        let folder = "\(CLILocator.home)/ffmpeg"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try await execute("\(bin)/npm", ["install", "--prefix", folder, "--no-fund", "--no-audit", "ffmpeg-static", "ffprobe-static"], env: env, timeout: 600)
        try Self.link("\(folder)/node_modules/ffmpeg-static/ffmpeg", as: "ffmpeg")
        try Self.link("\(folder)/node_modules/ffprobe-static/bin/darwin/\(Self.arch.node)/ffprobe", as: "ffprobe")
    }

    // MARK: Running

    /// `brew install <formula>`; false when the Mac has no Homebrew or the install failed, and the caller goes on
    /// without it.
    private func brewInstall(_ formula: String) async -> Bool {
        guard let brew = await ShellEnvironment.which("brew") else { return false }
        var env = await ShellEnvironment.environment()
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        return (try? await execute(brew, ["install", formula], env: env, timeout: 900)) != nil
    }

    /// Runs a command with its output in a log file, read twice a second for `watch`. The file, and not a pipe, because
    /// an install is minutes long and `ProcessRunner` hands its pipes back only at the end.
    private func execute(_ executable: String, _ arguments: [String], env: [String: String], timeout: TimeInterval, watch: (@MainActor (String) -> Void)? = nil) async throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("vitrin-install-\(UUID().uuidString).log")
        var env = env
        env["VITRIN_INSTALL_LOG"] = log.path
        defer { try? FileManager.default.removeItem(at: log) }
        let poll = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                if let text = try? String(contentsOf: log, encoding: .utf8) { watch?(text) }
            }
        }
        defer { poll.cancel() }
        let r = try await ProcessRunner.run("/bin/sh", ["-c", #"exec "$@" >"$VITRIN_INSTALL_LOG" 2>&1"#, "sh", executable] + arguments, environment: env, timeout: timeout)
        guard r.code == 0 else {
            let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            throw Failure.output(String(text.trimmingCharacters(in: .whitespacesAndNewlines).suffix(400)))
        }
    }

    // MARK: Releases

    /// The newest LTS at the minimum major or above from nodejs.org's `index.json`, which lists newest first.
    nonisolated static func nodeRelease(index: Data) -> String? {
        struct Entry: Decodable {
            var version: String
            var isLTS: Bool
            private enum CodingKeys: String, CodingKey { case version, lts }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                version = try c.decode(String.self, forKey: .version)
                isLTS = (try? c.decode(String.self, forKey: .lts)) != nil // `false`, or the release line's name
            }
        }
        let entries = (try? JSONDecoder().decode([Entry].self, from: index)) ?? []
        return entries.first { $0.isLTS && (Int($0.version.dropFirst().split(separator: ".").first ?? "") ?? 0) >= CLILocator.minimumNode }?.version
    }

    /// The SHA-256 a checksums file (`<hash>  <file>` per line) records for a file.
    nonisolated static func checksum(of file: String, in sums: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            if parts.count == 2, parts[1] == Substring(file) { return parts[0].lowercased() }
        }
        return nil
    }

    private nonisolated static var arch: (node: String, asc: String) {
        #if arch(arm64)
        return ("arm64", "arm64")
        #else
        return ("x64", "amd64")
        #endif
    }

    /// A release of Node.js into `<root>/node`; `root` is the Vitrin folder outside the tests.
    nonisolated static func downloadNode(root: String = CLILocator.home) async throws {
        let fm = FileManager.default
        guard let version = nodeRelease(index: try await fetch("https://nodejs.org/dist/index.json")) else { throw Failure.output("No Node.js release found on nodejs.org.") }
        let file = "node-\(version)-darwin-\(arch.node).tar.gz"
        let base = "https://nodejs.org/dist/\(version)"
        let sums = String(decoding: try await fetch("\(base)/SHASUMS256.txt"), as: UTF8.self)
        let tarball = try await download("\(base)/\(file)", expected: checksum(of: file, in: sums))
        defer { try? fm.removeItem(at: tarball) }
        let stage = "\(root)/.node.tmp"
        try? fm.removeItem(atPath: stage)
        try fm.createDirectory(atPath: stage, withIntermediateDirectories: true)
        let r = try await ProcessRunner.run("/usr/bin/tar", ["-xzf", tarball.path, "-C", stage, "--strip-components=1"], environment: ProcessInfo.processInfo.environment, timeout: 180)
        guard r.code == 0 else { try? fm.removeItem(atPath: stage); throw Failure.output(r.stderr) }
        try? fm.removeItem(atPath: "\(root)/node")
        try fm.moveItem(atPath: stage, toPath: "\(root)/node")
    }

    /// The latest asc release binary into `<root>/bin`.
    nonisolated static func downloadAsc(root: String = CLILocator.home) async throws {
        struct Release: Decodable { var tag_name: String }
        let fm = FileManager.default
        let repo = "rorkai/App-Store-Connect-CLI"
        let tag = try JSONDecoder().decode(Release.self, from: try await fetch("https://api.github.com/repos/\(repo)/releases/latest")).tag_name
        let base = "https://github.com/\(repo)/releases/download/\(tag)"
        let file = "asc_\(tag)_macOS_\(arch.asc)"
        let sums = String(decoding: try await fetch("\(base)/asc_\(tag)_checksums.txt"), as: UTF8.self)
        let binary = try await download("\(base)/\(file)", expected: checksum(of: file, in: sums))
        defer { try? fm.removeItem(at: binary) }
        try fm.createDirectory(atPath: "\(root)/bin", withIntermediateDirectories: true)
        try? fm.removeItem(atPath: "\(root)/bin/asc")
        try fm.moveItem(at: binary, to: URL(fileURLWithPath: "\(root)/bin/asc"))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: "\(root)/bin/asc")
    }

    private nonisolated static func link(_ target: String, as name: String) throws {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: target) else { throw Failure.output("\(target) was not installed.") }
        let bin = "\(CLILocator.home)/bin"
        try fm.createDirectory(atPath: bin, withIntermediateDirectories: true)
        try? fm.removeItem(atPath: "\(bin)/\(name)")
        try fm.createSymbolicLink(atPath: "\(bin)/\(name)", withDestinationPath: target)
    }

    private nonisolated static func request(_ url: String) throws -> URLRequest {
        guard let u = URL(string: url) else { throw Failure.output("Bad URL: \(url)") }
        var req = URLRequest(url: u)
        req.setValue("VitrinMac", forHTTPHeaderField: "user-agent")
        return req
    }

    private nonisolated static func check(_ response: URLResponse, _ url: String) throws {
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw Failure.output("\(url): HTTP \(http.statusCode)") }
    }

    private nonisolated static func fetch(_ url: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: try request(url))
        try check(response, url)
        return data
    }

    /// Downloads to a temporary file that matches `expected`. A file with no recorded checksum is not used.
    private nonisolated static func download(_ url: String, expected: String?) async throws -> URL {
        guard let expected else { throw Failure.output("\(url): no checksum published, so nothing was installed.") }
        let (file, response) = try await URLSession.shared.download(for: try request(url))
        do {
            try check(response, url)
            let actual = SHA256.hash(data: try Data(contentsOf: file, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else { throw Failure.output("\(url): the checksum does not match, so nothing was installed.") }
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        return file
    }
}
