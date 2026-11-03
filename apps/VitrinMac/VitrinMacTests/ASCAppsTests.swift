import XCTest
@testable import Vitrin

/// `Fixtures/asc-apps.json` is `vitrin asc apps --json` as the CLI prints it (packages/cli/src/commands/asc.ts).
@MainActor final class ASCAppsTests: XCTestCase {
    private func load() throws -> ASCAppsResult {
        try JSONDecoder().decode(ASCAppsResult.self, from: try TestPaths.fixture("asc-apps"))
    }

    func testDecodesAppsWithTheirCurrentVersions() throws {
        let r = try load()
        XCTAssertEqual(r.apps.map(\.name), ["Acorn", "Ritim", "Zed"])
        let ritim = try XCTUnwrap(r.apps.first { $0.bundleId == "com.jastech.ritim" })
        XCTAssertEqual(ritim.id, "6447000002")
        XCTAssertEqual(ritim.sku, "RITIM1")
        XCTAssertEqual(ritim.primaryLocale, "en-US")
        XCTAssertEqual(ritim.platforms, ["IOS", "MAC_OS"])
        XCTAssertEqual(ritim.versions.count, 2)
        // The sidebar shows the iOS version first.
        XCTAssertEqual(ritim.current?.version, "2.0.0")
        XCTAssertEqual(ritim.current?.state, "PREPARE_FOR_SUBMISSION")
        XCTAssertEqual(ritim.versions[1].createdAt, "2026-10-01T10:00:00Z")
        XCTAssertEqual(ritim.ascURL.absoluteString, "https://appstoreconnect.apple.com/apps/6447000002/distribution")
        // No version yet: nothing to show, nothing crashes.
        let acorn = r.apps[0]
        XCTAssertNil(acorn.current)
        XCTAssertEqual(acorn.platforms, [])
        // A platform other than iOS, with a state the app does not know.
        let zed = r.apps[2]
        XCTAssertEqual(zed.current?.platform, "VISION_OS")
        XCTAssertNil(zed.current?.createdAt)
    }

    func testUnknownKeysAndStatesSurvive() throws {
        var json = try JSONSerialization.jsonObject(with: try TestPaths.fixture("asc-apps")) as! [String: Any]
        json["somethingNew"] = 1
        var apps = json["apps"] as! [[String: Any]]
        apps[1]["icon"] = "https://example.com/icon.png"
        json["apps"] = apps
        let r = try JSONDecoder().decode(ASCAppsResult.self, from: try JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(r.apps.count, 3)
        XCTAssertEqual(ASCWords.state("SOMETHING_NEW"), "Something New", "an unknown state is readable")
        XCTAssertEqual(ASCWords.tone("SOMETHING_NEW"), .neutral)
    }

    func testWordsAndTones() {
        XCTAssertEqual(ASCWords.platform("IOS"), "iOS")
        XCTAssertEqual(ASCWords.platform("MAC_OS"), "macOS")
        XCTAssertEqual(ASCWords.platform("TV_OS"), "tvOS")
        XCTAssertEqual(ASCWords.platform("VISION_OS"), "visionOS")
        XCTAssertEqual(ASCWords.platform("ANDROID"), "ANDROID")
        XCTAssertEqual(ASCWords.tone("READY_FOR_SALE"), .ok)
        XCTAssertEqual(ASCWords.tone("IN_REVIEW"), .info)
        XCTAssertEqual(ASCWords.tone("PREPARE_FOR_SUBMISSION"), .warn)
        XCTAssertEqual(ASCWords.tone("METADATA_REJECTED"), .err)
        XCTAssertNotEqual(ASCWords.state("READY_FOR_SALE"), "ascState.READY_FOR_SALE", "the catalog has the common states")
    }

    func testBundleIdFromProjectConfig() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vitrin-cfg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(ProjectConfigFile.bundleId(inProjectAt: dir.path), "no config, no bundle id")
        let cfg = dir.appendingPathComponent("vitrin.config.yaml")
        try "app:\n  name: Ritim\n  bundleId: com.jastech.ritim # the App Store record\n  locales: [en-US, tr]\nurls: {}\n".write(to: cfg, atomically: true, encoding: .utf8)
        XCTAssertEqual(ProjectConfigFile.bundleId(inProjectAt: dir.path), "com.jastech.ritim")
        try "app:\n  bundleId: \"com.jastech.quoted\"\n".write(to: cfg, atomically: true, encoding: .utf8)
        XCTAssertEqual(ProjectConfigFile.bundleId(inProjectAt: dir.path), "com.jastech.quoted")
        try "app:\n  bundleId:\n  locales: [en-US]\n".write(to: cfg, atomically: true, encoding: .utf8)
        XCTAssertNil(ProjectConfigFile.bundleId(inProjectAt: dir.path), "an empty value is no bundle id")
    }

    func testEnvironmentWithoutAProject() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vitrin-cred-apps-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ASCCredentials(base: dir)
        XCTAssertEqual(store.environment(), [:], "no key, nothing to hand over")
        let p8 = dir.appendingPathComponent("AuthKey_ABC123DEFG.p8")
        try "-----BEGIN PRIVATE KEY-----\nMIGT\n-----END PRIVATE KEY-----\n".write(to: p8, atomically: true, encoding: .utf8)
        try store.save(keyId: "ABC123DEFG", issuerId: "issuer", p8: p8)
        let env = store.environment()
        XCTAssertEqual(env["ASC_KEY_ID"], "ABC123DEFG")
        XCTAssertEqual(env["ASC_ISSUER_ID"], "issuer")
        XCTAssertEqual(env["ASC_KEY_PATH"], store.key?.keyPath)
        // Outside a project there is no .env to defer to; inside one, the project's key still wins.
        let project = dir.appendingPathComponent("app", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "ASC_KEY_ID=PROJECTKEY\n".write(to: project.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        XCTAssertEqual(store.environment(forProject: project.path), [:])
        XCTAssertEqual(store.environment().count, 3)
    }

    func testAppListWithoutAKeyIsEmptyAndQuiet() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vitrin-cred-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let list = ASCAppList()
        await list.refresh(cli: nil, credentials: ASCCredentials(base: dir))
        XCTAssertEqual(list.apps, [])
        XCTAssertNil(list.error)
        XCTAssertFalse(list.loading)
    }
}
