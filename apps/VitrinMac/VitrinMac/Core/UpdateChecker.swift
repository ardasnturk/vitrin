import AppKit
import Foundation
import Observation

/// The newest release on GitHub (ardasnturk/vitrin) against this app, and installing it: the DMG is downloaded, checked
/// against its checksum, signature, Team ID and Gatekeeper, swapped in and relaunched (UpdateInstaller). The CLI of the
/// new version follows on the first launch (AppModel.bootstrap).
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
        var dmg: Asset? { assets.first { $0.name == "Vitrin-\(version).dmg" } }
        var checksum: Asset? { dmg.flatMap { dmg in assets.first { $0.name == dmg.name + ".sha256" } } }
    }

    enum State: Equatable { case idle, checking, upToDate, available(String), downloading(Double), installing, failed(String) }
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

    /// A download or an install is under way; a check would overwrite its state.
    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }
    var available: String? { if case .available(let v) = state { return v }; return nil }

    func check(notify: Bool = true) async {
        guard !isBusy else { return }
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
            if Self.compare(r.version, appVersion) > 0 {
                state = .available(r.version)
                if notify { Notifier.shared.post(id: "update-\(r.version)", title: L.t("updates.availableTitle"), body: L.t("updates.availableBody").replacingOccurrences(of: "{version}", with: r.version).replacingOccurrences(of: "{current}", with: appVersion)) }
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Daily, when enabled; looks again every hour so an app left open for days still finds a release.
    func checkPeriodically() async {
        while !Task.isCancelled {
            await checkIfDue()
            try? await Task.sleep(for: .seconds(3600))
        }
    }

    func checkIfDue() async {
        guard AppSettings.shared.checkForUpdates else { return }
        if let last = AppSettings.shared.lastUpdateCheck, Date().timeIntervalSince(last) < 24 * 3600 { return }
        await check()
    }

    /// Downloads, verifies and installs the latest release, then quits so the swap script can relaunch the new version.
    func install() async {
        guard let release = latest, available != nil else { return }
        let page = URL(string: release.html_url)
        guard let dmg = release.dmg, let dmgURL = URL(string: dmg.browser_download_url),
              let checksum = release.checksum.flatMap({ URL(string: $0.browser_download_url) }) else {
            if let page { NSWorkspace.shared.open(page) }
            return
        }
        let bundle = Bundle.main.bundleURL
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("VitrinUpdate-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            state = .downloading(0)
            let file = staging.appendingPathComponent(dmg.name)
            try await UpdateInstaller.download(dmgURL, to: file, expectedSize: dmg.size) { [weak self] fraction in
                guard let self, case .downloading = self.state else { return }
                self.state = .downloading(fraction)
            }
            state = .installing
            guard let expected = Self.digest(from: try await UpdateInstaller.fetchText(checksum), fileName: dmg.name) else { throw UpdateInstaller.Failure.checksumMissing }
            guard try await UpdateInstaller.sha256Hex(of: file) == expected else { throw UpdateInstaller.Failure.checksumMismatch }
            let app = try await UpdateInstaller.extractApp(fromDMG: file, into: staging)
            try? fm.removeItem(at: file)
            try await UpdateInstaller.verify(stagedApp: app)
            guard UpdateInstaller.canReplace(bundleAt: bundle) else {
                if let page { NSWorkspace.shared.open(page) }
                throw UpdateInstaller.Failure.cannotReplace
            }
            try UpdateInstaller.launchSwap(pid: ProcessInfo.processInfo.processIdentifier, oldBundle: bundle, newBundle: app, backup: staging.appendingPathComponent("Previous-\(bundle.lastPathComponent)"))
            // From the run loop, not this main-queue job: terminate waits in a nested run loop.
            RunLoop.main.perform { NSApp.terminate(nil) }
        } catch {
            try? fm.removeItem(at: staging)
            state = .failed((error as? UpdateInstaller.Failure)?.message ?? L.t("updates.fail.generic"))
        }
    }

    /// The lowercase SHA-256 of a `shasum -a 256` file: the line naming the file, else the first.
    nonisolated static func digest(from text: String, fileName: String) -> String? {
        let lines: [[String]] = text.split(whereSeparator: \.isNewline).map { $0.split(whereSeparator: \.isWhitespace).map { String($0) } }
            .filter { $0.first?.count == 64 && $0.first?.allSatisfy(\.isHexDigit) == true }
        let line = lines.first { $0.last.map { URL(fileURLWithPath: $0).lastPathComponent } == fileName } ?? lines.first
        return line?.first?.lowercased()
    }
}
