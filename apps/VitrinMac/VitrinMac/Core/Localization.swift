import Foundation
import Observation

/// The language the app talks in: the system's, English, Turkish, or the one the selected project's `ui.language` names.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, project, en, tr
    var id: String { rawValue }
}

/// Which strings table `L.t` reads. Observable so every view re-renders when the language changes at runtime.
@MainActor @Observable final class LanguageState {
    static let shared = LanguageState()
    /// "en", "tr" or nil for the system's choice.
    private(set) var code: String?
    private var bundles: [String: Bundle] = [:]

    func apply(setting: AppLanguage, projectLanguage: String?) {
        switch setting {
        case .system: code = nil
        case .en: code = "en"
        case .tr: code = "tr"
        case .project: code = projectLanguage.flatMap { Self.supported.contains($0) ? $0 : nil }
        }
    }

    static let supported = ["en", "tr"]

    var bundle: Bundle {
        guard let code else { return .main }
        if let b = bundles[code] { return b }
        let b = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        bundles[code] = b
        return b
    }

    var locale: Locale { code.map(Locale.init(identifier:)) ?? .current }
}

/// `L.t("key")` — the app's words in the current language (Resources/Localizable.xcstrings).
@MainActor enum L {
    static func t(_ key: String) -> String {
        LanguageState.shared.bundle.localizedString(forKey: key, value: key, table: nil)
    }
    static func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), locale: LanguageState.shared.locale, arguments: args)
    }
    /// Stage and status names the Studio and the app share.
    static func stage(_ id: String) -> String { t("stage.\(id)") }
    static func hint(_ id: String) -> String { t("hint.\(id)") }
    static func status(_ s: StageStatus) -> String { t("status.\(s.rawValue)") }
    static func date(_ iso: String?) -> String {
        guard let d = Date.fromISO(iso) else { return "" }
        return d.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: LanguageState.shared.locale))
    }
    static func relative(_ iso: String?) -> String {
        guard let d = Date.fromISO(iso) else { return "" }
        let f = RelativeDateTimeFormatter()
        f.locale = LanguageState.shared.locale
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: .now)
    }
    /// A blocker in words, with its parameters filled in.
    static func blocker(_ b: Blocker) -> String {
        var s = t("blocker.\(b.code)")
        for (k, v) in b.params { s = s.replacingOccurrences(of: "{\(k)}", with: v.display) }
        return s
    }
    static func fix(_ fix: BlockerFix, _ b: Blocker) -> String {
        switch fix.id {
        case "add-locales": return t("fix.addLocales", (b.params["locales"]?.arrayValue?.count ?? 0))
        case "drop-locales": return t("fix.dropLocales")
        case "set-primary": return t("fix.setPrimary").replacingOccurrences(of: "{locale}", with: fix.args["primaryLocale"]?.display ?? "")
        case "add-primary": return t("fix.addPrimary").replacingOccurrences(of: "{locale}", with: b.param("primary"))
        default: return fix.id
        }
    }
    /// Why a stage has its status, in words; empty when the status says it all.
    static func reason(_ view: StageView, _ o: Overview) -> String {
        guard let r = view.reason else { return "" }
        if view.stageStatus == .outdated { return t("reason.outdatedBy").replacingOccurrences(of: "{stage}", with: stage(r)) }
        switch r {
        case "validation-errors": return t("reason.validationErrors", o.validation?.counts.error ?? 0)
        case "content-changed": return t("reason.contentChanged")
        case "rejected": return t("reason.rejected")
        case "readback-differences": return t("reason.readback")
        case "question": return t("reason.question")
        default: return o.blocker(r).map(blocker) ?? ""
        }
    }
    /// A job in the user's words.
    static func job(_ j: JobSummary) -> String {
        if j.command == "upload" { return t(j.isDryRun ? "upload.dryRun" : "stage.upload") }
        if j.command == "design", j.args["samples"]?.boolValue == true { return t("job.renderSamples") }
        switch j.command {
        case "select": return t("job.select")
        case "doctor": return t("job.doctor")
        case "finalize": return t("upload.finalize")
        case "submit": return t("upload.submit")
        case "init": return t("job.init")
        default: return Pipeline.order.contains(j.command) ? stage(j.command) : j.command
        }
    }
}
