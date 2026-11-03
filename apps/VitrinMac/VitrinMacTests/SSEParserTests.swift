import XCTest
@testable import Vitrin

final class SSEParserTests: XCTestCase {
    private func parse(_ text: String) -> [StudioEvent] {
        var p = SSEParser()
        return p.feed(Array(text.utf8))
    }
    private func string(_ e: StudioEvent) -> String { String(decoding: e.data, as: UTF8.self) }

    func testEventsSplitOnBlankLines() {
        let events = parse("event: log\ndata: {\"a\":1}\n\nevent: job\ndata: {\"b\":2}\n\n")
        XCTAssertEqual(events.map(\.name), ["log", "job"])
        XCTAssertEqual(events.map(string), ["{\"a\":1}", "{\"b\":2}"])
    }

    func testDefaultNameIsMessage() {
        let events = parse("data: hi\n\n")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.name, "message")
        XCTAssertEqual(events.first.map(string), "hi")
    }

    func testCommentsAndKeepalivesAreIgnored() {
        let events = parse(": keep-alive\n\n: another\nevent: changed\ndata: x\n\n")
        XCTAssertEqual(events.count, 1, "a comment alone does not make an event")
        XCTAssertEqual(events.first?.name, "changed")
        XCTAssertEqual(events.first.map(string), "x")
    }

    func testBlankLineWithoutDataEmitsNothing() {
        XCTAssertTrue(parse("\n\n\nevent: only-a-name\n\n").isEmpty)
    }

    func testCRLFIsTolerated() {
        let events = parse("event: log\r\ndata: one\r\n\r\nevent: job\r\ndata: two\r\n\r\n")
        XCTAssertEqual(events.map(\.name), ["log", "job"])
        XCTAssertEqual(events.map(string), ["one", "two"])
    }

    func testMultiLineDataIsJoinedWithNewlines() {
        let events = parse("data: line 1\ndata: line 2\ndata:line 3\n\n")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first.map(string), "line 1\nline 2\nline 3")
    }

    func testNameResetsAfterEachEvent() {
        let events = parse("event: remotion\ndata: a\n\ndata: b\n\n")
        XCTAssertEqual(events.map(\.name), ["remotion", "message"])
    }

    func testByteAtATimeMatchesChunked() {
        let text = "event: claude\ndata: {\"type\":\"text\",\"text\":\"héllo wörld\"}\n\n: ping\n\nevent: log\ndata: {\"level\":\"info\",\"text\":\"x\"}\n\n"
        var p = SSEParser()
        var one: [StudioEvent] = []
        for b in text.utf8 { if let e = p.feed(b) { one.append(e) } }
        let all = parse(text)
        XCTAssertEqual(one.map(\.name), all.map(\.name))
        XCTAssertEqual(one.map(string), all.map(string))
        XCTAssertEqual(one.map(\.name), ["claude", "log"])
    }

    func testIncompleteEventWaitsForBlankLine() {
        var p = SSEParser()
        XCTAssertTrue(p.feed(Array("event: log\ndata: partial\n".utf8)).isEmpty)
        let done = p.feed(Array("\n".utf8))
        XCTAssertEqual(done.count, 1)
        XCTAssertEqual(done.first.map(string), "partial")
    }

    func testDecodeHelper() {
        struct Payload: Decodable, Equatable { var level: String; var text: String }
        let events = parse("event: log\ndata: {\"level\":\"warn\",\"text\":\"careful\"}\n\n")
        XCTAssertEqual(events.first?.decode(Payload.self), Payload(level: "warn", text: "careful"))
        XCTAssertNil(parse("data: not json\n\n").first?.decode(Payload.self))
    }
}
