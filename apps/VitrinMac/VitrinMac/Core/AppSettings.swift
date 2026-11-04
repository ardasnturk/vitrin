import Foundation
import Observation

/// The app's own preferences (UserDefaults). Nothing here is a secret: keys stay in each project's `.env`.
/// `VITRIN_DEFAULTS_SUITE` names a separate suite (the UI tests), `VITRIN_LANGUAGE` fixes the language.
@MainActor @Observable final class AppSettings {
    static let shared = AppSettings()
    private let d = ProcessInfo.processInfo.environment["VITRIN_DEFAULTS_SUITE"].flatMap { UserDefaults(suiteName: $0) } ?? UserDefaults.standard

    var language: AppLanguage { didSet { d.set(language.rawValue, forKey: "language") } }
    /// Keep running in the menu bar when the last window closes.
    var keepInMenuBar: Bool { didSet { d.set(keepInMenuBar, forKey: "keepInMenuBar") } }
    var showMenuBarExtra: Bool { didSet { d.set(showMenuBarExtra, forKey: "showMenuBarExtra") } }
    var checkForUpdates: Bool { didSet { d.set(checkForUpdates, forKey: "checkForUpdates") } }
    var notifications: Bool { didSet { d.set(notifications, forKey: "notifications") } }
    /// Explicit path to the Vitrin CLI entry (`bin.js` or a `vitrin` executable); empty = search.
    var cliPath: String { didSet { d.set(cliPath, forKey: "cliPath") } }
    /// A Vitrin checkout to run from (`packages/cli/dist/bin.js`); empty = none.
    var vitrinCheckout: String { didSet { d.set(vitrinCheckout, forKey: "vitrinCheckout") } }
    /// Show the CLI command behind each button.
    var developerMode: Bool { didSet { d.set(developerMode, forKey: "developerMode") } }
    /// The Claude Code model the briefs run with (`claude --model`): an alias (fable, opus, sonnet, haiku) or a full
    /// name; empty = Claude Code's own default. Sent with every run, so a change applies to the next one.
    var claudeModel: String { didSet { d.set(claudeModel, forKey: "claudeModel") } }
    var lastUpdateCheck: Date? { didSet { d.set(lastUpdateCheck, forKey: "lastUpdateCheck") } }
    var lastProjectID: String? { didSet { d.set(lastProjectID, forKey: "lastProjectID") } }
    /// The welcome tour ran to the end (or was skipped). The UI tests start with it done.
    var onboardingDone: Bool { didSet { d.set(onboardingDone, forKey: "onboardingDone") } }

    private init() {
        let env = ProcessInfo.processInfo.environment
        let testing = env["VITRIN_UITEST"] == "1"
        language = env["VITRIN_LANGUAGE"].flatMap(AppLanguage.init(rawValue:)) ?? AppLanguage(rawValue: d.string(forKey: "language") ?? "") ?? .system
        keepInMenuBar = d.object(forKey: "keepInMenuBar") as? Bool ?? !testing
        showMenuBarExtra = d.object(forKey: "showMenuBarExtra") as? Bool ?? !testing
        // A test run never calls GitHub.
        checkForUpdates = d.object(forKey: "checkForUpdates") as? Bool ?? !testing
        notifications = d.object(forKey: "notifications") as? Bool ?? true
        cliPath = d.string(forKey: "cliPath") ?? ""
        vitrinCheckout = d.string(forKey: "vitrinCheckout") ?? ProcessInfo.processInfo.environment["VITRIN_DEV"] ?? ""
        developerMode = d.bool(forKey: "developerMode")
        claudeModel = d.string(forKey: "claudeModel") ?? ""
        lastUpdateCheck = d.object(forKey: "lastUpdateCheck") as? Date
        lastProjectID = d.string(forKey: "lastProjectID")
        onboardingDone = d.object(forKey: "onboardingDone") as? Bool ?? testing
    }
}
