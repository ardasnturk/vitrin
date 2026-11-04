import XCTest
@testable import Vitrin

final class AscWatcherTests: XCTestCase {
    private func states(_ state: String, _ version: String = "1.0") -> [String: AscWatcher.Version] {
        ["1/IOS": .init(appId: "1", name: "Ritim", platform: "IOS", version: version, state: state)]
    }

    func testANewStageIsNews() {
        XCTAssertEqual(AscWatcher.changes(from: states("WAITING_FOR_REVIEW"), to: states("IN_REVIEW")).map(\.state), ["IN_REVIEW"])
        XCTAssertEqual(AscWatcher.changes(from: states("IN_REVIEW"), to: states("REJECTED")).map(\.state), ["REJECTED"])
    }

    func testYourOwnStepsAndStatesBetweenStagesAreQuiet() {
        XCTAssertTrue(AscWatcher.changes(from: states("READY_FOR_SALE"), to: states("PREPARE_FOR_SUBMISSION", "1.1")).isEmpty)
        XCTAssertTrue(AscWatcher.changes(from: states("IN_REVIEW"), to: states("PROCESSING_FOR_DISTRIBUTION")).isEmpty)
        XCTAssertTrue(AscWatcher.changes(from: states("IN_REVIEW"), to: states("IN_REVIEW")).isEmpty)
    }

    func testAMoveInsideOneStageIsToldOnce() {
        XCTAssertTrue(AscWatcher.changes(from: states("ACCEPTED"), to: states("PENDING_DEVELOPER_RELEASE")).isEmpty)
    }

    func testANewReleaseReachingTheSameStageIsNews() {
        XCTAssertEqual(AscWatcher.changes(from: states("READY_FOR_SALE"), to: states("READY_FOR_DISTRIBUTION", "1.1")).count, 1)
    }

    func testAnAppSeenForTheFirstTimeIsNotNews() {
        XCTAssertTrue(AscWatcher.changes(from: [:], to: states("IN_REVIEW")).isEmpty)
    }

    func testRemoteCodeHoldsTheWatchWhileItLooks() {
        let now = Date()
        func record(_ owner: String, age: TimeInterval) -> AscWatcher.Record {
            .init(owner: owner, checkedAt: now.timeIntervalSince1970 - age, states: [:])
        }
        XCTAssertTrue(AscWatcher.remoteCodeIsWatching(record("remote-code", age: 300), now: now))
        XCTAssertFalse(AscWatcher.remoteCodeIsWatching(record("remote-code", age: 900), now: now), "Remote Code stopped: the app takes over")
        XCTAssertFalse(AscWatcher.remoteCodeIsWatching(record("vitrin", age: 10), now: now))
        XCTAssertFalse(AscWatcher.remoteCodeIsWatching(nil, now: now))
    }

    /// Remote Code writes this file with the same keys: RemoteCodeHost/Plugins/AppStateWatcher.swift.
    func testTheFileSurvivesARoundTrip() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/asc-watch.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        AscWatcher.write(states("IN_REVIEW"), to: file)
        XCTAssertEqual(AscWatcher.read(file)?.states, states("IN_REVIEW"))
        XCTAssertEqual(AscWatcher.read(file)?.owner, "vitrin")
        let perms = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int)
        XCTAssertEqual(perms & 0o777, 0o600)
    }

    func testReadsRemoteCodesFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(#"{"owner":"remote-code","checkedAt":1800000000.5,"states":{"1/IOS":{"appId":"1","name":"Ritim","platform":"IOS","version":"1.0","state":"IN_REVIEW"}}}"#.utf8).write(to: file)
        XCTAssertEqual(AscWatcher.read(file)?.states, states("IN_REVIEW"))
    }
}
