import SwiftUI

/// One command: its help, a form built from its flags, Run, and the result.
struct AscCommandRunner: View {
    var path: [String]
    var appID: String?
    /// Flag values the page already knows (`app`, `version-id`): filled in when the command has that flag.
    var prefill: [String: String] = [:]
    @State private var help: AscHelp?
    @State private var values: [String: String] = [:]
    @State private var switches: [String: Bool] = [:]
    @State private var positional = ""
    @State private var allowChanges = false
    @State private var confirm = false
    @State private var running = false
    @State private var result: AscCLI.Result?
    @State private var error: String?

    private static let hidden: Set<String> = ["output", "pretty", "help", "api-debug", "debug", "report", "report-file", "retry-log", "strict-auth", "version", "profile", "read-only"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    IconBadge(symbol: "terminal.fill", colors: BadgeColors.deep, size: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("asc " + path.joined(separator: " ")).font(.title3.monospaced().weight(.semibold)).textSelection(.enabled)
                        if let h = help { Text(h.description).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    }
                }
                if let h = help {
                    if !h.usage.isEmpty { CopyCode(text: h.usage) }
                    if !h.details.isEmpty {
                        DisclosureGroup(L.t("asc.cmd.details")) {
                            Text(h.details).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                        }
                        .font(.callout)
                    }
                    if h.subcommands.isEmpty || h.flags.contains(where: { !Self.hidden.contains($0.name) }) {
                        form(h)
                    } else {
                        // A command group: it does nothing on its own, its subcommands do.
                        VStack(alignment: .leading, spacing: 6) {
                            SectionTitle(L.t("asc.cmd.subcommands"))
                            ForEach(h.subcommands) { e in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(e.name).font(.callout.monospaced()).frame(minWidth: 140, alignment: .leading)
                                    Text(e.summary).font(.callout).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .glassCard(padding: 14)
                    }
                } else if let error {
                    Text(error).foregroundStyle(.red)
                } else {
                    ProgressView()
                }
                if let r = result { output(r) }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            do {
                let h = try await AscHelp.load(path)
                help = h
                if let appID, h.flags.contains(where: { $0.name == "app" }) { values["app"] = appID }
                for (k, v) in prefill where h.flags.contains(where: { $0.name == k }) && !v.isEmpty { values[k] = v }
            } catch { self.error = error.localizedDescription }
        }
    }

    @ViewBuilder private func form(_ h: AscHelp) -> some View {
        let flags = h.flags.filter { !Self.hidden.contains($0.name) }
        let takesArgs = h.usage.contains("<") && !h.usage.hasSuffix("<subcommand> [flags]")
        VStack(alignment: .leading, spacing: 10) {
            if takesArgs {
                LabeledContent(L.t("asc.cmd.arguments")) { TextField(h.usage, text: $positional).textFieldStyle(.roundedBorder) }
            }
            ForEach(flags) { f in
                if f.isBool {
                    Toggle(isOn: Binding(get: { switches[f.name] ?? (f.defaultValue == "true") }, set: { switches[f.name] = $0 })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("--\(f.name)").font(.callout.monospaced())
                            Text(f.summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.switch).controlSize(.small)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text("--\(f.name)").font(.callout.monospaced())
                            if f.required { Text("*").foregroundStyle(.red) }
                        }
                        TextField(f.defaultValue.map { "\(L.t("asc.cmd.default")): \($0)" } ?? "", text: Binding(get: { values[f.name] ?? "" }, set: { values[f.name] = $0 }))
                            .textFieldStyle(.roundedBorder)
                        Text(f.summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if flags.isEmpty && !takesArgs { Text(L.t("asc.cmd.noFlags")).font(.callout).foregroundStyle(.secondary) }
            Divider()
            Toggle(L.t("asc.cmd.allowChanges"), isOn: $allowChanges).toggleStyle(.switch)
            Text(L.t("asc.cmd.allowChangesDetail")).font(.caption).foregroundStyle(.secondary)
            HStack {
                CopyCode(text: commandLine(h))
                Spacer()
                if running { ProgressView().controlSize(.small) }
                Button { if allowChanges { confirm = true } else { Task { await run(h) } } } label: { Label(L.t("asc.cmd.run"), systemImage: "play.fill") }
                    .buttonStyle(GradientButtonStyle(fullWidth: false)).disabled(running).keyboardShortcut(.return, modifiers: .command)
            }
        }
        .glassCard(padding: 16)
        .confirmationDialog(L.t("asc.cmd.confirm"), isPresented: $confirm, titleVisibility: .visible) {
            Button(L.t("asc.cmd.run"), role: .destructive) { Task { await run(h) } }
            Button(L.t("common.cancel"), role: .cancel) {}
        } message: { Text(commandLine(h)) }
    }

    private func arguments(_ h: AscHelp) -> [String] {
        var args = path
        args += positional.split(separator: " ").map(String.init)
        for f in h.flags where !Self.hidden.contains(f.name) {
            if f.isBool {
                if let on = switches[f.name], on != (f.defaultValue == "true") { args.append("--\(f.name)=\(on)") }
            } else if let v = values[f.name]?.trimmingCharacters(in: .whitespaces), !v.isEmpty {
                args += ["--\(f.name)", v]
            }
        }
        // asc requires --confirm for its own destructive commands; the dialog above is the user's confirmation.
        if allowChanges, h.flags.contains(where: { $0.name == "confirm" }), switches["confirm"] == nil { args.append("--confirm") }
        if h.flags.contains(where: { $0.name == "output" }) { args += ["--output", "json"] }
        return args
    }

    private func commandLine(_ h: AscHelp) -> String {
        "asc " + arguments(h).map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " ") + (allowChanges ? "" : " --read-only")
    }

    private func run(_ h: AscHelp) async {
        running = true
        defer { running = false }
        do { result = try await AscCLI.run(arguments(h), readOnly: !allowChanges, timeout: 600) } catch { self.error = error.localizedDescription }
    }

    @ViewBuilder private func output(_ r: AscCLI.Result) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(L.t("asc.cmd.result"))
                Pill(r.ok ? L.t("asc.cmd.ok") : L.t("asc.cmd.failed"), r.ok ? .ok : .err)
                Spacer()
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(r.stdout.isEmpty ? r.stderr : r.stdout, forType: .string) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help(L.t("common.copy"))
            }
            if let j = r.json, let items = Optional(JSONAPI.items(j)), !items.isEmpty, items.first?["attributes"] != nil {
                let keys = Array(Set(items.prefix(20).flatMap { ($0["attributes"]?.objectValue ?? [:]).filter { v in if case .object = v.value { return false }; if case .array = v.value { return false }; return true }.keys })).sorted().prefix(6)
                ResourceTable(items: items, columns: [("id", "id", .mono)] + keys.map { ($0, $0, ResourceTable.Kind.text) }, empty: "")
            }
            DisclosureGroup(L.t("asc.cmd.raw")) {
                ScrollView(.horizontal) {
                    Text(pretty(r)).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 320)
            }
            .font(.callout)
        }
        .glassCard(padding: 14)
    }

    private func pretty(_ r: AscCLI.Result) -> String {
        if let j = r.json, let d = try? JSONEncoder.pretty.encode(j), let s = String(data: d, encoding: .utf8) { return String(s.prefix(60_000)) }
        return String((r.stdout + (r.stderr.isEmpty ? "" : "\n" + r.stderr)).prefix(60_000))
    }
}

extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }()
}
