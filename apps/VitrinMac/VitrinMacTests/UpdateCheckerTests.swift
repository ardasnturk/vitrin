import XCTest
@testable import Vitrin

final class UpdateCheckerTests: XCTestCase {
    private func release(assets: [String]) -> UpdateChecker.Release {
        UpdateChecker.Release(tag_name: "v2.2.0", name: nil, html_url: "https://github.com/ardasnturk/vitrin/releases/tag/v2.2.0", published_at: nil, body: nil,
                              assets: assets.map { UpdateChecker.Release.Asset(name: $0, browser_download_url: "https://github.com/\($0)", size: 1) })
    }

    func testAReleaseWaitingForItsDMGIsNotInstallable() {
        XCTAssertFalse(release(assets: ["ardasnturk-vitrin-2.2.0.tgz", "SHA256SUMS"]).isInstallable)
        XCTAssertFalse(release(assets: ["Vitrin-2.2.0.dmg"]).isInstallable, "the checksum is attached a moment after the DMG")
        XCTAssertTrue(release(assets: ["Vitrin-2.2.0.dmg", "Vitrin-2.2.0.dmg.sha256"]).isInstallable)
    }

    func testEqualVersions() {
        XCTAssertEqual(UpdateChecker.compare("1.2.0", "1.2.0"), 0)
        XCTAssertEqual(UpdateChecker.compare("1.2", "1.2.0"), 0, "a missing component counts as 0")
        XCTAssertEqual(UpdateChecker.compare("1", "1.0.0"), 0)
    }

    func testOrdering() {
        XCTAssertEqual(UpdateChecker.compare("1.3.0", "1.2.9"), 1)
        XCTAssertEqual(UpdateChecker.compare("1.2.9", "1.3.0"), -1)
        XCTAssertEqual(UpdateChecker.compare("2.0.0", "1.99.99"), 1)
        XCTAssertEqual(UpdateChecker.compare("1.2.10", "1.2.9"), 1, "numeric, not lexical")
        XCTAssertEqual(UpdateChecker.compare("0.1.0", "0.1.1"), -1)
    }

    func testPrereleaseSuffixIsDropped() {
        XCTAssertEqual(UpdateChecker.compare("1.3.0-beta.1", "1.3.0"), 0)
        XCTAssertEqual(UpdateChecker.compare("1.3.0-rc", "1.2.0"), 1)
    }

    func testGarbageCountsAsZero() {
        XCTAssertEqual(UpdateChecker.compare("x.y", "0.0"), 0)
        XCTAssertEqual(UpdateChecker.compare("", "0"), 0)
    }

    func testReleaseVersionStripsV() throws {
        let json = """
        {"tag_name":"v1.4.0","html_url":"https://example.invalid/r","assets":[{"name":"SHA256SUMS","browser_download_url":"https://example.invalid/s","size":12}]}
        """
        let r = try JSONDecoder().decode(UpdateChecker.Release.self, from: Data(json.utf8))
        XCTAssertEqual(r.version, "1.4.0")
        XCTAssertEqual(r.assets.first?.name, "SHA256SUMS")
    }

    func testAReleaseNamesItsOwnDMGAndChecksum() throws {
        let json = #"{"tag_name":"v2.1.0","html_url":"https://x","assets":[{"name":"ardasnturk-vitrin-2.1.0.tgz","browser_download_url":"https://x/a","size":1},{"name":"Vitrin-2.1.0.dmg","browser_download_url":"https://x/d","size":2},{"name":"Vitrin-2.1.0.dmg.sha256","browser_download_url":"https://x/s","size":3}]}"#
        let release = try JSONDecoder().decode(UpdateChecker.Release.self, from: Data(json.utf8))
        XCTAssertEqual(release.dmg?.browser_download_url, "https://x/d")
        XCTAssertEqual(release.checksum?.browser_download_url, "https://x/s")
    }

    func testTheChecksumFileIsRead() {
        let hash = String(repeating: "a", count: 64)
        XCTAssertEqual(UpdateChecker.digest(from: "\(hash)  dist/Vitrin-2.1.0.dmg\n", fileName: "Vitrin-2.1.0.dmg"), hash)
        XCTAssertEqual(UpdateChecker.digest(from: "\(hash.uppercased())  Vitrin-2.1.0.dmg", fileName: "Vitrin-2.1.0.dmg"), hash)
        XCTAssertNil(UpdateChecker.digest(from: "not a checksum", fileName: "Vitrin-2.1.0.dmg"))
    }
}
