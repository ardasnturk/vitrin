import XCTest
@testable import Vitrin

/// Starts the real CLI (`packages/cli/dist/bin.js`) on examples/Ritim and talks to it the way the app does.
/// Skipped when the CLI is not built.
@MainActor
final class StudioHandshakeTests: XCTestCase {
    private var process: Process?
    private var tokenFile: URL?

    override func setUp() async throws {
        try TestPaths.requireCLI()
    }

    override func tearDown() async throws {
        if let p = process, p.isRunning { p.terminate(); p.waitUntilExit() }
        process = nil
        if let tokenFile { try? FileManager.default.removeItem(at: tokenFile.deletingLastPathComponent()) }
    }

    private func node() async throws -> String {
        do { return try await CLILocator.node() } catch { throw XCTSkip("Node.js 22+ not found: \(error.localizedDescription)") }
    }

    /// A plain `Process`, so the CLI's own handshake and cleanup are what is tested.
    private func startCLI() async throws -> StudioHandshake {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vitrin-mac-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("studio.json")
        tokenFile = file
        var env = await ShellEnvironment.environment()
        env["NO_COLOR"] = "1"
        env["FORCE_COLOR"] = "0"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: try await node())
        p.arguments = [TestPaths.cliBin.path, "--cwd", TestPaths.ritim.path, "studio", "--no-open", "--port", "0", "--token-file", file.path]
        p.environment = env
        p.currentDirectoryURL = TestPaths.ritim
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        try p.run()
        process = p
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if !p.isRunning { XCTFail("vitrin studio exited with \(p.terminationStatus) before writing the handshake"); throw XCTSkip("CLI exited") }
            if let data = try? Data(contentsOf: file), let h = try? JSONDecoder().decode(StudioHandshake.self, from: data) { return h }
            try await Task.sleep(for: .milliseconds(150))
        }
        XCTFail("no handshake within 90 s")
        throw XCTSkip("no handshake")
    }

    func testHandshakeOverviewTokenAndShutdown() async throws {
        let h = try await startCLI()
        XCTAssertTrue(h.url.hasPrefix("http://127.0.0.1:"), h.url)
        XCTAssertEqual(h.root, TestPaths.ritim.standardizedFileURL.path)
        XCTAssertEqual(h.pid, Int(process!.processIdentifier))
        XCTAssertFalse(h.token.isEmpty)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: tokenFile!.path), let perms = attrs[.posixPermissions] as? Int {
            XCTAssertEqual(perms & 0o777, 0o600, "the handshake is readable by its owner only")
        }

        let client = StudioClient(handshake: h)
        let overview = try await client.overview()
        XCTAssertEqual(overview.app?.name, "Ritim")
        XCTAssertEqual(overview.config?.locales, ["en-US", "tr"])
        XCTAssertEqual(overview.flow.count, 11)
        XCTAssertEqual(overview.root, h.root)

        // A POST without the session token is refused.
        var req = URLRequest(url: client.url("/api/jobs"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = Data(#"{"command":"nope","args":{}}"#.utf8)
        let (body, response) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 403)
        XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("token"))

        // With the token, an unknown command is accepted (202) and the job fails with "Unknown command".
        let started = try await client.run("nope")
        XCTAssertEqual(started.command, "nope")
        var job = try await client.job(started.id)
        let deadline = Date().addingTimeInterval(30)
        while job.status == "running", Date() < deadline {
            try await Task.sleep(for: .milliseconds(200))
            job = try await client.job(started.id)
        }
        XCTAssertEqual(job.status, "failed")
        XCTAssertEqual(job.code, 1)
        XCTAssertTrue(job.message?.contains("Unknown command") == true, job.message ?? "nil")
        let jobs = try await client.jobs()
        XCTAssertTrue(jobs.contains { $0.id == started.id })

        // The 202 itself, raw, so the status code is asserted and not only the decoded body.
        var accepted = URLRequest(url: client.url("/api/jobs"))
        accepted.httpMethod = "POST"
        accepted.setValue(h.token, forHTTPHeaderField: "x-vitrin-token")
        accepted.setValue("application/json", forHTTPHeaderField: "content-type")
        accepted.httpBody = Data(#"{"command":"nope","args":{}}"#.utf8)
        let (_, acceptedResponse) = try await URLSession.shared.data(for: accepted)
        XCTAssertEqual((acceptedResponse as? HTTPURLResponse)?.statusCode, 202)

        // SIGTERM stops the server and removes the handshake.
        let p = process!
        p.terminate()
        let exitDeadline = Date().addingTimeInterval(20)
        while p.isRunning, Date() < exitDeadline { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(p.isRunning, "the CLI did not exit on SIGTERM")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tokenFile!.path), "the token file remained after SIGTERM")
        process = nil
    }

    /// The app's own wrapper: `StudioProcess` runs the CLI, reaches `.running`, and `stop()` returns to `.stopped`.
    func testStudioProcessStartsAndStops() async throws {
        let cli = CLILocation(kind: .checkout, executable: try await node(), leadingArguments: [TestPaths.cliBin.path], version: nil)
        let studio = StudioProcess()
        XCTAssertEqual(studio.state, .stopped)
        let h = try await studio.start(root: TestPaths.ritim.path, cli: cli)
        XCTAssertTrue(studio.isRunning)
        XCTAssertEqual(studio.handshake?.url, h.url)
        let overview = try await StudioClient(handshake: h).overview()
        XCTAssertEqual(overview.app?.name, "Ritim")
        // A second start returns the same handshake without a second process.
        let again = try await studio.start(root: TestPaths.ritim.path, cli: cli)
        XCTAssertEqual(again.token, h.token)
        studio.stop()
        XCTAssertEqual(studio.state, .stopped)
        XCTAssertNil(studio.handshake)
        // The server is gone shortly after.
        let deadline = Date().addingTimeInterval(15)
        var reachable = true
        while reachable, Date() < deadline {
            do { _ = try await StudioClient(handshake: h).overview() } catch { reachable = false }
            if reachable { try await Task.sleep(for: .milliseconds(250)) }
        }
        XCTAssertFalse(reachable, "the Studio still answered after stop()")
    }
}
