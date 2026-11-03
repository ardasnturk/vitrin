import Foundation
import Observation

/// `vitrin asc apps --json`: the team's apps from App Store Connect, with the newest App Store version per platform.
/// Mirrors packages/cli/src/commands/asc.ts; states and platforms stay strings so a newer CLI never breaks decoding.

struct ASCAppVersion: Codable, Hashable, Identifiable, Sendable {
    var id: String
    /// IOS, MAC_OS, TV_OS, VISION_OS.
    var platform: String
    var version: String
    /// READY_FOR_SALE, PREPARE_FOR_SUBMISSION, IN_REVIEW …
    var state: String
    var createdAt: String?
}

struct ASCApp: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var bundleId: String
    var name: String
    var sku: String
    var primaryLocale: String
    var platforms: [String]
    var versions: [ASCAppVersion]

    /// The version the sidebar shows: iOS first, else the first platform ASC listed.
    var current: ASCAppVersion? { versions.first { $0.platform == "IOS" } ?? versions.first }
    var ascURL: URL { URL(string: "https://appstoreconnect.apple.com/apps/\(id)/distribution")! }
}

struct ASCAppsResult: Codable, Sendable {
    var generatedAt: String
    var apps: [ASCApp]
}

/// App Store Connect's names in words, and a tone per version state.
enum ASCWords {
    static func platform(_ p: String) -> String {
        switch p {
        case "IOS": return "iOS"
        case "MAC_OS": return "macOS"
        case "TV_OS": return "tvOS"
        case "VISION_OS": return "visionOS"
        default: return p
        }
    }

    /// The state in the user's language when the catalog knows it, else readable ("Pending Apple Release").
    @MainActor static func state(_ s: String) -> String {
        let key = "ascState.\(s)"
        let t = L.t(key)
        if t != key { return t }
        return s.lowercased().split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    static func tone(_ state: String) -> Tone {
        switch state {
        case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION", "ACCEPTED": return .ok
        case "WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE", "PROCESSING_FOR_DISTRIBUTION", "PROCESSING_FOR_APP_STORE", "WAITING_FOR_EXPORT_COMPLIANCE": return .info
        case "REJECTED", "DEVELOPER_REJECTED", "METADATA_REJECTED", "INVALID_BINARY", "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE": return .err
        case "PREPARE_FOR_SUBMISSION": return .warn
        default: return .neutral
        }
    }
}

/// The team's app list, read through the CLI with the account key: at launch, after the key changes, and on demand.
@MainActor @Observable final class ASCAppList {
    private(set) var apps: [ASCApp] = []
    private(set) var loading = false
    private(set) var error: String?
    private(set) var loadedAt: Date?
    private var task: Task<Void, Never>?

    func app(_ id: String?) -> ASCApp? { id.flatMap { id in apps.first { $0.id == id } } }

    /// Runs `vitrin asc apps --json` with the stored key; a refresh while one runs joins it. No key: the list empties.
    func refresh(cli: CLILocation?, credentials: ASCCredentials = .shared) async {
        if let running = task { return await running.value }
        let env = credentials.environment()
        guard !env.isEmpty else {
            apps = []
            error = nil
            loadedAt = nil
            return
        }
        guard let cli else {
            error = L.t("cli.notFound")
            return
        }
        let t = Task { [self] in
            loading = true
            defer { loading = false }
            do {
                let (outcome, value, result) = try await CLIRunner(location: cli).json(["asc", "apps"], as: ASCAppsResult.self, timeout: 120, extraEnv: env)
                if outcome == .ok, let value {
                    apps = value.apps
                    error = nil
                    loadedAt = .now
                } else if result.stderr.contains("unknown command") {
                    // A CLI from before `vitrin asc` (1.2.0 and older): say so instead of echoing commander.
                    error = L.t("apps.cliTooOld").replacingOccurrences(of: "{version}", with: cli.version ?? "?")
                } else {
                    error = Self.firstLine(of: result.stderr) ?? Self.firstLine(of: result.stdout) ?? L.t("apps.loadFailed")
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
        task = t
        await t.value
        task = nil
    }

    func clear() {
        task?.cancel()
        task = nil
        apps = []
        error = nil
        loadedAt = nil
    }

    private static func firstLine(of text: String) -> String? {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // The CLI prefixes errors with ✗ and warnings with ⚠; the words are what matter.
        guard let line = lines.first(where: { $0.hasPrefix("✗") }) ?? lines.first else { return nil }
        // "ASC API 401 /v1/apps?include=…: detail" → "ASC API 401: detail"; the path is noise in a sidebar line.
        return String(line.drop { $0 == "✗" || $0 == "⚠" || $0 == " " }).replacingOccurrences(of: #"^(ASC API \d+) /\S*:"#, with: "$1:", options: .regularExpression)
    }
}

/// Where a local project meets an App Store Connect app: the bundle id in `vitrin.config.yaml`.
enum ProjectConfigFile {
    /// `app.bundleId` of a project's `vitrin.config.yaml`, read without a YAML library: the first `bundleId:` line.
    nonisolated static func bundleId(inProjectAt path: String) -> String? {
        guard let text = try? String(contentsOfFile: path + "/vitrin.config.yaml", encoding: .utf8) else { return nil }
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("bundleId:") else { continue }
            var value = line.dropFirst("bundleId:".count).trimmingCharacters(in: .whitespaces)
            if let hash = value.firstIndex(of: "#"), !value.hasPrefix("\""), !value.hasPrefix("'") { value = value[..<hash].trimmingCharacters(in: .whitespaces) }
            if value.count >= 2, let f = value.first, (f == "\"" || f == "'"), value.last == f { value = String(value.dropFirst().dropLast()) }
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
