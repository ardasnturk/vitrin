import XCTest
@testable import Vitrin

final class ToolInstallerTests: XCTestCase {
    func testTheHintsFromTheCLINameTheirTool() {
        XCTAssertEqual(LocalTool(hint: "npm install -g @anthropic-ai/claude-code"), .claude)
        XCTAssertEqual(LocalTool(hint: "brew install asc"), .asc)
        XCTAssertEqual(LocalTool(hint: "brew install ffmpeg"), .ffmpeg)
        XCTAssertNil(LocalTool(hint: "bundle install"))
    }

    func testTheNewestLTSAtTheMinimumMajorIsPicked() {
        let index = #"[{"version":"v27.1.0","lts":false},{"version":"v24.11.0","lts":"Krypton"},{"version":"v22.20.0","lts":"Jod"}]"#
        XCTAssertEqual(ToolInstaller.nodeRelease(index: Data(index.utf8)), "v24.11.0")
        XCTAssertNil(ToolInstaller.nodeRelease(index: Data(#"[{"version":"v20.1.0","lts":"Iron"}]"#.utf8)))
    }

    func testAChecksumIsReadForItsOwnFileOnly() {
        let sums = "ABC123  asc_6.4.0_macOS_arm64\ndef456  asc_6.4.0_macOS_amd64\n"
        XCTAssertEqual(ToolInstaller.checksum(of: "asc_6.4.0_macOS_arm64", in: sums), "abc123")
        XCTAssertNil(ToolInstaller.checksum(of: "asc_6.4.0_macOS", in: sums))
    }

    func testTheInstallStageComesFromTheLauncherLog() {
        XCTAssertEqual(ToolInstaller.vitrinStage(log: "vitrin: downloading https://x"), .download)
        XCTAssertEqual(ToolInstaller.vitrinStage(log: "vitrin: checksum verified (abc)"), .packages)
        XCTAssertEqual(ToolInstaller.vitrinStage(log: "vitrin: installing Playwright Chromium (renders the screenshots)…"), .browser(nil))
        XCTAssertEqual(ToolInstaller.vitrinStage(log: "100% of 2 MiB\nvitrin: installing Playwright Chromium (x)…\n|■■ | 20% of 160 MiB\n|■■■■ | 40% of 160 MiB\n"), .browser(40))
    }

    /// The real downloads, for the Mac with no Homebrew: `VITRIN_NETWORK_TESTS=1`, into a temporary folder.
    func testTheReleasesInstallWithoutHomebrew() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["VITRIN_NETWORK_TESTS"] == "1")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: root) }
        try await ToolInstaller.downloadNode(root: root)
        let node = try await ProcessRunner.run("\(root)/node/bin/node", ["--version"], environment: [:])
        XCTAssertEqual(node.code, 0)
        print("node", node.stdout)
        try await ToolInstaller.downloadAsc(root: root)
        let asc = try await ProcessRunner.run("\(root)/bin/asc", ["--version"], environment: [:])
        XCTAssertEqual(asc.code, 0, asc.stderr)
        print("asc", asc.stdout)
    }
}
