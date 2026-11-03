import SwiftUI

/// The run at a glance: the next step first, the stages in three groups with the status the server computed, and
/// everything that waits for the user (Claude's questions, blockers, the approve and upload clicks).
struct FlowView: View {
    @Environment(AppModel.self) private var model
    var session: ProjectSession
    var overview: Overview
    /// The brief shown in the sheet. `sheet(item:)`, not `isPresented` + `if let`: the latter built an empty sheet
    /// (no content, no close button) when the state was set in the same turn as the flag.
    struct Brief: Identifiable { var name: String; var text: String; var id: String { name } }
    @State private var brief: Brief?
    @State private var width: CGFloat = 1000

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                NextStepCard(session: session, overview: overview, showBrief: openBrief)
                // Two columns while there is room for both (the Claude column and the log take theirs); stacked otherwise,
                // so the stage rows never shrink to a word per line.
                if width >= 860 {
                    HStack(alignment: .top, spacing: 16) {
                        stageList.frame(maxWidth: .infinity)
                        VStack(spacing: 12) {
                            decisions
                            summary
                        }
                        .frame(width: 340)
                    }
                } else {
                    stageList
                    decisions
                    summary
                }
            }
            .padding(20)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .sheet(item: $brief) { b in
            BriefSheet(name: b.name, text: b.text, session: session) { brief = nil }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("page.flow")).font(.title.bold())
                Text(L.t("flow.intro")).foregroundStyle(.secondary)
            }
            Spacer()
            if let app = overview.app {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(app.name).font(.headline)
                    Text([app.bundleId, app.version.map { "v\($0)" }, app.platforms.joined(separator: ", ")].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var stageList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Pipeline.groups, id: \.key) { group in
                Text(L.t("flow.\(group.key)")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase).padding(.top, 8)
                ForEach(group.stages, id: \.self) { id in
                    if let view = overview.stage(id), let n = overview.flow.firstIndex(where: { $0.id == id }) {
                        StageRow(session: session, overview: overview, view: view, n: n + 1, showBrief: openBrief)
                    }
                }
            }
        }
    }

    private var decisions: some View {
        Card(L.t("flow.pending")) {
            let list = overview.pendingDecisions.filter { d in
                switch d {
                case .blocker(let b): return b.code != overview.next?.blocker
                case .question(let q): return q.id != overview.next?.question
                case .stage: return true
                }
            }
            if list.isEmpty {
                Text(L.t("flow.noDecisions")).foregroundStyle(.secondary)
            } else {
                ForEach(list) { d in DecisionView(decision: d, session: session, overview: overview) }
            }
        }
    }

    private var summary: some View {
        Card(L.t("flow.summary")) {
            if let cfg = overview.config {
                KeyValueRow(key: L.t("summary.locales"), value: cfg.locales.joined(separator: ", "))
                KeyValueRow(key: L.t("summary.primary"), value: cfg.primaryLocale)
                KeyValueRow(key: L.t("summary.uploader"), value: cfg.uploader ?? L.t("summary.notChosen"))
                KeyValueRow(key: L.t("summary.capture"), value: cfg.capture)
                KeyValueRow(key: L.t("summary.language"), value: cfg.language ?? "en")
                KeyValueRow(key: L.t("summary.screenshots"), value: overview.screenshots.map { "\($0.key): \($0.value.count)" }.sorted().joined(separator: " · "))
                KeyValueRow(key: L.t("summary.previews"), value: overview.previews.map { "\($0.key): \($0.value.count)" }.sorted().joined(separator: " · "))
                if let v = overview.validation { KeyValueRow(key: L.t("summary.validation"), value: v.ok ? L.t("review.validationOk") : L.t("review.validationErrors", v.counts.error)) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("summary.tools")).foregroundStyle(.secondary).font(.callout)
                FlowLayout(spacing: 6) {
                    ToolPill("asc", overview.tools.asc)
                    ToolPill("fastlane", overview.tools.fastlane)
                    ToolPill("ffmpeg", overview.tools.ffmpeg)
                    ToolPill("claude", overview.tools.claude)
                }
            }
            Text("Vitrin \(overview.version) · \(overview.root)").font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
        }
    }

    private func openBrief(_ name: String) {
        Task {
            do {
                let f = try await session.readFile("metadata/briefs/\(name).md")
                brief = Brief(name: name, text: f.text)
            } catch {
                session.report(error)
            }
        }
    }
}

struct ToolPill: View {
    var name: String
    var version: String?
    init(_ name: String, _ version: String?) {
        self.name = name
        self.version = version
    }
    var body: some View { Pill(version.map { "\(name) \($0)" } ?? name, version == nil ? .neutral : .ok).help(version == nil ? L.t("common.missing") : L.t("common.installed")) }
}

/// One stage: its number (or check), title, hint, status and the single action it offers; the rest behind “…”.
struct StageRow: View {
    @Environment(AppModel.self) private var model
    var session: ProjectSession
    var overview: Overview
    var view: StageView
    var n: Int
    var showBrief: (String) -> Void

    private var running: Bool { session.job?.command == Pipeline.command(for: view.id)?.command && view.id != "upload" }
    private var missingTool: Blocker? { overview.blockers.first { $0.stage == view.id && $0.severity == "error" && $0.params["install"] != nil } }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StepNumber(n: n, done: view.stageStatus == .done && !running, tone: Tone.of(view.stageStatus), running: running)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Button(L.stage(view.id)) { model.selectedPage = Pipeline.page(for: view.id) }.buttonStyle(.link).font(.body.weight(.medium))
                    if view.isOptional { Text("· \(L.t("flow.optional"))").font(.caption).foregroundStyle(.secondary) }
                }
                Text(L.hint(view.id)).font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if running { Pill(L.t("common.running"), .accent) } else { Pill(L.status(view.stageStatus), Tone.of(view.stageStatus)) }
                    if let at = view.completedAt, view.stageStatus != .notRun { Text(L.date(at)).font(.caption).foregroundStyle(.secondary) }
                    let reason = L.reason(view, overview)
                    if !reason.isEmpty { Text("· \(reason)").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    if let note = view.note { Text("· \(note)").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
            }
            Spacer()
            HStack(spacing: 6) {
                primaryAction
                if let c = Pipeline.command(for: view.id) {
                    Menu {
                        if let b = view.brief {
                            Button(L.t("flow.brief")) { showBrief(b) }
                            Button(L.t("common.run")) { Task { await session.run(c.command, args: c.args) } }
                        }
                        Button(L.t("flow.rerun")) { Task { await session.run(c.command, args: c.args, force: true) } }
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).frame(width: 24).disabled(session.isBusy)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(running ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        .opacity(view.stageStatus == .skipped ? 0.6 : 1)
    }

    @ViewBuilder private var primaryAction: some View {
        if view.stageStatus == .skipped {
            EmptyView()
        } else if view.stageStatus == .needsUser || view.id == "upload" {
            Button(L.t("flow.goToPage")) { model.selectedPage = Pipeline.page(for: view.id) }
                .buttonStyle(view.stageStatus == .needsUser ? AnyButtonStyle(.borderedProminent) : AnyButtonStyle(.bordered)).controlSize(.small)
        } else if let b = view.brief {
            ClaudeButton(session: session, overview: overview, stage: b, small: true)
        } else if let c = Pipeline.command(for: view.id) {
            Button(L.t("common.run")) { Task { await session.run(c.command, args: c.args) } }
                .buttonStyle(view.stageStatus != .done && !view.isOptional ? AnyButtonStyle(.borderedProminent) : AnyButtonStyle(.bordered))
                .controlSize(.small)
                .disabled(session.isBusy || missingTool != nil)
                .help(missingTool.map(L.blocker) ?? (AppSettings.shared.developerMode ? "vitrin \(c.command)" : ""))
        }
    }
}

/// `.borderedProminent` or `.bordered` chosen at runtime.
struct AnyButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: PrimitiveButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// “Let Claude do it”: runs the user's Claude Code on a stage's brief.
struct ClaudeButton: View {
    @Environment(AppModel.self) private var model
    var session: ProjectSession
    var overview: Overview
    var stage: String
    var small = false
    var body: some View {
        Button { Task { await session.askClaude(stage: stage); model.showClaude = true } } label: { Label(L.t("claude.doIt"), systemImage: "sparkles") }
            .buttonStyle(.borderedProminent)
            .controlSize(small ? .small : .regular)
            .disabled(session.isBusy || !overview.claude.available)
            .help(overview.claude.available ? L.t("claude.doItHint") : L.t("claude.missing"))
    }
}

/// One sentence and one button: what to do now.
struct NextStepCard: View {
    @Environment(AppModel.self) private var model
    var session: ProjectSession
    var overview: Overview
    var showBrief: (String) -> Void

    var body: some View {
        Card(L.t("flow.nextStep"), accent: true) {
            if let next = overview.next {
                Text(L.stage(next.stage)).font(.title3.weight(.semibold))
                body(for: next)
            } else {
                Text(L.t("flow.allDone"))
            }
        }
    }

    @ViewBuilder private func body(for next: NextStep) -> some View {
        let view = overview.stage(next.stage)
        let reason = view.map { L.reason($0, overview) } ?? ""
        switch next.action {
        case "answer":
            if let q = overview.questions.first(where: { $0.id == next.question }) { QuestionCard(question: q, session: session, overview: overview) }
        case "fix", "decide":
            if let b = overview.blocker(next.blocker ?? "") {
                if next.action == "fix" { Text(L.t("flow.fixFirst")).foregroundStyle(.secondary) }
                BlockerCard(blocker: b, session: session, overview: overview, primary: true)
            }
        case "claude":
            if let b = view?.brief {
                Text(L.t("flow.nextClaude").replacingOccurrences(of: "{stage}", with: L.stage(next.stage)))
                HStack {
                    ClaudeButton(session: session, overview: overview, stage: b)
                    Button(L.t("flow.brief")) { showBrief(b) }
                }
            }
        case "approve", "upload", "finalize":
            Text(next.action == "finalize" ? L.t("flow.nextFinalize") : (reason.isEmpty ? L.t(next.action == "upload" ? "flow.decisionUpload" : "flow.nextApprove") : reason))
            Button(L.t(next.action == "approve" ? "flow.openReview" : "flow.openUpload")) { model.selectedPage = Pipeline.page(for: next.stage) }.buttonStyle(.borderedProminent)
        default:
            Text(reason.isEmpty ? L.t("flow.nextRun").replacingOccurrences(of: "{stage}", with: L.stage(next.stage)) : reason)
            if let c = Pipeline.command(for: next.stage) {
                Button(L.t("common.run")) { Task { await session.run(c.command, args: c.args) } }.buttonStyle(.borderedProminent).disabled(session.isBusy).cliHelp("vitrin \(c.command)")
            }
        }
    }
}

/// A pending decision: Claude's question, a blocker with its fixes, or a stage waiting for the user's click.
struct DecisionView: View {
    @Environment(AppModel.self) private var model
    var decision: PendingDecision
    var session: ProjectSession
    var overview: Overview
    var body: some View {
        switch decision {
        case .question(let q): QuestionCard(question: q, session: session, overview: overview)
        case .blocker(let b): BlockerCard(blocker: b, session: session, overview: overview)
        case .stage(let s):
            VStack(alignment: .leading, spacing: 8) {
                let r = L.reason(s, overview)
                Text(r.isEmpty ? L.t(s.id == "upload" ? "flow.decisionUpload" : "flow.decisionApprove") : r)
                Button(L.t(s.id == "upload" ? "flow.openUpload" : "flow.openReview")) { model.selectedPage = Pipeline.page(for: s.id) }.buttonStyle(.borderedProminent).controlSize(.small)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
        }
    }
}

/// One blocker: what is wrong, and its one-click fixes or the install command to copy.
struct BlockerCard: View {
    @Environment(AppModel.self) private var model
    var blocker: Blocker
    var session: ProjectSession
    var overview: Overview
    var primary = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: blocker.severity == "error" ? "exclamationmark.octagon.fill" : blocker.severity == "decision" ? "questionmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(blocker.severity == "error" ? .red : blocker.severity == "decision" ? .accentColor : .orange)
                Text(L.blocker(blocker)).textSelection(.enabled)
            }
            if blocker.code == "design-choice" {
                DesignOptions(session: session, overview: overview)
            } else {
                HStack(spacing: 8) {
                    ForEach(Array(blocker.fixes.enumerated()), id: \.element.id) { i, fix in
                        Button(L.fix(fix, blocker)) { Task { await session.run(fix.command, args: fix.args) } }
                            .buttonStyle(primary && i == 0 ? AnyButtonStyle(.borderedProminent) : AnyButtonStyle(.bordered)).controlSize(.small).disabled(session.isBusy)
                    }
                    if let install = blocker.params["install"]?.stringValue { CopyCode(text: install) }
                    if blocker.code == "keys-missing" {
                        SettingsLink { Text(L.t("flow.accountSettings")) }.controlSize(.small).accessibilityIdentifier("flow.accountSettings")
                    } else if blocker.fixes.isEmpty, blocker.params["install"] == nil, blocker.stage != "upload" {
                        Button(L.t("flow.goToPage")) { model.selectedPage = Pipeline.page(for: blocker.stage) }.controlSize(.small)
                    }
                }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill((blocker.severity == "error" ? Color.red : blocker.severity == "decision" ? Color.accentColor : Color.orange).opacity(0.08)))
    }
}

/// One button per design sample (and the store preview to compare them): a click hands the choice to Claude.
struct DesignOptions: View {
    @Environment(AppModel.self) private var model
    var session: ProjectSession
    var overview: Overview
    var body: some View {
        FlowLayout(spacing: 6) {
            if overview.samples?.storePreview != nil {
                Button(L.t("visuals.openSamples")) { model.selectedPage = .visuals }.controlSize(.small)
            }
            ForEach(overview.samples?.options ?? []) { o in
                Button("\(o.letter) · \(o.name)") { Task { await session.chooseDesign(o); model.showClaude = true } }
                    .buttonStyle(.borderedProminent).controlSize(.small).disabled(session.isBusy || !overview.claude.available).help(o.style)
            }
        }
    }
}

/// A question Claude left: its options as buttons, or an answer in the user's own words.
struct QuestionCard: View {
    @Environment(AppModel.self) private var model
    var question: StudioQuestion
    var session: ProjectSession
    var overview: Overview
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L.t("claude.asks"), systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
            Text(question.question).font(.body.weight(.medium)).textSelection(.enabled)
            if !question.options.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(question.options, id: \.value) { o in
                        Button(o.label) { Task { await session.answer(question, o.value); model.showClaude = true } }
                            .buttonStyle(.borderedProminent).controlSize(.small).disabled(disabled)
                    }
                }
            }
            HStack {
                TextField(question.options.isEmpty ? L.t("claude.answer") : L.t("claude.answerOwnWords"), text: $text)
                    .textFieldStyle(.roundedBorder).disabled(disabled)
                    .onSubmit { send() }
                Button(L.t("claude.answer")) { send() }.controlSize(.small).disabled(disabled || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
    }
    private var disabled: Bool { session.isBusy || !overview.claude.available }
    private func send() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        Task { await session.answer(question, t); text = ""; model.showClaude = true }
    }
}

struct BriefSheet: View {
    @Environment(AppModel.self) private var model
    var name: String
    var text: String
    var session: ProjectSession
    var close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("flow.briefTitle").replacingOccurrences(of: "{stage}", with: L.stage(name))).font(.headline)
                    Text(L.t("flow.briefIntro")).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if let o = session.overview { ClaudeButton(session: session, overview: o, stage: name) }
                Button(L.t("common.close")) { close() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("brief.close")
            }
            ScrollView {
                Text(text).font(.callout.monospaced()).textSelection(.enabled).padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            Text("metadata/briefs/\(name).md").font(.caption.monospaced()).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(minWidth: 680, idealWidth: 760, minHeight: 520, idealHeight: 640)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brief.sheet")
    }
}

/// Wraps its children onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = layout(proposal: proposal, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (width: CGFloat, height: CGFloat) {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > maxW, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
            width = max(width, x)
        }
        return (width, y + rowH)
    }
}
