import Foundation
import Observation

/// Where the app keeps its own files: ~/Library/Application Support/Vitrin (`VITRIN_APP_SUPPORT` names another folder,
/// so the UI tests and the unit tests keep theirs apart from the user's).
enum AppSupport {
    static let base: URL = {
        let url = ProcessInfo.processInfo.environment["VITRIN_APP_SUPPORT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Vitrin", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return url
    }()
}

/// The App Store Connect API key the app holds once for every project (Settings → Account), the way a per-project
/// `.env` would hold ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH. The .p8 is copied under Application Support with
/// owner-only permissions; the ids sit next to it in credentials.json, also owner-only. The CLI reads the variables
/// from the environment first and `.env` second (loadEnv in @vitrin/core), so the app hands them to each Studio it
/// starts — except for a project whose own `.env` names a key: that project keeps its key.
@MainActor @Observable final class ASCCredentials {
    static let shared = ASCCredentials(base: AppSupport.base)

    struct Key: Codable, Equatable, Sendable {
        var keyId: String
        var issuerId: String
        /// Absolute path of the stored .p8.
        var keyPath: String
    }

    struct SaveError: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    private(set) var key: Key?
    let base: URL
    private var file: URL { base.appendingPathComponent("credentials.json") }
    private var keysDir: URL { base.appendingPathComponent("keys", isDirectory: true) }

    init(base: URL) {
        self.base = base
        if let data = try? Data(contentsOf: file), let k = try? JSONDecoder().decode(Key.self, from: data), FileManager.default.fileExists(atPath: k.keyPath) { key = k }
    }

    var isSet: Bool { key != nil }

    /// Stores the ids and a private copy of the .p8 (0600 under keys/). The original file stays where it is.
    func save(keyId: String, issuerId: String, p8: URL) throws {
        let id = keyId.trimmingCharacters(in: .whitespacesAndNewlines)
        let issuer = issuerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !issuer.isEmpty else { throw SaveError(message: L.t("settings.keyInvalid")) }
        let pem = try String(contentsOf: p8, encoding: .utf8)
        guard pem.contains("PRIVATE KEY-----") else { throw SaveError(message: L.t("settings.keyNotP8")) }
        let fm = FileManager.default
        try fm.createDirectory(at: keysDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let safe = id.filter { $0.isLetter || $0.isNumber }
        let dest = keysDir.appendingPathComponent("AuthKey_\(safe.isEmpty ? "key" : safe).p8")
        if let old = key, old.keyPath != dest.path { try? fm.removeItem(atPath: old.keyPath) }
        try? fm.removeItem(at: dest)
        try Data(pem.utf8).write(to: dest, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
        let k = Key(keyId: id, issuerId: issuer, keyPath: dest.path)
        let data = try JSONEncoder().encode(k)
        try data.write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        key = k
    }

    /// Forgets the key and deletes the stored .p8.
    func clear() {
        if let k = key { try? FileManager.default.removeItem(atPath: k.keyPath) }
        try? FileManager.default.removeItem(at: file)
        key = nil
    }

    /// The variables for a CLI run in `root`: the stored key, unless the project's own `.env` sets ASC_KEY_ID (then the
    /// project's key is the one the user meant, and `loadEnv` would let ours override it).
    func environment(forProject root: String) -> [String: String] {
        if Self.dotenvNames(at: URL(fileURLWithPath: root).appendingPathComponent(".env")).contains("ASC_KEY_ID") { return [:] }
        return environment()
    }

    /// The variables for a CLI run outside any project (`vitrin asc apps`): the stored key, or nothing.
    func environment() -> [String: String] {
        guard let k = key else { return [:] }
        return ["ASC_KEY_ID": k.keyId, "ASC_ISSUER_ID": k.issuerId, "ASC_KEY_PATH": k.keyPath]
    }

    /// The names a `.env` file sets to a non-empty value (`KEY=value`, `export KEY=value`; comments and blanks skipped).
    nonisolated static func dotenvNames(at url: URL) -> Set<String> {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var names = Set<String>()
        for raw in text.split(separator: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let name = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let f = value.first, (f == "\"" || f == "'"), value.last == f { value = String(value.dropFirst().dropLast()) }
            if !name.isEmpty, !value.isEmpty { names.insert(name) }
        }
        return names
    }
}
