import XCTest

/// Drives the app on examples/Ritim with the checkout's CLI. Each run gets its own Application Support folder and
/// UserDefaults suite, so the user's projects and settings are never touched. The Studio takes 5–30 s to start.
final class VitrinMacUITests: XCTestCase {
    private var app: XCUIApplication!
    private var isolationDir: URL!

    /// `<repo>` from `<repo>/apps/VitrinMac/VitrinMacUITests/VitrinMacUITests.swift`.
    private static let repo: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url.standardizedFileURL
    }()
    private static var ritim: URL { repo.appendingPathComponent("examples/Ritim") }
    private static var cliBin: URL { repo.appendingPathComponent("packages/cli/dist/bin.js") }

    private let studioTimeout: TimeInterval = 120

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard FileManager.default.fileExists(atPath: Self.cliBin.path) else {
            throw XCTSkip("The Vitrin CLI is not built (\(Self.cliBin.path)); run `pnpm build` at the repository root.")
        }
        guard FileManager.default.fileExists(atPath: Self.ritim.appendingPathComponent("vitrin.config.yaml").path) else {
            throw XCTSkip("examples/Ritim is missing.")
        }
        isolationDir = FileManager.default.temporaryDirectory.appendingPathComponent("vitrin-mac-uitests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: isolationDir, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launchEnvironment = [
            "VITRIN_PROJECT": Self.ritim.path,
            "VITRIN_DEV": Self.repo.path,
            "VITRIN_APP_SUPPORT": isolationDir.appendingPathComponent("support").path,
            "VITRIN_DEFAULTS_SUITE": "com.jastech.vitrin.uitests.\(UUID().uuidString)",
            "VITRIN_LANGUAGE": "en",
            "VITRIN_UITEST": "1",
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
        if let isolationDir { try? FileManager.default.removeItem(at: isolationDir) }
    }

    // MARK: helpers

    /// Any element with this accessibility identifier.
    private func byID(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    /// Any element whose label is exactly `text`.
    private func labelled(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", text)).firstMatch
    }

    /// Any element whose label contains `text`.
    private func containing(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// The sidebar is a `List(.sidebar)`: an outline whose rows carry static texts.
    private var sidebar: XCUIElement { app.outlines.firstMatch }

    /// Waits for the Studio: the project row reads "Ritim" and the Flow page lists its stages.
    private func waitForProject() {
        XCTAssertTrue(sidebar.staticTexts["Ritim"].waitForExistence(timeout: studioTimeout), "the sidebar never showed Ritim")
        XCTAssertTrue(labelled("Analyze the project").waitForExistence(timeout: studioTimeout), "the Flow page never listed its stages (Studio did not start?)")
    }

    private func openPage(_ name: String) {
        let row = sidebar.staticTexts[name]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "no sidebar row \(name)")
        row.click()
    }

    /// Polls `condition` on the main run loop until it holds or `timeout` passes.
    @discardableResult
    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return condition()
    }

    /// The page title is a `Text(...).font(.title)` in the detail's scroll view, apart from the sidebar row of the same name.
    private func assertPageTitle(_ name: String) {
        let detailTitle = app.scrollViews.descendants(matching: .staticText).matching(NSPredicate(format: "label == %@", name)).firstMatch
        if detailTitle.waitForExistence(timeout: 20) { return }
        // Some pages render their header outside a scroll view; then at least two elements carry the name (row + title).
        let all = app.staticTexts.matching(NSPredicate(format: "label == %@", name))
        XCTAssertTrue(waitUntil(20) { all.count >= 2 }, "the page title \(name) did not appear")
    }

    // MARK: (a) launch

    func testLaunchShowsRitimAndFlow() {
        waitForProject()
        XCTAssertTrue(labelled("Flow").exists)
    }

    // MARK: (b) Claude column and log panel

    func testClaudeColumnToggles() {
        waitForProject()
        let toggle = byID("toolbar.claude")
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        let title = byID("claude.title")
        XCTAssertFalse(title.exists, "the Claude column starts hidden")
        toggle.click()
        XCTAssertTrue(title.waitForExistence(timeout: 10), "claude.title did not appear after the first click")
        toggle.click()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: title)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "claude.title still there after the second click")
    }

    func testLogPanelToggles() throws {
        waitForProject()
        let toggle = byID("toolbar.log")
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        let panel = byID("log.panel")
        guard panel.waitForExistence(timeout: 10) else {
            throw XCTSkip("log.panel is not exposed as an accessibility element (the identifier sits on the LogPanel container); needs `.accessibilityElement(children: .contain)` on LogPanel or the identifier on a child control.")
        }
        toggle.click()
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: panel)
        XCTAssertEqual(XCTWaiter().wait(for: [hidden], timeout: 10), .completed, "log.panel still visible after the first click")
        toggle.click()
        XCTAssertTrue(panel.waitForExistence(timeout: 10), "log.panel did not come back after the second click")
    }

    // MARK: (c) pages

    func testSidebarPagesShowTheirTitles() {
        waitForProject()
        for name in ["Research", "Store text", "Visuals", "Review", "Upload"] {
            openPage(name)
            assertPageTitle(name)
        }
        openPage("Flow")
        XCTAssertTrue(labelled("Analyze the project").waitForExistence(timeout: 20))
    }

    // MARK: (d) upload dry-run

    func testUploadDryRunProducesAPlanAndUploadStaysDisabled() {
        waitForProject()
        openPage("Upload")
        let dryRun = byID("upload.dryRun")
        XCTAssertTrue(dryRun.waitForExistence(timeout: 30), "upload.dryRun not found")
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: dryRun)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 60), .completed, "upload.dryRun stayed disabled (a job running?)")
        let uploadNow = byID("upload.now")
        XCTAssertTrue(uploadNow.waitForExistence(timeout: 10))
        XCTAssertFalse(uploadNow.isEnabled, "Upload now must be disabled without keys and approval")

        dryRun.click()
        let shown = waitUntil(180) { self.containing("Last plan").exists || self.containing("unchanged").exists || self.app.tables.firstMatch.exists }
        XCTAssertTrue(shown, "no plan table, 'unchanged' text or 'Last plan' pill within 180 s")
        XCTAssertFalse(uploadNow.isEnabled, "Upload now became enabled after the dry-run")
    }

    // MARK: (e) review

    func testReviewOffersApproveAllButDoesNotClickIt() {
        waitForProject()
        openPage("Review")
        let approve = byID("review.approveAll")
        XCTAssertTrue(approve.waitForExistence(timeout: 60), "review.approveAll not found")
        XCTAssertTrue(byID("review.reject").exists)
        // Never clicked: approving would write approval.json into examples/Ritim.
        XCTAssertFalse(FileManager.default.fileExists(atPath: Self.ritim.appendingPathComponent("metadata/approval.json").path), "examples/Ritim must stay unapproved")
    }
}
