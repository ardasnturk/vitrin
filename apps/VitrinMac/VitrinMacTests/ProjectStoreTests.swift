import XCTest
@testable import Vitrin

/// The project list is one file with two writers: this app and `vitrin hub`, which adds projects from the phone.
@MainActor final class ProjectStoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("vitrin-projects-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// As the hub saves it: a whole new file renamed into place.
    private func writeFromHub(_ path: String) throws {
        let list = [Project(id: UUID().uuidString, path: path, addedAt: .now)]
        let temporary = dir.appendingPathComponent("projects.json.1.tmp")
        try JSONEncoder().encode(list).write(to: temporary)
        _ = try FileManager.default.replaceItemAt(dir.appendingPathComponent("projects.json"), withItemAt: temporary)
    }

    func testShowsAProjectAddedFromThePhoneWhileRunning() async throws {
        let store = ProjectStore(base: dir)
        XCTAssertTrue(store.projects.isEmpty)
        try writeFromHub("/tmp/from-phone")
        for _ in 0..<40 where store.projects.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(store.projects.map(\.path), ["/tmp/from-phone"])
    }

    func testAddingKeepsAProjectTheHubJustWrote() throws {
        let store = ProjectStore(base: dir)
        try writeFromHub("/tmp/from-phone")
        store.add(path: "/tmp/from-mac")
        XCTAssertEqual(store.projects.map(\.path), ["/tmp/from-phone", "/tmp/from-mac"])
        XCTAssertEqual(ProjectStore(base: dir).projects.map(\.path), ["/tmp/from-phone", "/tmp/from-mac"])
    }
}
