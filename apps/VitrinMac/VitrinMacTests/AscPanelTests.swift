import XCTest
@testable import Vitrin

/// The App Store Connect panel's words and shapes, on outputs copied from real `asc --output json` runs.
@MainActor final class AscPanelTests: XCTestCase {
    private func json(_ s: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }

    override func setUp() async throws {
        LanguageState.shared.apply(setting: .tr, projectLanguage: nil)
    }

    override func tearDown() async throws {
        LanguageState.shared.apply(setting: .system, projectLanguage: nil)
    }

    func testCodesBecomeWords() {
        XCTAssertEqual(AscText.language("de-DE"), "Almanca (Almanya)")
        XCTAssertEqual(AscText.language("de_DE"), "Almanca (Almanya)")
        XCTAssertEqual(AscText.territory("TUR"), "Türkiye")
        XCTAssertEqual(AscText.value("HEALTH_AND_FITNESS"), "Sağlık ve Fitness")
        XCTAssertEqual(AscText.value("REJECTED"), "Reddedildi")
        XCTAssertEqual(AscText.value("PT168H"), "7 gün")
        XCTAssertEqual(AscText.value("SOME_NEW_VALUE"), "Some New Value")
    }

    func testValuesAreShownByKeyAndShape() throws {
        XCTAssertEqual(AscText.shown("locale", "tr"), .text("Türkçe"))
        XCTAssertEqual(AscText.shown("name", "ACME_APP"), .text("ACME_APP"))
        XCTAssertEqual(AscText.shown("currency", "USD"), .text("USD"))
        XCTAssertEqual(AscText.shown("expired", true), .flag(true))
        XCTAssertEqual(AscText.shown("state", "VALID"), .state(AscText.value("VALID"), .ok))
        XCTAssertEqual(AscText.plain("roles", try json(#"["ADMIN"]"#)), AscText.value("ADMIN"))
        let image = try json(#"{"templateUrl":"https://x.test/a/{w}x{h}bb.{f}","width":10,"height":10}"#)
        XCTAssertEqual(AscText.shown("iconAssetToken", image), .image(URL(string: "https://x.test/a/320x320bb.png")!))
    }

    func testAnyResultHasAShape() throws {
        let list = try json(#"{"data":[{"type":"betaGroups","id":"g1","attributes":{"name":"intern","isInternalGroup":true,"createdDate":"2026-01-02T03:04:05-08:00"},"links":{"self":"x"}}],"links":{}}"#)
        guard case .list(let rows) = AscDataView.shape(list) else { return XCTFail("a list") }
        XCTAssertEqual(rows.first?.id, "g1")
        XCTAssertEqual(rows.first?.fields.first?.key, "name")
        XCTAssertEqual(AscRowList.summary(rows[0]).title, "intern")
        guard case .one = AscDataView.shape(try json(#"{"data":{"type":"apps","id":"1","attributes":{"name":"A"}}}"#)) else { return XCTFail("one resource") }
        guard case .report = AscDataView.shape(try json(#"{"appId":"1","total":45}"#)) else { return XCTFail("a report") }
        guard case .list(let none) = AscDataView.shape(try json(#"{"data":[]}"#)), none.isEmpty else { return XCTFail("an empty list") }
    }

    func testNoFieldsAreBlank() throws {
        guard case .one(let r) = AscDataView.shape(try json(#"{"data":{"type":"","id":"","attributes":{}}}"#)) else { return XCTFail("one resource") }
        XCTAssertTrue(r.fields.isEmpty)
    }

    func testNewestBuildGivesTheAppIcon() throws {
        let doc = try json(#"""
        {"data":[
          {"type":"builds","id":"b2","attributes":{"iconAssetToken":{"templateUrl":"https://x.test/new/{w}x{h}bb.{f}"}},"relationships":{"app":{"data":{"type":"apps","id":"a1"}}}},
          {"type":"builds","id":"b1","attributes":{"iconAssetToken":{"templateUrl":"https://x.test/old/{w}x{h}bb.{f}"}},"relationships":{"app":{"data":{"type":"apps","id":"a1"}}}},
          {"type":"builds","id":"b3","attributes":{"iconAssetToken":null},"relationships":{"app":{"data":{"type":"apps","id":"a2"}}}}
        ]}
        """#)
        XCTAssertEqual(AppIconStore.icons(from: doc), ["a1": "https://x.test/new/{w}x{h}bb.{f}"])
        XCTAssertEqual(AppIconStore.url(template: "https://x.test/{w}x{h}bb.{f}", size: 26)?.absoluteString, "https://x.test/52x52bb.png")
    }

    func testScreenshotsGroupByLanguageAndDevice() throws {
        let doc = try json(#"""
        {"localizations":[{"locale":"tr","versionLocalizationId":"l1","sets":[{"set":{"attributes":{"screenshotDisplayType":"APP_IPHONE_67"}},
          "screenshots":[{"attributes":{"imageAsset":{"templateUrl":"https://x.test/{w}x{h}bb.{f}","width":1320,"height":2868}}}]}]}]}
        """#)
        let languages = ScreenshotGallery.languages(doc)
        XCTAssertEqual(languages.map(\.locale), ["tr"])
        XCTAssertEqual(languages[0].localizationID, "l1")
        XCTAssertEqual(languages[0].devices.first?.type, "APP_IPHONE_67")
        XCTAssertEqual(languages[0].devices.first?.shots.count, 1)
    }

    func testTheCatalogCoversTheAreas() {
        XCTAssertGreaterThan(AscCatalog.children("versions").count, 5)
        let list = AscCatalog.command("versions list")
        XCTAssertEqual(list?.read, true)
        XCTAssertEqual(list?.takes, ["app"])
        XCTAssertEqual(list?.title, "App Store sürümleri")
        XCTAssertEqual(AscCatalog.command("testflight groups builds list")?.needs, ["group-id"])
        XCTAssertEqual(AscCatalog.source(flag: "group-id", path: "testflight groups builds list")?.path, "testflight groups list")
        XCTAssertEqual(AscCatalog.source(flag: "id", path: "users view")?.path, "users list")
        XCTAssertEqual(AscCatalog.choices("Platform: IOS, MAC_OS, TV_OS (default: IOS)"), ["IOS", "MAC_OS", "TV_OS"])
        XCTAssertNil(AscCatalog.choices("App Store Connect app ID (or ASC_APP_ID env)"))
        for area in [AscAreas.release, AscAreas.listing, AscAreas.visuals, AscAreas.builds, AscAreas.testflight, AscAreas.reviews, AscAreas.money, AscAreas.analytics, AscAreas.more] {
            for group in area { XCTAssertNotNil(AscCatalog.command(group), group) }
        }
    }

    /// Real `asc` outputs, when a folder of them is at hand (they hold account data, so they are not in the repository):
    /// every one has a page shape and nothing on its face is a raw enum.
    func testRealOutputsRead() throws {
        let dir = URL(fileURLWithPath: "/tmp/asc-samples")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil), !files.isEmpty else { throw XCTSkip("no samples") }
        var read = 0
        for f in files where f.pathExtension == "json" {
            guard let doc = try? JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: f)) else { continue }
            read += 1
            switch AscDataView.shape(doc) {
            case .list(let rows):
                for r in rows {
                    let s = AscRowList.summary(r)
                    XCTAssertFalse(s.title.isEmpty, f.lastPathComponent)
                    XCTAssertFalse(s.state.map { AscText.isEnum($0.0) } ?? false, "\(f.lastPathComponent): \(s.state?.0 ?? "")")
                }
            case .one, .report, .nothing: break
            case .text(let t): XCTFail("\(f.lastPathComponent) is plain text: \(t.prefix(60))")
            }
        }
        XCTAssertGreaterThan(read, 100)
    }
}
