import Foundation

struct ProcessResult: Sendable {
    var code: Int32
    var stdout: String
    var stderr: String
}

/// Runs a process to completion with a timeout; stdout and stderr are collected, never shown raw to the user.
///
/// The exit is observed through `terminationHandler`, not `waitUntilExit()`: the latter runs a run loop on whatever
/// thread calls it and, on a cooperative-pool thread, has been seen to miss the exit of a short-lived child (the app
/// then sat on "looking for the CLI" for ever). A child that outlives the timeout gets SIGTERM, then SIGKILL. The
/// pipes are read on their own tasks; when a grandchild keeps a pipe open after the child exited (a login shell's
/// background jobs), the read ends are closed after a grace period so the call still returns.
enum ProcessRunner {
    static func run(_ executable: String, _ arguments: [String], environment: [String: String], cwd: String? = nil, timeout: TimeInterval = 120) async throws -> ProcessResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        p.environment = environment
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        let outTask = Task.detached { (try? out.fileHandleForReading.readToEnd()) ?? Data() }
        let errTask = Task.detached { (try? err.fileHandleForReading.readToEnd()) ?? Data() }

        let code: Int32 = try await withCheckedThrowingContinuation { cont in
            p.terminationHandler = { proc in cont.resume(returning: proc.terminationStatus) }
            do {
                try p.run()
            } catch {
                p.terminationHandler = nil
                cont.resume(throwing: error)
                return
            }
            let pid = p.processIdentifier
            Task.detached {
                try? await Task.sleep(for: .seconds(timeout))
                guard p.isRunning else { return }
                kill(pid, SIGTERM)
                try? await Task.sleep(for: .seconds(3))
                if p.isRunning { kill(pid, SIGKILL) }
            }
        }

        // The child is gone; give its output a moment, then stop waiting for a pipe something else still holds.
        let closer = Task.detached {
            try? await Task.sleep(for: .seconds(2))
            try? out.fileHandleForReading.close()
            try? err.fileHandleForReading.close()
        }
        let o = await outTask.value, e = await errTask.value
        closer.cancel()
        try? out.fileHandleForReading.close()
        try? err.fileHandleForReading.close()
        return ProcessResult(code: code, stdout: String(decoding: o, as: UTF8.self), stderr: String(decoding: e, as: UTF8.self))
    }
}

/// The CLI as a command line: `vitrin <cmd> --json`, with the exit codes read as the CLI defines them (0 ok, 1 failed, 2 needs input).
struct CLIRunner: Sendable {
    enum Outcome: Sendable { case ok, failed, needsInput }
    var location: CLILocation

    func run(_ args: [String], cwd: String? = nil, timeout: TimeInterval = 300) async throws -> (outcome: Outcome, result: ProcessResult) {
        var env = await ShellEnvironment.environment()
        env["FORCE_COLOR"] = "0"
        env["NO_COLOR"] = "1"
        let r = try await ProcessRunner.run(location.executable, location.leadingArguments + args, environment: env, cwd: cwd, timeout: timeout)
        let outcome: Outcome = r.code == 0 ? .ok : r.code == 2 ? .needsInput : .failed
        return (outcome, r)
    }

    /// `vitrin <cmd> --json` decoded; the JSON block is the last object on stdout (warnings go to stderr).
    func json<T: Decodable>(_ args: [String], as type: T.Type, cwd: String? = nil, timeout: TimeInterval = 300) async throws -> (outcome: Outcome, value: T?, result: ProcessResult) {
        let (outcome, r) = try await run(args + ["--json"], cwd: cwd, timeout: timeout)
        guard let start = r.stdout.firstIndex(of: "{") ?? r.stdout.firstIndex(of: "[") else { return (outcome, nil, r) }
        let data = Data(r.stdout[start...].utf8)
        return (outcome, try? JSONDecoder().decode(T.self, from: data), r)
    }
}

/// `vitrin doctor --tools --json`: the local tools, no keys, no network.
struct DoctorCheck: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var status: String
    var detail: String?
    var fix: String?
}

struct DoctorResult: Codable, Sendable {
    struct MissingKey: Codable, Hashable, Sendable {
        var name: String
        var location: String
        private enum CodingKeys: String, CodingKey { case name, location = "where" }
    }
    var checks: [DoctorCheck]
    var missingKeys: [MissingKey]
    var exitCode: Int?
}

/// `vitrin uploader --json`: what is installed for App Store uploads.
struct UploaderReport: Codable, Sendable {
    struct Option: Codable, Hashable, Identifiable, Sendable {
        var uploader: String
        var label: String
        var installed: Bool
        var install: String
        var note: String
        var warning: String?
        var id: String { uploader }
    }
    var chosen: String?
    var tools: Tools
    var options: [Option]
    var recommended: String?
}
