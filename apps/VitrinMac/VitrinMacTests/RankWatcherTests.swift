import XCTest
@testable import Vitrin

final class RankWatcherTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_880_000) // 2026-11-05 UTC

    private func due(_ newest: String?, _ schedule: RankSchedule = .daily, attempt: Date? = nil) -> Bool {
        RankWatcher.isDue(newest: newest, schedule: schedule, lastAttempt: attempt, now: now)
    }

    func testFollowsTheSchedule() {
        XCTAssertTrue(due("2026-11-03"))
        XCTAssertFalse(due("2026-11-05"))
        XCTAssertFalse(due("2026-11-01", .weekly))
        XCTAssertTrue(due("2026-10-28", .weekly))
        XCTAssertFalse(due("2026-10-01", .off))
    }

    func testNeverStartsAProjectNobodyMeasured() {
        XCTAssertFalse(due(nil))
    }

    func testAFailedCheckWaitsBeforeTryingAgain() {
        XCTAssertFalse(due("2026-11-01", attempt: now.addingTimeInterval(-3600)))
        XCTAssertTrue(due("2026-11-01", attempt: now.addingTimeInterval(-7 * 3600)))
    }

    func testFindsTheNewestSnapshotAndIgnoresOtherFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("metadata/rankings")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["2026-10-01.json", "2026-11-02.json", "notes.json", "2026-12-01.txt"] {
            try Data("{}".utf8).write(to: folder.appendingPathComponent(name))
        }
        XCTAssertEqual(RankWatcher.newestSnapshot(in: root.path), "2026-11-02")
        XCTAssertNil(RankWatcher.newestSnapshot(in: "/nonexistent"))
    }

    @MainActor func testTellsTheBiggestNewsOnly() throws {
        let json = #"{ "date": "2026-11-05", "previous": "2026-11-04", "highlights": { "up": 2, "down": 0, "enteredTop10": [{ "locale": "en-US", "term": "habit", "before": 12, "after": 8, "delta": 4 }], "leftTop10": [{ "term": "sleep", "before": 9, "after": null, "delta": null }] } }"#
        let r = try JSONDecoder().decode(RankWatcher.Result.self, from: Data(json.utf8))
        XCTAssertTrue(try XCTUnwrap(RankWatcher.message(r.highlights)).contains("habit"))
        XCTAssertNotNil(RankWatcher.message(.init(up: 1, down: 0, enteredTop10: [], leftTop10: [])))
    }

    @MainActor func testQuietWithoutNews() {
        XCTAssertNil(RankWatcher.message(nil))
        XCTAssertNil(RankWatcher.message(.init(up: 0, down: 0, enteredTop10: [], leftTop10: [])))
    }
}
