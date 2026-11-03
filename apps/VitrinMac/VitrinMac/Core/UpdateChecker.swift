import Foundation
import Observation

/// The newest release on GitHub (ardasnturk/vitrin) against the CLI and the app. The release carries the CLI tarball
/// and SHA256SUMS; the app's own build is not published there yet (see SparkleUpdater).
@MainActor @Observable final class UpdateChecker {
    struct Release: Codable, Sendable {
        struct Asset: Codable, Sendable {
            var name: String
            var browser_download_url: String
            var size: Int
        }
        var tag_name: String
        var name: String?
        var html_url: String
        var published_at: String?
        var body: String?
        var assets: [Asset]
        var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
    }

    enum State: Equatable { case idle, checking, upToDate, available(String), failed(String) }
    private(set) var state: State = .idle
    private(set) var latest: Release?
    private(set) var checkedAt: Date?
    /// The CLI version the app runs (from the located CLI).
    var cliVersion: String?
    static let repo = "ardasnturk/vitrin"
    var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    /// Compares dotted versions numerically; prerelease suffixes are dropped.
    nonisolated static func compare(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] { s.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? [] }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let d = (i < pa.count ? pa[i] : 0) - (i < pb.count ? pb[i] : 0)
            if d != 0 { return d > 0 ? 1 : -1 }
        }
        return 0
    }

    func check(notify: Bool = true) async {
        state = .checking
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "accept")
        req.setValue("VitrinMac/\(appVersion)", forHTTPHeaderField: "user-agent")
        req.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let r = try JSONDecoder().decode(Release.self, from: data)
            latest = r
            checkedAt = .now
            AppSettings.shared.lastUpdateCheck = .now
            let current = cliVersion ?? appVersion
            if Self.compare(r.version, current) > 0 {
                state = .available(r.version)
                if notify { Notifier.shared.post(id: "update-\(r.version)", title: L.t("updates.availableTitle"), body: L.t("updates.availableBody").replacingOccurrences(of: "{version}", with: r.version).replacingOccurrences(of: "{current}", with: current)) }
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Daily, when enabled.
    func checkIfDue() async {
        guard AppSettings.shared.checkForUpdates else { return }
        if let last = AppSettings.shared.lastUpdateCheck, Date().timeIntervalSince(last) < 24 * 3600 { return }
        await check()
    }
}

/// Sparkle skeleton. The framework is not bundled: adding it means the SPM package `sparkle-project/Sparkle`, an
/// `SUPublicEDKey` in Info.plist, a signed appcast and a signed, notarized app, none of which this build has. Until
/// then the app reads GitHub releases (UpdateChecker) and opens the release page.
@MainActor final class SparkleUpdater {
    static let shared = SparkleUpdater()
    var appcastURL: URL? { URL(string: AppSettings.shared.appcastURL) }
    /// True once Sparkle is linked and configured; drives the Settings UI.
    var isAvailable: Bool { false }
    func checkForUpdates() {}
}
