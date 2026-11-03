import XCTest
@testable import Vitrin

final class UpdateCheckerTests: XCTestCase {
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
}
