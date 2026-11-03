import AppKit
import Foundation
import Observation

/// The app's root state: the project list, one session per open project, the located CLI, the update checker.
@MainActor @Observable final class AppModel {
    static let shared = AppModel()
    let store = ProjectStore()
    let settings = AppSettings.shared
    let updates = UpdateChecker()
    private(set) var sessions: [String: ProjectSession] = [:]
    private(set) var cli: CLILocation?
    private(set) var cliError: String?
    private(set) var locating = false
    var selectedProjectID: String? { didSet { settings.lastProjectID = selectedProjectID; applyLanguage() } }
    var selectedPage: ProjectPage = .flow
    var showLog = true
    var showClaude = false

    private init() {
        selectedProjectID = store.project(settings.lastProjectID)?.id ?? store.projects.first?.id
        applyLanguage()
    }

    var selectedProject: Project? { store.project(selectedProjectID) }
    var selectedSession: ProjectSession? { selectedProjectID.flatMap { sessions[$0] } }

    func session(for project: Project) -> ProjectSession {
        if let s = sessions[project.id] { return s }
        let s = ProjectSession(project: project)
        sessions[project.id] = s
        return s
    }

    /// After the account key changed: every running Studio restarts, so its environment carries the new key.
    func restartSessions() async {
        guard let cli else { return }
        for s in sessions.values where s.isReady || s.loadError != nil { await s.restart(cli: cli) }
    }

    /// Finds the CLI and opens the selected project. Called at launch and after the CLI settings change.
    func bootstrap() async {
        if let path = Self.launchProject { selectedProjectID = store.add(path: path).id }
        await locateCLI()
        await updates.checkIfDue()
        if let p = selectedProject { await open(p) }
    }

    /// `--project <folder>` (or `VITRIN_PROJECT`) adds and opens a project at launch: `open -a Vitrin --args --project ~/MyApp`.
    /// The UI tests use it to start on the example without a file dialog.
    static var launchProject: String? {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--project"), i + 1 < args.count { return args[i + 1] }
        return ProcessInfo.processInfo.environment["VITRIN_PROJECT"]
    }

    func locateCLI() async {
        locating = true
        defer { locating = false }
        do {
            cli = try await CLILocator.locate(settings: (settings.cliPath, settings.vitrinCheckout))
            cliError = nil
            updates.cliVersion = cli?.version
        } catch {
            cli = nil
            cliError = error.localizedDescription
        }
    }

    func open(_ project: Project) async {
        selectedProjectID = project.id
        guard let cli, project.exists else { return }
        let s = session(for: project)
        if !s.isReady { await s.start(cli: cli) }
    }

    func addProject(path: String) async {
        let p = store.add(path: path)
        await open(p)
    }

    func removeProject(_ id: String) {
        sessions[id]?.stop()
        sessions[id] = nil
        store.remove(id)
        if selectedProjectID == id { selectedProjectID = store.projects.first?.id }
    }

    func stopAll() {
        for s in sessions.values { s.stop() }
    }

    /// `AppLanguage.project` follows the selected project's `ui.language`.
    func applyLanguage() {
        LanguageState.shared.apply(setting: settings.language, projectLanguage: selectedSession?.overview?.config?.language)
    }

    /// Choose a folder with NSOpenPanel.
    func pickProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = L.t("projects.pickMessage")
        panel.prompt = L.t("projects.add")
        if panel.runModal() == .OK, let url = panel.url {
            Task { await addProject(path: url.path) }
        }
    }

    /// Pending decisions across every open project, for the menu bar.
    var pendingDecisions: Int { sessions.values.reduce(0) { $0 + ($1.overview?.pendingCount ?? 0) } }
    var runningJob: (project: Project, job: JobSummary)? {
        for s in sessions.values { if let j = s.job { return (s.project, j) } }
        return nil
    }
    var lastFinishedJob: (project: Project, job: JobSummary)? {
        sessions.values.compactMap { s in s.finishedJob.map { (s.project, $0) } }.max { ($0.1.endedAt ?? "") < ($1.1.endedAt ?? "") }
    }
}
