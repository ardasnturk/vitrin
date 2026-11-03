import SwiftUI

/// The store text per language with the App Store Connect counters, and the validation issues next to their fields.
struct ListingView: View {
    var session: ProjectSession
    var overview: Overview
    @State private var locale = ""
    @State private var doc: [String: Any] = [:]
    @State private var original = ""
    @State private var fields: [String: String] = [:]
    @State private var loading = false
    @State private var saving = false
    @State private var loadError: String?

    private var path: String { "metadata/listing/\(locale).json" }
    private var dirty: Bool { !doc.isEmpty && fields != loadedFields }
    private var loadedFields: [String: String] { Dictionary(uniqueKeysWithValues: TextLimits.fields.map { ($0.key, doc[$0.key] as? String ?? "") }) }
    private var issues: [ValidationIssue] { (overview.validation?.issues ?? []).filter { $0.locale == locale && !$0.code.hasPrefix("image.") && !$0.code.hasPrefix("shot.") && !$0.code.hasPrefix("badge.") && !$0.code.hasPrefix("video.") } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("page.listing")).font(.title.bold())
                        Text(L.t("listing.intro")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L.t("listing.write")) { Task { await session.run("write") } }.buttonStyle(.borderedProminent).disabled(session.isBusy).cliHelp("vitrin write")
                    if overview.stage("write")?.brief != nil { ClaudeButton(session: session, overview: overview, stage: "write") }
                }
                Picker("", selection: $locale) { ForEach(overview.config?.locales ?? [], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).frame(maxWidth: 400)
                if let loadError {
                    Card { Text(loadError).foregroundStyle(.secondary); Text(L.t("listing.noFile")).font(.callout) }
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        editor.frame(maxWidth: .infinity)
                        VStack(spacing: 12) {
                            issuesCard
                            urlsCard
                        }.frame(width: 320)
                    }
                }
            }
            .padding(20)
        }
        .onAppear { if locale.isEmpty { locale = overview.config?.startLocale ?? "en-US" } }
        .task(id: "\(locale)-\(session.changedTick)") { if !dirty { await load() } }
        .safeAreaInset(edge: .bottom) {
            if dirty {
                HStack {
                    Text(L.t("listing.unsaved")).foregroundStyle(.secondary)
                    Spacer()
                    Button(L.t("common.revert")) { fields = loadedFields }
                    Button(saving ? L.t("common.saving") : L.t("common.save")) { Task { await save() } }.buttonStyle(.borderedProminent).disabled(saving)
                }
                .padding(10).background(.bar)
            }
        }
    }

    private var editor: some View {
        Card {
            if loading { ProgressView() }
            ForEach(TextLimits.fields, id: \.key) { f in
                FieldEditor(key: f.key, limit: f.limit, text: Binding(get: { fields[f.key] ?? "" }, set: { fields[f.key] = $0 }), issues: issues.filter { $0.field == f.key })
            }
        }
    }

    private var issuesCard: some View {
        Card(L.t("listing.issues")) {
            let general = issues.filter { i in !TextLimits.fields.contains { $0.key == i.field } }
            if issues.isEmpty { Text(overview.validation == nil ? L.t("listing.notValidated") : L.t("listing.noIssues")).foregroundStyle(.secondary) }
            ForEach(general) { IssueRow(issue: $0) }
            if !issues.isEmpty, general.count < issues.count { Text(L.t("listing.fieldIssues", issues.count - general.count)).font(.caption).foregroundStyle(.secondary) }
            Button(L.stage("validate")) { Task { await session.run("validate") } }.controlSize(.small).disabled(session.isBusy).cliHelp("vitrin validate")
        }
    }

    private var urlsCard: some View {
        Card(L.t("listing.urls")) {
            KeyValueRow(key: L.t("listing.support"), value: doc["supportUrl"] as? String ?? overview.config?.urls.support ?? "—")
            KeyValueRow(key: L.t("listing.privacy"), value: doc["privacyUrl"] as? String ?? overview.config?.urls.privacy ?? "—")
            KeyValueRow(key: L.t("listing.marketing"), value: doc["marketingUrl"] as? String ?? overview.config?.urls.marketing ?? "—")
            Text(L.t("listing.urlsHint")).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func load() async {
        guard !locale.isEmpty else { return }
        loading = true
        defer { loading = false }
        do {
            let f = try await session.readFile(path)
            guard f.exists, let obj = try JSONSerialization.jsonObject(with: Data(f.text.utf8)) as? [String: Any] else {
                loadError = L.t("listing.missing").replacingOccurrences(of: "{path}", with: path)
                doc = [:]; fields = [:]
                return
            }
            loadError = nil
            doc = obj
            original = f.text
            fields = loadedFields
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var out = doc
        for (k, v) in fields { out[k] = v }
        guard let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return }
        if await session.saveFile(path, text: String(decoding: data, as: UTF8.self)) {
            doc = out
            fields = loadedFields
        }
    }
}

struct FieldEditor: View {
    var key: String
    var limit: TextLimits.Limit
    @Binding var text: String
    var issues: [ValidationIssue]
    private var length: Int { TextLimits.length(text, limit) }
    private var over: Bool { length > limit.max || (limit.required && text.isEmpty) }
    private var multiline: Bool { limit.max > 200 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L.t("field.\(key)")).font(.callout.weight(.medium))
                if limit.required { Text("*").foregroundStyle(.red) }
                Spacer()
                Text("\(length) / \(limit.max)\(limit.bytes ? " B" : "")").font(.caption.monospacedDigit()).foregroundStyle(over ? .red : length > Int(Double(limit.max) * 0.9) ? .orange : .secondary)
            }
            if multiline {
                TextEditor(text: $text).font(.body).frame(minHeight: key == "description" ? 220 : 120)
                    .scrollContentBackground(.hidden).padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(over ? Color.red : Color(nsColor: .separatorColor)))
            } else {
                TextField("", text: $text).textFieldStyle(.roundedBorder)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(over ? Color.red : .clear))
            }
            if key == "keywords" {
                let terms = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                Text(L.t("field.keywordsHint", terms.count)).font(.caption).foregroundStyle(text.contains(", ") ? .orange : .secondary)
            }
            ForEach(issues) { IssueRow(issue: $0) }
        }
        .padding(.vertical, 4)
    }
}

struct IssueRow: View {
    var issue: ValidationIssue
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: issue.severity == "error" ? "xmark.octagon.fill" : issue.severity == "warning" ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(issue.severity == "error" ? .red : issue.severity == "warning" ? .orange : .blue).font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(issue.message).font(.caption).textSelection(.enabled)
                if let fix = issue.fix { Text("→ \(fix)").font(.caption).foregroundStyle(.secondary) }
                Text(issue.code).font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
        }
    }
}
