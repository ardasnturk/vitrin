import SwiftUI

/// The live log: every line the running stage prints, masked by the CLI, with the job's state on top.
struct LogPanel: View {
    var session: ProjectSession
    @State private var filter = ""
    @State private var autoScroll = true
    @State private var errorsOnly = false

    private var lines: [LogLine] {
        session.logs.filter { l in
            (!errorsOnly || l.level == "error" || l.level == "warn") && (filter.isEmpty || l.text.localizedCaseInsensitiveContains(filter))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "terminal").foregroundStyle(.secondary)
                // The status truncates and the controls keep their size: a narrow page (the Claude column open) never wraps the bar.
                Group {
                    if let j = session.job {
                        ProgressView().controlSize(.small)
                        Text(L.job(j)).font(.callout.weight(.medium))
                        Text(L.date(j.startedAt)).font(.caption).foregroundStyle(.secondary)
                    } else if let f = session.finishedJob {
                        Pill(L.t("job.\(f.status)"), Tone.ofJob(f.status))
                        Text(L.job(f)).font(.callout)
                        if let m = f.message { Text(m).font(.caption).foregroundStyle(.secondary) }
                    } else {
                        Text(L.t("log.idle")).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1).truncationMode(.tail).layoutPriority(-1)
                Spacer(minLength: 4)
                Toggle(L.t("log.errorsOnly"), isOn: $errorsOnly).toggleStyle(.checkbox).controlSize(.small).fixedSize()
                Toggle(L.t("log.autoScroll"), isOn: $autoScroll).toggleStyle(.checkbox).controlSize(.small).fixedSize()
                TextField(L.t("log.filter"), text: $filter).textFieldStyle(.roundedBorder).controlSize(.small).frame(minWidth: 70, idealWidth: 180, maxWidth: 180)
                Button { copyAll() } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).help(L.t("log.copy"))
                Button { session.clearLogs() } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help(L.t("log.clear"))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.bar)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(lines) { l in
                            Text(l.text.isEmpty ? " " : l.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(color(l.level))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(l.id)
                        }
                    }
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: session.logs.count) {
                    if autoScroll, let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func color(_ level: String) -> Color {
        switch level {
        case "error": return .red
        case "warn": return .orange
        case "ok": return .green
        case "step": return .accentColor
        case "dim": return .secondary
        case "result": return .purple
        default: return .primary
        }
    }

    private func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.map(\.text).joined(separator: "\n"), forType: .string)
    }
}
