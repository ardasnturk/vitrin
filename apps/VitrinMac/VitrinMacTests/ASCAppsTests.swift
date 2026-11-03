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
        XCTAssertEqual(ritim.versions[1].platform, "MAC_OS")
        XCTAssertEqual(ritim.ascURL.absoluteString, "https://appstoreconnect.apple.com/apps/6447000002/distribution")
        // No version yet: nothing to show, nothing crashes.
        let acorn = r.apps[0]
        XCTAssertNil(acorn.current)
        XCTAssertEqual(acorn.platforms, [])
        // A platform other than iOS, with a state the app does not know.
        let zed = r.apps[2]
        XCTAssertEqual(zed.current?.platform, "VISION_OS")
        XCTAssertEqual(zed.current?.state, "SOMETHING_NEW")
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

    /// The list comes from asc's raw `GET /v1/apps` with the versions included: newest version number per platform,
    /// iOS first, names sorted; an app without versions stays in the list.
    func testAppListFromTheJSONAPIDocument() throws {
        let doc = try JSONDecoder().decode(JSONValue.self, from: Data(#"""
        {"data":[
          {"type":"apps","id":"2","attributes":{"name":"Zed","bundleId":"com.z","sku":"Z","primaryLocale":"tr"},"relationships":{"appStoreVersions":{"data":[{"type":"appStoreVersions","id":"a"},{"type":"appStoreVersions","id":"b"},{"type":"appStoreVersions","id":"c"}]}}},
          {"type":"apps","id":"1","attributes":{"name":"Acorn","bundleId":"com.a","sku":"A","primaryLocale":"en-US"},"relationships":{"appStoreVersions":{"data":[]}}}
        ],"included":[
          {"type":"appStoreVersions","id":"a","attributes":{"platform":"IOS","versionString":"1.9","appVersionState":"READY_FOR_DISTRIBUTION"}},
          {"type":"appStoreVersions","id":"b","attributes":{"platform":"IOS","versionString":"1.10","appVersionState":"PREPARE_FOR_SUBMISSION"}},
          {"type":"appStoreVersions","id":"c","attributes":{"platform":"MAC_OS","versionString":"2.0","appStoreState":"IN_REVIEW"}}
        ]}
        """#.utf8))
        let apps = ASCAppList.apps(from: doc)
        XCTAssertEqual(apps.map(\.name), ["Acorn", "Zed"])
        XCTAssertEqual(apps[0].versions, [])
        XCTAssertEqual(apps[1].versions.map(\.version), ["1.10", "2.0"])
        XCTAssertEqual(apps[1].current?.state, "PREPARE_FOR_SUBMISSION")
        XCTAssertEqual(apps[1].versions[1].state, "IN_REVIEW")
        XCTAssertEqual(apps[1].platforms, ["IOS", "MAC_OS"])
        XCTAssertEqual(ASCAppList.compareVersions("1.0", "1.0.0"), 0)
        XCTAssertEqual(ASCAppList.compareVersions("2.0", "1.99.1"), 1)
    }

    /// asc's help layout, parsed into the command palette's groups, subcommands and flags.
    func testAscHelpParsing() {
        let root = AscHelp.parse("""
        DESCRIPTION
          asc is a CLI.

        USAGE
          asc <subcommand> [flags]

        APP MANAGEMENT COMMANDS
          apps:      List and manage apps.
          versions:  Manage App Store versions.

        FLAGS
          --debug        Enable debug logging (default: false)
        """)
        XCTAssertEqual(root.description, "asc is a CLI.")
        XCTAssertEqual(root.groups.map(\.title), ["APP MANAGEMENT COMMANDS"])
        XCTAssertEqual(root.subcommands.map(\.name), ["apps", "versions"])
        let leaf = AscHelp.parse("""
        DESCRIPTION
          Create a response.

        USAGE
          asc reviews respond [flags]

        FLAGS
          --output       Output format: json, table, markdown (default: json)
          --response     Response body text (required)
          --pretty       Pretty-print JSON output (default: false)
        """)
        XCTAssertEqual(leaf.usage, "asc reviews respond [flags]")
        XCTAssertEqual(leaf.flags.map(\.name), ["output", "response", "pretty"])
        XCTAssertTrue(leaf.flags[1].required)
        XCTAssertTrue(leaf.flags[2].isBool)
        XCTAssertEqual(leaf.flags[0].defaultValue, "json")
        XCTAssertFalse(leaf.flags[0].isBool)
    }
}
