import XCTest
@testable import Vitrin

@MainActor final class AscCacheTests: XCTestCase {
    private let args = ["versions", "list", "--app", "1"]
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func cache(account: String? = "KEY") -> AscCache {
        let c = AscCache(directory: folder)
        c.account = account
        return c
    }

    /// Every result `read` delivers, and how many times it asked App Store Connect.
    private func read(_ cache: AscCache, _ args: [String]? = nil, force: Bool = false, answer: Result<JSONValue, Error> = .success("new")) async throws -> (shown: [JSONValue], requests: Int) {
        var shown: [JSONValue] = []
        var requests = 0
        try await cache.read(args ?? self.args, force: force, fetch: { requests += 1; return try answer.get() }, deliver: { shown.append($0.doc) })
        return (shown, requests)
    }

    private func old(_ age: TimeInterval = 24 * 3600) -> AscCache.Entry { AscCache.Entry(fetchedAt: .now.addingTimeInterval(-age), doc: "old") }

    func testAFreshResultNeedsNoRequest() async throws {
        let c = cache()
        let first = try await read(c)
        let second = try await read(c)
        XCTAssertEqual(first.requests, 1)
        XCTAssertEqual(second.requests, 0)
        XCTAssertEqual(second.shown, ["new"])
    }

    func testAnOldResultShowsFirstAndIsReadAgain() async throws {
        let c = cache()
        await c.save(old(), for: args)
        let r = try await read(c)
        XCTAssertEqual(r.shown, ["old", "new"])
        XCTAssertEqual(r.requests, 1)
    }

    func testAFailedReadLeavesWhatIsShowing() async throws {
        let c = cache()
        await c.save(old(), for: args)
        let r = try await read(c, answer: .failure(AscCLI.Failure(message: "offline")))
        XCTAssertEqual(r.shown, ["old"])
    }

    func testAFailedReadWithNothingStoredThrows() async {
        do {
            _ = try await read(cache(), answer: .failure(AscCLI.Failure(message: "offline")))
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, "offline")
        }
    }

    func testForceSkipsTheStoredResult() async throws {
        let c = cache()
        _ = try await read(c)
        let r = try await read(c, force: true, answer: .success("newer"))
        XCTAssertEqual(r.shown, ["newer"])
        XCTAssertEqual(r.requests, 1)
    }

    func testAChangeMakesEverythingOldButStillShowsIt() async throws {
        let c = cache()
        _ = try await read(c)
        try await Task.sleep(for: .milliseconds(5))
        c.markStale()
        let r = try await read(c, answer: .success("after"))
        XCTAssertEqual(r.shown, ["new", "after"])
        XCTAssertEqual(r.requests, 1)
    }

    func testAChangeOutlivesARestart() async throws {
        let c = cache()
        _ = try await read(c)
        try await Task.sleep(for: .milliseconds(5))
        c.markStale()
        try await Task.sleep(for: .milliseconds(200))
        let r = try await read(cache(), answer: .success("after"))
        XCTAssertEqual(r.requests, 1)
    }

    func testResultsSurviveARestart() async throws {
        _ = try await read(cache())
        let r = try await read(cache())
        XCTAssertEqual(r.shown, ["new"])
        XCTAssertEqual(r.requests, 0)
    }

    func testAccountsDoNotSeeEachOther() async throws {
        let c = cache(account: "A")
        _ = try await read(c, answer: .success("team a"))
        c.account = "B"
        let r = try await read(c, answer: .success("team b"))
        XCTAssertEqual(r.shown, ["team b"])
        XCTAssertEqual(r.requests, 1)
    }

    func testNoAccountKeepsNothing() async throws {
        let c = cache(account: nil)
        _ = try await read(c)
        let r = try await read(c)
        XCTAssertEqual(r.requests, 1)
    }

    func testSignInStatusIsAlwaysRead() async throws {
        let c = cache()
        let status = ["web", "auth", "status"]
        _ = try await read(c, status)
        let r = try await read(c, status)
        XCTAssertEqual(r.requests, 1)
    }

    func testRemoveAllForgetsTheResults() async throws {
        let c = cache()
        _ = try await read(c)
        c.removeAll()
        let r = try await read(c)
        XCTAssertEqual(r.requests, 1)
    }

    func testTwoPagesShareOneRequest() async throws {
        let c = cache()
        var requests = 0
        let fetch: @MainActor () async throws -> JSONValue = {
            requests += 1
            try await Task.sleep(for: .milliseconds(50))
            return "new"
        }
        let list = args
        let a = Task { try await c.value(list, fetch: fetch) }
        let b = Task { try await c.value(list, fetch: fetch) }
        let answers = [try await a.value, try await b.value]
        XCTAssertEqual(answers, ["new", "new"])
        XCTAssertEqual(requests, 1)
    }

    func testLifetimes() {
        XCTAssertNil(AscCache.lifetime(["auth", "status"]))
        XCTAssertNil(AscCache.lifetime(["ads", "auth", "status"]))
        XCTAssertNil(AscCache.lifetime(["web", "auth", "status"]))
        XCTAssertNil(AscCache.lifetime(["builds", "next-build-number", "--app", "1"]))
        XCTAssertEqual(AscCache.lifetime(["status", "--app", "1"]), AscCache.short)
        XCTAssertEqual(AscCache.lifetime(["builds", "list"]), AscCache.short)
        XCTAssertEqual(AscCache.lifetime(ASCAppList.listArgs), AscCache.short)
        XCTAssertEqual(AscCache.lifetime(["reviews", "list"]), AscCache.medium)
        XCTAssertEqual(AscCache.lifetime(["users", "list"]), AscCache.long)
        XCTAssertEqual(AscCache.lifetime(["web", "analytics", "overview"]), AscCache.long)
        XCTAssertEqual(AscCache.lifetime(AppIconStore.recentBuildsArgs), AscCache.long)
    }

    func testSearchIgnoresCaseAndAccents() {
        let app = ASCApp(id: "1", bundleId: "com.jastech.ritim", name: "Ritim Çalar", sku: "RITIM1", primaryLocale: "tr", platforms: [], versions: [])
        XCTAssertTrue(app.matches(""))
        XCTAssertTrue(app.matches("  "))
        XCTAssertTrue(app.matches("calar"))
        XCTAssertTrue(app.matches("JASTECH"))
        XCTAssertTrue(app.matches("ritim1"))
        XCTAssertFalse(app.matches("sudoku"))
    }
}
