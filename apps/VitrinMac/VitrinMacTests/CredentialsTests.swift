import XCTest
@testable import Vitrin

/// The account key: stored owner-only, handed to a project's Studio unless the project's own .env names a key.
@MainActor final class CredentialsTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vitrin-cred-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func writeP8(_ name: String = "AuthKey_ABC123DEFG.p8", body: String = "-----BEGIN PRIVATE KEY-----\nMIGT\n-----END PRIVATE KEY-----\n") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testSaveCopiesTheKeyOwnerOnlyAndSurvivesReload() throws {
        let store = ASCCredentials(base: dir)
        XCTAssertFalse(store.isSet)
        let p8 = try writeP8()
        try store.save(keyId: " ABC123DEFG ", issuerId: "69a6de7f-0000-47e3-e053-5b8c7c11a4d1", p8: p8)
        let k = try XCTUnwrap(store.key)
        XCTAssertEqual(k.keyId, "ABC123DEFG")
        XCTAssertEqual(k.keyPath, dir.appendingPathComponent("keys/AuthKey_ABC123DEFG.p8").path)
        // The original stays; the copy and the ids are readable by the owner only.
        XCTAssertTrue(FileManager.default.fileExists(atPath: p8.path))
        let perms = { (p: String) in (try? FileManager.default.attributesOfItem(atPath: p)[.posixPermissions] as? Int) ?? -1 }
        XCTAssertEqual(perms(k.keyPath), 0o600)
        XCTAssertEqual(perms(dir.appendingPathComponent("credentials.json").path), 0o600)
        XCTAssertEqual(ASCCredentials(base: dir).key, k)
        store.clear()
        XCTAssertNil(store.key)
        XCTAssertFalse(FileManager.default.fileExists(atPath: k.keyPath))
        XCTAssertNil(ASCCredentials(base: dir).key)
    }

    func testSaveRefusesIncompleteOrWrongFiles() throws {
        let store = ASCCredentials(base: dir)
        let p8 = try writeP8()
        XCTAssertThrowsError(try store.save(keyId: "", issuerId: "x", p8: p8))
        let png = try writeP8("key.png", body: "PNG")
        XCTAssertThrowsError(try store.save(keyId: "ABC", issuerId: "x", p8: png))
        XCTAssertNil(store.key)
    }

    func testProjectsOwnEnvWins() throws {
        let store = ASCCredentials(base: dir)
        let project = dir.appendingPathComponent("app", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        XCTAssertEqual(store.environment(forProject: project.path), [:], "no key stored, nothing to hand over")
        try store.save(keyId: "ABC123DEFG", issuerId: "issuer", p8: try writeP8())
        let env = store.environment(forProject: project.path)
        XCTAssertEqual(env["ASC_KEY_ID"], "ABC123DEFG")
        XCTAssertEqual(env["ASC_ISSUER_ID"], "issuer")
        XCTAssertEqual(env["ASC_KEY_PATH"], store.key?.keyPath)
        // An empty or commented value in .env does not count as the project's own key.
        try "# ASC_KEY_ID=OLD\nASC_KEY_ID=\nAPPTWEAK_API_KEY=x\n".write(to: project.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        XCTAssertEqual(store.environment(forProject: project.path).count, 3)
        try "export ASC_KEY_ID=\"PROJECTKEY\"\n".write(to: project.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        XCTAssertEqual(store.environment(forProject: project.path), [:], "the project's key stays the project's")
    }

    func testDotenvNames() throws {
        let f = dir.appendingPathComponent(".env")
        try "A=1\n  B = 'two' \nexport C=3\nD=\n#E=5\nnot a line\n".write(to: f, atomically: true, encoding: .utf8)
        XCTAssertEqual(ASCCredentials.dotenvNames(at: f), ["A", "B", "C"])
        XCTAssertEqual(ASCCredentials.dotenvNames(at: dir.appendingPathComponent("missing")), [])
    }

    func testModelShortName() {
        XCTAssertEqual(ClaudeModel.shortName("claude-opus-5-5"), "opus 5.5")
        XCTAssertEqual(ClaudeModel.shortName("claude-fable-5-1"), "fable 5.1")
        XCTAssertEqual(ClaudeModel.shortName("opus"), "opus")
        XCTAssertEqual(ClaudeModel.shortName("claude-sonnet-4-5-20250929"), "sonnet 4.5.20250929")
    }
}
