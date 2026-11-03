import XCTest
@testable import Vitrin

final class JSONValueTests: XCTestCase {
    private let sample: JSONValue = .object([
        "string": "hello",
        "number": 42,
        "fraction": .number(1.5),
        "bool": true,
        "null": .null,
        "array": .array(["a", 1, false, .null, .object(["k": "v"])]),
        "nested": .object(["deep": .object(["deeper": .array([.number(-3)])])]),
    ])

    func testRoundTrip() throws {
        let data = try JSONEncoder().encode(sample)
        let back = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(back, sample)
    }

    func testDecodesFromServerStyleJSON() throws {
        let text = #"{"command":"upload","args":{"dryRun":true,"skipScreenshots":false,"count":3,"name":"x","list":[1,"two",null],"none":null}}"#
        let v = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        let args = v.objectValue?["args"]?.objectValue
        XCTAssertEqual(args?["dryRun"]?.boolValue, true)
        XCTAssertEqual(args?["skipScreenshots"]?.boolValue, false)
        XCTAssertEqual(args?["count"]?.numberValue, 3)
        XCTAssertEqual(args?["name"]?.stringValue, "x")
        XCTAssertEqual(args?["list"]?.arrayValue?.count, 3)
        XCTAssertEqual(args?["list"]?.arrayValue?[2], .null)
        XCTAssertEqual(args?["none"], .null)
        // Re-encoding and decoding gives the same value.
        let again = try JSONDecoder().decode(JSONValue.self, from: try JSONEncoder().encode(v))
        XCTAssertEqual(again, v)
    }

    func testBoolIsNotANumber() throws {
        // `true` must decode as .bool, `1` as .number, even though Bool is tried first.
        let v = try JSONDecoder().decode([JSONValue].self, from: Data("[true, 1, 0, false]".utf8))
        XCTAssertEqual(v, [.bool(true), .number(1), .number(0), .bool(false)])
    }

    func testDisplay() {
        XCTAssertEqual(JSONValue.number(3).display, "3")
        XCTAssertEqual(JSONValue.number(2.5).display, "2.5")
        XCTAssertEqual(JSONValue.array(["a", "b"]).display, "a, b")
        XCTAssertEqual(JSONValue.null.display, "")
        XCTAssertEqual(JSONValue.object(["b": 1, "a": 2]).display, "a, b")
    }

    func testLiterals() {
        let v: [String: JSONValue] = ["s": "text", "b": true, "i": 7]
        XCTAssertEqual(v["s"], .string("text"))
        XCTAssertEqual(v["b"], .bool(true))
        XCTAssertEqual(v["i"], .number(7))
    }
}
