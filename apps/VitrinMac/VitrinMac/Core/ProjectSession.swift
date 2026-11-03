import Foundation
import Observation

/// Everything the app knows about one open project: its Studio process, the overview, the running job, the log lines
/// and Claude's runs, kept current from the Studio's event stream.
@MainActor @Observable final class ProjectSession {
    let project: Project
    let process = StudioProcess()
    private(set) var client: StudioClient?
    private(set) var overview: Overview?
    private(set) var loadError: String?
    private(set) var connected = false
    private(set) var job: JobSummary?
    private(set) var finishedJob: JobSummary?
    private(set) var jobs: [JobSummary] = []
    private(set) var logs: [LogLine] = []
    private(set) var claudeRuns: [ClaudeRun] = []
    private(set) var claudeRunning = false
    private(set) var remotion: RemotionState?
    /// Bumps when files under metadata/ changed, so galleries reload.
    private(set) var changedTick = 0
    /// One-line messages for the toast area (newest last).
    private(set) var toasts: [Toast] = []
    private var eventsTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var seq = 0

    struct Toast: Identifiable, Hashable {
        enum Tone { case ok, info, error }
        let id = UUID()
        var text: String
        var tone: Tone
    }

    init(project: Project) { self.project = project }

    var isBusy: Bool { job != nil || claudeRunning }
    var isReady: Bool { client != nil }
    var url: URL? { client?.baseURL }

    // MARK: lifecycle

    func start(cli: CLILocation) async {
        guard client == nil else { return }
        loadError = nil
        do {
            let h = try await process.start(root: project.path, cli: cli)
            client = StudioClient(handshake: h)
            await refresh()
            subscribe()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func stop() {
        eventsTask?.cancel()
        eventsTask = nil
        process.stop()
        client = nil
        connected = false
        job = nil
    }

    func restart(cli: CLILocation) async {
        stop()
        await start(cli: cli)
    }

    // MARK: data

    func refresh() async {
        guard let client else { return }
        do {
            let o = try await client.overview()
            overview = o
            job = o.job
            claudeRunning = o.claude.running
            remotion = o.remotion
            loadError = nil
        } catch {
            if Self.isCancellation(error) { return }
            loadError = error.localizedDescription
        }
        if let list = try? await client.jobs() { jobs = list }
        if let c = try? await client.claude() {
            claudeRuns = c.runs
            claudeRunning = c.running != nil
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func subscribe() {
        eventsTask?.cancel()
        guard let client else { return }
        let url = client.url("/api/events")
        eventsTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    for try await e in StudioEvents.stream(url) {
                        guard let self else { return }
                        self.connected = true
                        self.handle(e)
                    }
                } catch {
                    // dropped connection: fall through and reconnect
                }
                guard let self, !Task.isCancelled else { return }
                self.connected = false
                if !self.process.isRunning { return }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func handle(_ e: StudioEvent) {
        switch e.name {
        case "hello":
            struct Hello: Decodable { var job: JobSummary?; var claude: ClaudeID?; var remotion: RemotionState? }
            struct ClaudeID: Decodable { var id: String }
            if let h = e.decode(Hello.self) {
                job = h.job
                claudeRunning = h.claude != nil
                remotion = h.remotion
            }
        case "log":
            if var line = e.decode(LogLine.self) {
                seq += 1
                line.seq = seq
                logs.append(line)
                if logs.count > 5000 { logs.removeFirst(logs.count - 5000) }
            }
        case "job":
            if let j = e.decode(JobSummary.self) {
                if j.isRunning {
                    job = j
                } else {
                    if job?.id == j.id || job == nil { job = nil }
                    finishedJob = j
                    announce(j)
                    scheduleRefresh()
                }
                if let i = jobs.firstIndex(where: { $0.id == j.id }) { jobs[i] = j } else { jobs.append(j) }
            }
        case "claude":
            if let ev = e.decode(ClaudeEvent.self) {
                switch ev.type {
                case "init": claudeRunning = true
                case "exit":
                    claudeRunning = false
                    scheduleRefresh()
                default: break
                }
                if let runId = ev.runId {
                    if let i = claudeRuns.firstIndex(where: { $0.id == runId }) {
                        claudeRuns[i].events.append(ev)
                        if ev.type == "exit" { claudeRuns[i].status = (ev.code ?? 1) == 0 ? "done" : "failed"; claudeRuns[i].endedAt = ISO8601DateFormatter().string(from: .now) }
                    } else {
                        Task { [weak self] in
                            guard let self, let c = try? await self.client?.claude() else { return }
                            self.claudeRuns = c.runs
                        }
                    }
                }
            }
        case "changed":
            changedTick += 1
            scheduleRefresh()
        case "remotion":
            if let r = e.decode(RemotionState.self) { remotion = r }
        default: break
        }
    }

    private func announce(_ j: JobSummary) {
        let name = L.job(j)
        switch j.status {
        case "ok": toast(L.t("toast.jobDone").replacingOccurrences(of: "{name}", with: name), .ok)
        case "needs-input": toast(L.t("toast.jobNeedsInput").replacingOccurrences(of: "{name}", with: name), .info)
        default: toast(L.t("toast.jobFailed").replacingOccurrences(of: "{name}", with: name) + (j.message.map { " — \($0)" } ?? ""), .error)
        }
        Notifier.shared.jobFinished(project: project.name, name: name, status: j.status)
    }

    func toast(_ text: String, _ tone: Toast.Tone = .info) {
        let t = Toast(text: text, tone: tone)
        toasts.append(t)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(tone == .error ? 8 : 4))
            self?.toasts.removeAll { $0.id == t.id }
        }
    }

    func dismiss(_ toast: Toast) { toasts.removeAll { $0.id == toast.id } }

    /// A request cancelled by a newer one (a page reload, a view that went away) is not an error worth a toast.
    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    func report(_ error: Error) {
        if Self.isCancellation(error) { return }
        report(error)
    }

    func clearLogs() { logs.removeAll() }

    // MARK: actions

    /// Starts a stage (one at a time; the server refuses while Claude works).
    func run(_ command: String, args: [String: JSONValue] = [:], force: Bool = false) async {
        guard let client else { return }
        do {
            job = try await client.run(command, args: args, force: force)
        } catch {
            report(error)
        }
    }

    func askClaude(stage: String? = nil, prompt: String? = nil, extra: String? = nil, fresh: Bool? = nil) async {
        guard let client else { return }
        do {
            try await client.askClaude(prompt: prompt, stage: stage, extra: extra, fresh: fresh)
            claudeRunning = true
            if let c = try? await client.claude() { claudeRuns = c.runs }
        } catch {
            report(error)
        }
    }

    func cancelClaude() async {
        try? await client?.cancelClaude()
    }

    func resetClaude() async {
        do {
            try await client?.resetClaude()
            toast(L.t("claude.newConversation"), .ok)
        } catch {
            report(error)
        }
    }

    func answer(_ q: StudioQuestion, _ answer: String) async {
        guard let client else { return }
        do {
            try await client.answer(question: q.id, answer: answer)
            toast(L.t("toast.answerSent"), .ok)
            claudeRunning = true
            scheduleRefresh()
        } catch {
            report(error)
        }
    }

    func chooseDesign(_ option: DesignSamples.Option) async {
        await askClaude(stage: "design", extra: "The user looked at the design samples in the Vitrin app and chose \(option.letter): “\(option.name)” (\(option.style)). That answers Step 2 of the brief: write art-direction.json with this choice (selectionReason: “The user chose \(option.letter).”) and continue with Step 3.")
        toast(L.t("toast.designChoiceSent").replacingOccurrences(of: "{name}", with: "\(option.letter) · \(option.name)"), .ok)
    }

    func readFile(_ path: String) async throws -> EditableFile {
        guard let client else { throw CLIError.failed("Studio is not running.") }
        return try await client.file(path)
    }

    func saveFile(_ path: String, text: String) async -> Bool {
        guard let client else { return false }
        do {
            try await client.save(path, text: text)
            toast(L.t("toast.saved"), .ok)
            return true
        } catch {
            report(error)
            return false
        }
    }

    func openInFinder(_ path: String) async {
        try? await client?.open(path, reveal: true)
    }

    /// The command behind a button, for developer mode.
    func cliHint(_ cmd: String) -> String? { AppSettings.shared.developerMode ? cmd : nil }
}
