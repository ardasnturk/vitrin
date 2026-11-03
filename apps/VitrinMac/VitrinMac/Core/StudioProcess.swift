import Foundation
import Observation

/// One `vitrin studio --no-open --port 0 --token-file …` process for a project. The handshake file gives the URL and the
/// session token; the process is stopped with SIGTERM (the CLI removes the file and closes its server).
@MainActor @Observable final class StudioProcess {
    enum State: Equatable {
        case stopped, starting, running(StudioHandshake), failed(String)
        static func == (a: State, b: State) -> Bool {
            switch (a, b) {
            case (.stopped, .stopped), (.starting, .starting): return true
            case (.running(let x), .running(let y)): return x.url == y.url && x.token == y.token
            case (.failed(let x), .failed(let y)): return x == y
            default: return false
            }
        }
    }
    private(set) var state: State = .stopped
    /// The CLI's own stdout/stderr tail, for the failure message.
    private(set) var output: [String] = []
    private var process: Process?
    private var tokenFile: URL?

    var handshake: StudioHandshake? { if case .running(let h) = state { return h }; return nil }
    var isRunning: Bool { handshake != nil }

    func start(root: String, cli: CLILocation) async throws -> StudioHandshake {
        if let h = handshake { return h }
        state = .starting
        output = []
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vitrin-mac", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = dir.appendingPathComponent("studio-\(UUID().uuidString).json")
        tokenFile = file
        try? FileManager.default.removeItem(at: file)

        var env = await ShellEnvironment.environment()
        env["FORCE_COLOR"] = "0"
        env["NO_COLOR"] = "1"
        env["BROWSER"] = "none"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: cli.executable)
        p.arguments = cli.leadingArguments + ["--cwd", root, "studio", "--no-open", "--port", "0", "--token-file", file.path]
        p.environment = env
        p.currentDirectoryURL = URL(fileURLWithPath: root)
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        let append: @Sendable (Data) -> Void = { [weak self] data in
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.appendOutput(text) }
        }
        out.fileHandleForReading.readabilityHandler = { h in append(h.availableData) }
        err.fileHandleForReading.readabilityHandler = { h in append(h.availableData) }
        p.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in self?.processEnded(code: code) }
        }
        do {
            try p.run()
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
        process = p
        // The CLI writes the handshake once its server listens; the first start also loads Playwright etc.
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if case .failed(let msg) = state { throw CLIError.failed(msg) }
            if let data = try? Data(contentsOf: file), let h = try? JSONDecoder().decode(StudioHandshake.self, from: data) {
                state = .running(h)
                return h
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        stop()
        let msg = "The Studio did not start within 90 seconds.\n" + output.suffix(10).joined(separator: "\n")
        state = .failed(msg)
        throw CLIError.failed(msg)
    }

    func stop() {
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        if let tokenFile { try? FileManager.default.removeItem(at: tokenFile) }
        state = .stopped
    }

    private func appendOutput(_ text: String) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            output.append(String(line))
        }
        if output.count > 200 { output.removeFirst(output.count - 200) }
    }

    private func processEnded(code: Int32) {
        process = nil
        if let tokenFile { try? FileManager.default.removeItem(at: tokenFile) }
        switch state {
        case .stopped: break
        default:
            let tail = output.suffix(8).joined(separator: "\n")
            state = .failed(code == 0 || code == 15 ? "" : "vitrin studio exited with code \(code).\n\(tail)")
            if case .failed("") = state { state = .stopped }
        }
    }
}
