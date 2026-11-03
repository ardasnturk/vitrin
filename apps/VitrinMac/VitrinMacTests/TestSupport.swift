import Foundation
import XCTest

/// Where things are, found from this file's path: the repository, the CLI build and the example project.
enum TestPaths {
    /// `<repo>` from `<repo>/apps/VitrinMac/VitrinMacTests/TestSupport.swift`.
    static let repo: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }
        return url.standardizedFileURL
    }()
    static var cliBin: URL { repo.appendingPathComponent("packages/cli/dist/bin.js") }
    static var ritim: URL { repo.appendingPathComponent("examples/Ritim") }
    static var fixtures: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures") }

    /// A fixture JSON from the test bundle, else from the source tree.
    static func fixture(_ name: String) throws -> Data {
        if let url = Bundle(for: FixtureAnchor.self).url(forResource: name, withExtension: "json") { return try Data(contentsOf: url) }
        return try Data(contentsOf: fixtures.appendingPathComponent("\(name).json"))
    }

    /// Skips the test when the CLI is not built.
    static func requireCLI() throws {
        if !FileManager.default.fileExists(atPath: cliBin.path) {
            throw XCTSkip("The Vitrin CLI is not built: \(cliBin.path) is missing. Run `pnpm build` at the repository root.")
        }
    }
}

private final class FixtureAnchor {}
