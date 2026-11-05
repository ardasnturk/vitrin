import AppKit
import Foundation
import Observation

/// The app's root state: the project list, one session per open project, the located CLI, the update checker.
@MainActor @Observable final class AppModel {
    static let shared = AppModel()
    let store = ProjectStore()
    let settings = AppSettings.shared
    let updates = UpdateChecker()
    /// The team's apps from App Store Connect (Settings → Account key), shown above the projects.
    let ascApps = ASCAppList()
    /// Who App Store Connect requests run as (Vitrin's key, asc's own login, or nobody).
    let connection = AscConnection()
    let icons = AppIconStore()
    let installer = ToolInstaller()
    /// Counts the finished installs, for the pages that list what is on this Mac.
    private(set) var installRevision = 0
    /// The new app sheet.
    var showNewApp = false
    private(set) var sessions: [String: ProjectSession] = [:]
    private(set) var cli: CLILocation?
    private(set) var cliError: String?
    private(set) var locating = false
    private var watchingAppReview = false
    private var watchingRanks = false
    /// When each project's check last ran here, so a failing one waits instead of retrying every hour.
    private var rankAttempts: [String: Date] = [:]
    var selectedProjectID: String? { didSet { settings.lastProjectID = selectedProjectID; applyLanguage() } }
    var selectedPage: ProjectPage = .flow
    /// An App Store Connect app without a linked project folder, shown read-only; nil while a project page is open.
    var selectedAppID: String? { didSet { if selectedAppID != nil { showHome = false; selectedTeamPage = nil } } }
    /// A team page (users, devices, signing, every asc command), when one is selected.
    var selectedTeamPage: TeamPage? { didSet { if selectedTeamPage != nil { showHome = false } } }
    /// The overview page (Genel bakış): every app and project at a glance. Shown when nothing else is selected.
    var showHome = false
    var showLog = true
    var showClaude = false

    private init() {
        selectedProjectID = store.project(settings.lastProjectID)?.id ?? store.projects.first?.id
        applyLanguage()
    }

    var selectedProject: Project? { store.project(selectedProjectID) }
    var selectedSession: ProjectSession? { selectedProjectID.flatMap { sessions[$0] } }
    var selectedApp: ASCApp? { ascApps.app(selectedAppID) }

    /// The local project whose `vitrin.config.yaml` names the app's bundle id (the open Studio's overview first).
    func linkedProject(for app: ASCApp) -> Project? {
        if let s = sessions.values.first(where: { $0.overview?.app?.bundleId == app.bundleId }) { return s.project }
        return store.projects.first { ProjectConfigFile.bundleId(inProjectAt: $0.path) == app.bundleId }
    }

    /// A project's name as people know the app: the App Store Connect name when linked, else the name the analysis
    /// found (unless it is only the bundle id), else the folder name.
    func displayName(for project: Project) -> String {
        if let a = ascApp(for: project) { return a.name }
        if let o = sessions[project.id]?.overview?.app, !o.name.isEmpty, o.name != o.bundleId { return o.name }
        return project.name
    }

    /// The App Store Connect app a project is linked to, for its row and title.
    func ascApp(for project: Project) -> ASCApp? {
        let id = sessions[project.id]?.overview?.app?.bundleId ?? ProjectConfigFile.bundleId(inProjectAt: project.path)
        return id.flatMap { id in ascApps.apps.first { $0.bundleId == id } }
    }

    /// A sidebar click on an app: its project when one is linked, else the read-only overview.
    /// A sidebar click on an app: its App Store Connect page, linked project or not (the page's hero opens the
    /// project). Jumping straight to the project hid the app's live metadata.
    func select(app: ASCApp) async {
        selectedTeamPage = nil
        showHome = false
        selectedAppID = app.id
    }

    /// Reads the team's apps (key change, the refresh button); at launch the cache may answer (`force: false`).
    func refreshApps(force: Bool = true) async {
        await ascApps.refresh(cli: cli, connection: connection, force: force)
        Task { await icons.load(apps: ascApps.apps) }
        if let id = selectedAppID, ascApps.app(id) == nil, ascApps.error == nil { selectedAppID = nil }
    }

    /// Runs for as long as the app does, also in the menu bar. The window's task calls `bootstrap` each time it opens.
    private func watchAppReview() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: AscWatcher.interval)
            await checkAppReview()
        }
    }

    /// One look at the team's apps: a change of review stage notifies, and what was read about the apps is old.
    func checkAppReview() async {
        guard settings.notifications, settings.notifyAppReview, connection.isConnected else { return }
        let file = AscWatcher.defaultFile
        let previous = AscWatcher.read(file)
        guard !AscWatcher.remoteCodeIsWatching(previous) else { return }
        await ascApps.refresh(cli: cli, connection: connection, force: true)
        guard ascApps.error == nil, !ascApps.apps.isEmpty else { return }
        let states = AscWatcher.snapshot(ascApps.apps)
        AscWatcher.write(states, to: file)
        // The first look only records where everything stands.
        guard let previous else { return }
        let changes = AscWatcher.changes(from: previous.states, to: states)
        if !changes.isEmpty { AscCache.shared.markStale() }
        for v in changes {
            Notifier.shared.post(id: "review-\(v.appId)-\(v.platform)-\(v.version)-\(v.state)", title: v.name,
                                 body: "\(ASCWords.platform(v.platform)) \(v.version) · \(ASCWords.state(v.state))")
        }
    }

    private func watchRanks() async {
        // Launching is busy enough, and the App Store search API is slow on purpose.
        try? await Task.sleep(for: .seconds(120))
        while !Task.isCancelled {
            await checkRanks()
            try? await Task.sleep(for: RankWatcher.interval)
        }
    }

    /// One pass over the projects: those already measured once and due now, one at a time.
    func checkRanks(now: Date = .now) async {
        guard settings.rankSchedule != .off, let cli else { return }
        for project in store.projects where project.hasConfig {
            let due = RankWatcher.isDue(newest: RankWatcher.newestSnapshot(in: project.path), schedule: settings.rankSchedule, lastAttempt: rankAttempts[project.id], now: now)
            guard due else { continue }
            rankAttempts[project.id] = now
            guard let result = try? await CLIRunner(location: cli).json(["rank"], as: RankWatcher.Result.self, cwd: project.path, timeout: RankWatcher.timeout).value,
                  let body = RankWatcher.message(result.highlights) else { continue }
            Notifier.shared.post(id: "ranks-\(project.id)-\(result.date)", title: displayName(for: project), body: body)
        }
    }

    func session(for project: Project) -> ProjectSession {
        if let s = sessions[project.id] { return s }
        let s = ProjectSession(project: project)
        sessions[project.id] = s
        return s
    }

    /// After the account key changed: the app list is read again and every running Studio restarts, so its
    /// environment carries the new key.
    func restartSessions() async {
        Task { await refreshApps() }
        guard let cli else { return }
        for s in sessions.values where s.isReady || s.loadError != nil { await s.restart(cli: cli) }
    }

    /// Finds the CLI and opens the selected project. Called at launch and after the CLI settings change.
    func bootstrap() async {
        applyLanguage()
        if let path = Self.launchProject { selectedProjectID = store.add(path: path).id }
        await locateCLI()
        // The team's apps load beside the project, not after it.
        Task { await refreshApps(force: false) }
        Task { await updates.checkPeriodically() }
        if !watchingAppReview {
            watchingAppReview = true
            Task { await watchAppReview() }
        }
        if !watchingRanks {
            watchingRanks = true
            Task { await watchRanks() }
        }
        Task { await updateCLIIfBehind() }
        if let p = selectedProject { await open(p) }
    }

    /// `--project <folder>` (or `VITRIN_PROJECT`) adds and opens a project at launch: `open -a Vitrin --args --project ~/MyApp`.
    /// The UI tests use it to start on the example without a file dialog.
    static var launchProject: String? {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--project"), i + 1 < args.count { return args[i + 1] }
        return ProcessInfo.processInfo.environment["VITRIN_PROJECT"]
    }

    /// After the app updated itself: the CLI it installed follows. A CLI from Settings, PATH or a checkout is the
    /// user's own, and stays.
    private func updateCLIIfBehind() async {
        guard let cli, cli.kind == .plugin, let version = cli.version, UpdateChecker.compare(updates.appVersion, version) > 0 else { return }
        await install([.vitrin])
    }

    /// Installs tools, then reads again everything that depends on them.
    func install(_ tools: [LocalTool]) async {
        await installer.install(tools, appVersion: updates.appVersion) {
            await locateCLI()
            await connection.refresh()
            installRevision += 1
        }
        Task { await refreshApps() }
        if let p = selectedProject { await open(p) }
        await selectedSession?.refresh()
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
        showHome = false
        selectedTeamPage = nil
        selectedAppID = nil
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
        // AppKit's own words (window titles, the menus, open panels) follow this at the next launch.
        if ProcessInfo.processInfo.environment["VITRIN_DEFAULTS_SUITE"] == nil {
            if let code = LanguageState.shared.code { UserDefaults.standard.set([code], forKey: "AppleLanguages") } else { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
        }
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
