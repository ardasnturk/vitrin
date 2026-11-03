import Foundation
import Observation

/// The app's own preferences (UserDefaults). Nothing here is a secret: keys stay in each project's `.env`.
/// `VITRIN_DEFAULTS_SUITE` names a separate suite (the UI tests), `VITRIN_LANGUAGE` fixes the language (en, tr).
@MainActor @Observable final class AppSettings {
    static let shared = AppSettings()
    private let d = ProcessInfo.processInfo.environment["VITRIN_DEFAULTS_SUITE"].flatMap { UserDefaults(suiteName: $0) } ?? UserDefaults.standard

    var language: AppLanguage { didSet { d.set(language.rawValue, forKey: "language") } }
    /// Keep running in the menu bar when the last window closes.
    var keepInMenuBar: Bool { didSet { d.set(keepInMenuBar, forKey: "keepInMenuBar") } }
    var showMenuBarExtra: Bool { didSet { d.set(showMenuBarExtra, forKey: "showMenuBarExtra") } }
    var checkForUpdates: Bool { didSet { d.set(checkForUpdates, forKey: "checkForUpdates") } }
    var notifications: Bool { didSet { d.set(notifications, forKey: "notifications") } }
    /// Sparkle appcast (skeleton: read by SparkleUpdater once the framework is bundled).
    var appcastURL: String { didSet { d.set(appcastURL, forKey: "appcastURL") } }
    /// Explicit path to the Vitrin CLI entry (`bin.js` or a `vitrin` executable); empty = search.
    var cliPath: String { didSet { d.set(cliPath, forKey: "cliPath") } }
    /// A Vitrin checkout to run from (`packages/cli/dist/bin.js`); empty = none.
    var vitrinCheckout: String { didSet { d.set(vitrinCheckout, forKey: "vitrinCheckout") } }
    /// Show the CLI command behind each button.
    var developerMode: Bool { didSet { d.set(developerMode, forKey: "developerMode") } }
    var lastUpdateCheck: Date? { didSet { d.set(lastUpdateCheck, forKey: "lastUpdateCheck") } }
    var lastProjectID: String? { didSet { d.set(lastProjectID, forKey: "lastProjectID") } }

    private init() {
        let env = ProcessInfo.processInfo.environment
        let testing = env["VITRIN_UITEST"] == "1"
        language = env["VITRIN_LANGUAGE"].flatMap(AppLanguage.init(rawValue:)) ?? AppLanguage(rawValue: d.string(forKey: "language") ?? "") ?? .project
        keepInMenuBar = d.object(forKey: "keepInMenuBar") as? Bool ?? !testing
        showMenuBarExtra = d.object(forKey: "showMenuBarExtra") as? Bool ?? !testing
        // A test run never calls GitHub.
        checkForUpdates = d.object(forKey: "checkForUpdates") as? Bool ?? !testing
        notifications = d.object(forKey: "notifications") as? Bool ?? true
        appcastURL = d.string(forKey: "appcastURL") ?? "https://github.com/ardasnturk/vitrin/releases.atom"
        cliPath = d.string(forKey: "cliPath") ?? ""
        vitrinCheckout = d.string(forKey: "vitrinCheckout") ?? ProcessInfo.processInfo.environment["VITRIN_DEV"] ?? ""
        developerMode = d.bool(forKey: "developerMode")
        lastUpdateCheck = d.object(forKey: "lastUpdateCheck") as? Date
        lastProjectID = d.string(forKey: "lastProjectID")
    }
}
