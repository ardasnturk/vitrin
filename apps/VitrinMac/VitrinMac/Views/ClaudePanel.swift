import SwiftUI

/// The Claude inspector: the user's Claude Code running the creative stages inside the project, and a prompt field.
struct ClaudePanel: View {
    @Environment(AppSettings.self) private var settings
    var session: ProjectSession
    @State private var prompt = ""
    @State private var expanded: Set<String> = []

    private var available: Bool { session.overview?.claude.available ?? false }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Claude", systemImage: "sparkles").font(.headline).accessibilityIdentifier("claude.title")
                ClaudeModelMenu().accessibilityIdentifier("claude.model")
                Spacer()
                if session.claudeRunning {
                    ProgressView().controlSize(.small)
                    Button(L.t("common.stop")) { Task { await session.cancelClaude() } }.controlSize(.small)
                } else {
                    Button(L.t("claude.newConversation")) { Task { await session.resetClaude() } }.controlSize(.small).disabled(session.claudeRuns.isEmpty)
                }
            }
            .padding(10)
            Divider()
            if !available {
                VStack(spacing: 8) {
                    Text(L.t("claude.missing")).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    CopyCode(text: "npm install -g @anthropic-ai/claude-code")
                }.padding(16)
                Spacer()
            } else if session.claudeRuns.isEmpty {
                EmptyHint(text: L.t("claude.idle"), symbol: "sparkles")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(session.claudeRuns) { run in RunView(run: run, expanded: expanded.contains(run.id) || run.id == session.claudeRuns.last?.id) { toggle(run.id) } }
                        }
                        .padding(10)
                    }
                    .onChange(of: session.claudeRuns.last?.events.count) {
                        if let last = session.claudeRuns.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            Divider()
            HStack(alignment: .bottom) {
                TextField(L.t("claude.placeholder"), text: $prompt, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
                    .onSubmit { send() }
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }.buttonStyle(.borderless)
                    .disabled(!available || session.isBusy || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
        }
    }

    private func toggle(_ id: String) { if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) } }

    private func send() {
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        prompt = ""
        Task { await session.askClaude(prompt: p) }
    }
}

struct RunView: View {
    var run: ClaudeRun
    var expanded: Bool
    var toggle: () -> Void

    /// The model Claude Code reported in its init line (the alias resolved to a full name).
    private var model: String? { run.events.first(where: { $0.type == "init" })?.model }

    private var title: String {
        guard let l = run.label else { return run.prompt }
        switch l.kind {
        case "brief": return L.t("claude.runBrief").replacingOccurrences(of: "{stage}", with: L.stage(l.stage ?? ""))
        case "answer": return L.t("claude.runAnswer").replacingOccurrences(of: "{answer}", with: l.answer ?? "")
        default: return l.text ?? run.prompt
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption).foregroundStyle(.secondary)
                    Text(title).font(.callout.weight(.medium)).lineLimit(2)
                    Spacer()
                    Pill(L.t("claude.\(run.status)"), run.status == "running" ? .accent : run.status == "done" ? .ok : run.status == "cancelled" ? .neutral : .err)
                }
            }
            .buttonStyle(.plain)
            if let model { Text(ClaudeModel.shortName(model)).font(.caption2.monospaced()).foregroundStyle(.tertiary) }
            if expanded {
                ForEach(Array(run.events.enumerated()), id: \.offset) { _, e in EventView(event: e) }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .id(run.id)
    }
}

struct EventView: View {
    var event: ClaudeEvent
    var body: some View {
        switch event.type {
        case "text":
            Text(event.text ?? "").font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        case "tool":
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "wrench").font(.caption).foregroundStyle(.secondary)
                Text(event.name ?? "").font(.caption.weight(.medium))
                Text(event.summary ?? "").font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            }
        case "result":
            HStack(spacing: 6) {
                Image(systemName: event.ok == true ? "checkmark.circle" : "xmark.circle").foregroundStyle(event.ok == true ? .green : .red).font(.caption)
                Text([event.turns.map { "\($0) turns" }, event.costUsd.map { String(format: "$%.2f", $0) }, event.durationMs.map { String(format: "%.0fs", $0 / 1000) }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
        case "error":
            Text(event.text ?? "").font(.caption).foregroundStyle(.red).textSelection(.enabled)
        case "init":
            Text([event.model, event.sessionId.map { String($0.prefix(8)) }].compactMap { $0 }.joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary)
        default:
            EmptyView()
        }
    }
}

/// The Claude Code models the app offers by alias; anything else is typed in Settings.
@MainActor enum ClaudeModel {
    static let aliases: [(alias: String, label: String)] = [("fable", "Fable"), ("opus", "Opus"), ("sonnet", "Sonnet"), ("haiku", "Haiku")]

    /// "claude-opus-5-5" → "opus 5.5"; an alias or an unknown name stays as it is.
    static func shortName(_ model: String) -> String {
        let parts = model.split(separator: "-").map(String.init)
        guard parts.count >= 3, parts[0] == "claude" else { return model }
        let version = parts.dropFirst(2).filter { Int($0) != nil }.joined(separator: ".")
        return version.isEmpty ? parts[1] : "\(parts[1]) \(version)"
    }

    static func label(_ setting: String) -> String {
        let s = setting.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return L.t("settings.claudeModelDefault") }
        return aliases.first(where: { $0.alias == s })?.label ?? s
    }
}

/// A compact menu for Settings → Claude model, in the Claude column's header.
struct ClaudeModelMenu: View {
    @Environment(AppSettings.self) private var settings
    var body: some View {
        @Bindable var settings = settings
        Menu {
            Picker(L.t("claude.model"), selection: $settings.claudeModel) {
                Text(L.t("settings.claudeModelDefault")).tag("")
                ForEach(ClaudeModel.aliases, id: \.alias) { Text($0.label).tag($0.alias) }
                if !settings.claudeModel.isEmpty, !ClaudeModel.aliases.contains(where: { $0.alias == settings.claudeModel }) { Text(settings.claudeModel).tag(settings.claudeModel) }
            }
            .pickerStyle(.inline)
            Divider()
            SettingsLink { Text(L.t("settings.claudeModelMore")) }
        } label: {
            Label(ClaudeModel.label(settings.claudeModel), systemImage: "cpu").font(.caption).foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L.t("settings.claudeModelHint"))
    }
}
