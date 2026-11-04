import Foundation

/// App Review notifications: compares the team's apps with the last look. `asc-watch.json` in Vitrin's folder is shared
/// with Remote Code, whose watcher runs while the Mac app is closed too and also reaches the phone: while it is at work
/// this one stays quiet, so a change is told once.
enum AscWatcher {
    struct Version: Codable, Hashable, Sendable {
        var appId: String
        var name: String
        var platform: String
        var version: String
        var state: String
    }

    struct Record: Codable, Sendable {
        var owner: String
        /// Seconds since 1970.
        var checkedAt: Double
        var states: [String: Version]
    }

    enum Stage: Equatable, Sendable {
        case waitingForReview, inReview, approved, live, rejected

        /// App Store Connect's states, by stage; the ones between them say nothing worth a notification.
        init?(state: String) {
            switch state {
            case "WAITING_FOR_REVIEW": self = .waitingForReview
            case "IN_REVIEW": self = .inReview
            case "ACCEPTED", "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE": self = .approved
            case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION": self = .live
            case "REJECTED", "METADATA_REJECTED", "INVALID_BINARY", "UNRESOLVED_ISSUES": self = .rejected
            default: return nil
            }
        }
    }

    static let interval: Duration = .seconds(300)
    /// Remote Code looks every five minutes; this long without a look means it stopped.
    private static let remoteCodeGrace: TimeInterval = 600

    static var defaultFile: URL {
        let env = ProcessInfo.processInfo.environment["VITRIN_APP_SUPPORT"]
        let folder = env.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Vitrin")
        return folder.appendingPathComponent("asc-watch.json")
    }

    static func read(_ file: URL) -> Record? {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Record.self, from: $0) }
    }

    static func write(_ states: [String: Version], to file: URL, now: Date = .now) {
        let record = Record(owner: "vitrin", checkedAt: now.timeIntervalSince1970, states: states)
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    static func remoteCodeIsWatching(_ record: Record?, now: Date = .now) -> Bool {
        guard let record, record.owner == "remote-code" else { return false }
        return now.timeIntervalSince1970 - record.checkedAt < remoteCodeGrace
    }

    /// `<app id>/<platform>` → the newest version.
    static func snapshot(_ apps: [ASCApp]) -> [String: Version] {
        var states: [String: Version] = [:]
        for app in apps {
            for v in app.versions {
                states["\(app.id)/\(v.platform)"] = Version(appId: app.id, name: app.name, platform: v.platform, version: v.version, state: v.state)
            }
        }
        return states
    }

    /// What reached a new review stage. An app or platform seen for the first time isn't news, and a move inside one
    /// stage (accepted, then pending release) is told once.
    static func changes(from old: [String: Version], to new: [String: Version]) -> [Version] {
        new.keys.sorted().compactMap { key in
            guard let before = old[key], let after = new[key], before.state != after.state,
                  let stage = Stage(state: after.state) else { return nil }
            return before.version == after.version && Stage(state: before.state) == stage ? nil : after
        }
    }
}
