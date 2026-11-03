import SwiftUI

/// The upload as a checklist: uploader → keys (names only) → approved content → dry-run plan → the upload after the
/// user's explicit confirmation; read-back, finalize and submit follow.
struct UploadView: View {
    @Environment(AppModel.self) private var model
    var session: ProjectSession
    var overview: Overview
    @State private var flags = Flags()
    @State private var planJob: Job?
    @State private var confirmUpload = false
    @State private var typed = ""
    @State private var deleteResearch: Bool?
    @State private var submitBundle = ""
    @State private var doctor: Job?

    struct Flags {
        var creatives = false, cpp = false, events = false, experiment = false, skipScreenshots = false
        var args: [String: JSONValue] {
            var a: [String: JSONValue] = ["creatives": .bool(creatives), "cpp": .bool(cpp), "events": .bool(events), "skipScreenshots": .bool(skipScreenshots)]
            if experiment { a["experiment"] = .bool(true) }
            return a
        }
    }

    private var uploader: String? { overview.config?.uploader }
    private var toolVersion: String? { uploader == "asc" ? overview.tools.asc : uploader != nil ? overview.tools.fastlane : nil }
    private var uploaderOk: Bool { uploader != nil && toolVersion != nil }
    private var keysOk: Bool { overview.missingKeys.isEmpty }
    private var approved: Bool { overview.approval?.valid ?? false }
    private var planOk: Bool { planJob?.status == "ok" }
    private var uploaded: ApprovalSummary.Upload? { overview.approval?.upload }
    private var waiting: [String] { [uploaderOk ? nil : L.t("upload.stepUploader"), keysOk ? nil : L.t("upload.stepKeys"), approved ? nil : L.t("upload.stepApproval")].compactMap { $0 } }
    private var appName: String { overview.app?.name ?? "" }
    /// The key names the upload needs for this app's platforms: present ones from the env key list, missing ones from the overview.
    private var keyNames: [(name: String, present: Bool)] {
        let platforms = overview.app?.platforms ?? ["ios"]
        var names = platforms.contains(where: { $0 != "android" }) ? ["ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH"] : []
        if platforms.contains("android") { names.append("GOOGLE_PLAY_JSON_KEY_PATH") }
        for m in overview.missingKeys where !names.contains(m) { names.append(m) }
        return names.map { ($0, !overview.missingKeys.contains($0)) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("page.upload")).font(.title.bold())
                    Text(L.t("upload.intro")).foregroundStyle(.secondary)
                }
                Step(n: 1, ok: uploaderOk, title: L.t("upload.stepUploader")) {
                    Picker("", selection: Binding(get: { uploader ?? "" }, set: { v in Task { await session.run("select", args: ["uploader": .string(v)]) } })) {
                        Text("asc CLI \(overview.tools.asc.map { "· \($0)" } ?? "· \(L.t("common.missing"))")").tag("asc")
                        Text("fastlane deliver \(overview.tools.fastlane.map { "· \($0)" } ?? "· \(L.t("common.missing"))")").tag("deliver")
                    }.pickerStyle(.radioGroup).disabled(session.isBusy)
                    Text(L.t(uploader == "asc" ? "upload.ascHint" : "upload.deliverHint")).font(.caption).foregroundStyle(.secondary)
                    if uploader == nil { Text(L.t("blocker.uploader-unset")).font(.callout).foregroundStyle(.red) }
                    if let u = uploader, toolVersion == nil { CopyCode(text: u == "asc" ? "brew install asc" : "bundle install") }
                }
                Step(n: 2, ok: keysOk, title: L.t("upload.stepKeys"), actions: AnyView(Button(L.t("job.doctor")) { Task { await session.run("doctor") } }.controlSize(.small).disabled(session.isBusy).cliHelp("vitrin doctor"))) {
                    Text(L.t("upload.keysIntro")).font(.callout).foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(keyNames, id: \.name) { k in Pill(k.name + (k.present ? " ✓" : ""), k.present ? .ok : .err) }
                    }
                    if !keysOk { Text(L.t("upload.keysWhere")).font(.caption).foregroundStyle(.secondary) }
                    if let d = doctor, let checks = d.result?.objectValue?["checks"]?.arrayValue { DoctorChecks(checks: checks) }
                }
                Step(n: 3, ok: approved, title: L.t("upload.stepApproval")) {
                    if approved, let a = overview.approval { Text("\(L.t("review.approved")) · \(L.date(a.approvedAt))").font(.callout) }
                    else {
                        if let a = overview.approval, a.status == "approved" { Text(L.t("review.approvalInvalid").replacingOccurrences(of: "{reason}", with: L.reason(StageView(id: "review", status: "blocked", reason: a.problem), overview))).font(.callout).foregroundStyle(.red) }
                        else { Text(L.t("flow.decisionApprove")).font(.callout) }
                        Button(L.t("flow.openReview")) { model.selectedPage = .review }.controlSize(.small)
                    }
                }
                Step(n: 4, ok: planOk, title: L.t("upload.stepPlan")) {
                    Text(L.t("upload.dryRunHint")).font(.callout).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Toggle(L.t("upload.creatives"), isOn: $flags.creatives)
                        Toggle(L.t("upload.cpp"), isOn: $flags.cpp).disabled(overview.files["cpp"] != true)
                        Toggle(L.t("upload.events"), isOn: $flags.events)
                        Toggle(L.t("upload.experiment"), isOn: $flags.experiment).disabled(overview.files["experiments"] != true)
                        Toggle(L.t("upload.skipScreenshots"), isOn: $flags.skipScreenshots)
                    }.toggleStyle(.checkbox).font(.callout)
                    Button(L.t("upload.dryRun")) { Task { await session.run("upload", args: flags.args.merging(["dryRun": true]) { $1 }) } }.buttonStyle(.borderedProminent).disabled(session.isBusy).cliHelp("vitrin upload --dry-run").accessibilityIdentifier("upload.dryRun")
                    if let p = planJob, !p.summary.isRunning {
                        HStack {
                            Pill("\(L.t("upload.lastPlan")) · \(L.date(p.endedAt))", Tone.ofJob(p.status))
                            if let m = p.message { Text(m).font(.callout) }
                        }
                        PlanTable(session: session, tick: session.changedTick)
                        DisclosureGroup(L.t("upload.planLog")) {
                            ScrollView { Text(p.lines.map(\.text).joined(separator: "\n")).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                                .frame(maxHeight: 260).padding(8).background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                        }.font(.callout)
                    }
                }
                Step(n: 5, ok: uploaded != nil && uploaded?.overallHash == overview.approval?.overallHash, title: L.t("upload.stepUpload")) {
                    Button(L.t("upload.now")) { typed = ""; confirmUpload = true }.buttonStyle(.borderedProminent).tint(.red).disabled(!waiting.isEmpty || session.isBusy).cliHelp("vitrin upload --yes").accessibilityIdentifier("upload.now")
                    if !waiting.isEmpty { Text(L.t("upload.waitsFor").replacingOccurrences(of: "{steps}", with: waiting.joined(separator: ", "))).font(.callout).foregroundStyle(.red) }
                }
                Text(L.t("upload.after")).font(.title3.bold()).padding(.top, 8)
                HStack(alignment: .top, spacing: 14) {
                    readBackCard.frame(maxWidth: .infinity)
                    finalizeCard.frame(maxWidth: .infinity)
                    submitCard.frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
        .onChange(of: session.job?.id) { Task { await trackJobs() } }
        .onChange(of: session.finishedJob?.id) { Task { await trackJobs() } }
        .task { await trackJobs() }
        .sheet(isPresented: $confirmUpload) { uploadConfirmation }
    }

    private var readBackCard: some View {
        Card(L.t("upload.readBack")) {
            if let u = uploaded {
                KeyValueRow(key: L.t("upload.uploaded"), value: L.date(u.uploadedAt))
                HStack { Text(L.t("upload.readBack")).foregroundStyle(.secondary).font(.callout).frame(width: 140, alignment: .leading); Pill(u.readBack == "ok" ? L.t("upload.readBackOk") : L.t("upload.differences", u.differences.count), u.readBack == "ok" ? .ok : .err) }
                ForEach(u.differences, id: \.self) { Text($0).font(.caption) }
            } else { Text(L.t("upload.notUploaded")).foregroundStyle(.secondary).font(.callout) }
        }
    }

    private var finalizeCard: some View {
        Card(L.t("upload.finalize")) {
            Text(L.t("upload.finalizeIntro")).font(.callout).foregroundStyle(.secondary)
            if let f = overview.approval?.finalized {
                Pill("\(f.mode) · \(L.date(f.at))", .ok)
            } else {
                Picker("", selection: Binding(get: { deleteResearch.map { $0 ? "delete" : "keep" } ?? "" }, set: { deleteResearch = $0 == "delete" ? true : $0 == "keep" ? false : nil })) {
                    Text(L.t("upload.deleteResearch")).tag("delete")
                    Text(L.t("upload.keepResearch")).tag("keep")
                }.pickerStyle(.radioGroup).font(.callout)
                Button(L.t("upload.finalize")) { Task { await session.run("finalize", args: ["checked": true, "deleteResearch": .bool(deleteResearch ?? false)]) } }
                    .disabled(session.isBusy || uploaded == nil || deleteResearch == nil).cliHelp("vitrin finalize --checked")
                if uploaded == nil { Text(L.t("upload.finalizeAfter")).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }

    private var submitCard: some View {
        Card(L.t("upload.submit")) {
            Text(L.t("upload.submitHint")).font(.callout).foregroundStyle(.secondary)
            TextField(overview.app?.bundleId ?? "bundle id", text: $submitBundle).textFieldStyle(.roundedBorder).font(.body.monospaced())
            Button(L.t("upload.submit")) { Task { await session.run("submit", args: ["confirm": .string(submitBundle)]) } }.tint(.red)
                .disabled(session.isBusy || submitBundle.isEmpty || submitBundle != overview.app?.bundleId).cliHelp("vitrin submit --confirm \(overview.app?.bundleId ?? "")")
        }
    }

    private var uploadConfirmation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L.t("upload.now"), systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(.red)
            Text(L.t("upload.confirmText"))
            Text(appName).font(.title3.bold())
            TextField(L.t("upload.typeName"), text: $typed).textFieldStyle(.roundedBorder)
            Text(L.t("upload.confirmHint")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L.t("common.cancel")) { confirmUpload = false }.keyboardShortcut(.cancelAction)
                Button(L.t("upload.now")) {
                    confirmUpload = false
                    Task { await session.run("upload", args: flags.args.merging(["yes": true]) { $1 }) }
                }.buttonStyle(.borderedProminent).tint(.red).disabled(typed.trimmingCharacters(in: .whitespaces) != appName.trimmingCharacters(in: .whitespaces))
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    /// Keeps the last dry run and doctor jobs this page cares about.
    private func trackJobs() async {
        guard let c = session.client else { return }
        if let j = session.jobs.last(where: { $0.command == "upload" && $0.isDryRun }), let full = try? await c.job(j.id) { planJob = full }
        if let j = session.jobs.last(where: { $0.command == "doctor" }), let full = try? await c.job(j.id) { doctor = full }
    }
}

struct Step<Content: View>: View {
    var n: Int
    var ok: Bool
    var title: String
    var actions: AnyView? = nil
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StepNumber(n: n, done: ok, tone: ok ? .ok : .neutral)
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text(title).font(.headline); Spacer(); actions }
                content
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ok ? Color.green.opacity(0.4) : Color(nsColor: .separatorColor)))
    }
}

/// metadata/upload-plan.json as a table.
struct PlanTable: View {
    var session: ProjectSession
    var tick: Int
    @State private var items: [PlanItem] = []
    @State private var meta = ""

    struct PlanItem: Decodable, Identifiable {
        var area: String
        var locale: String?
        var field: String?
        var target: String?
        var change: String
        var local: String?
        var remote: String?
        var via: String?
        var file: String?
        var id: String { [area, locale, field, target, file, local].compactMap { $0 }.joined(separator: "|") }
    }
    struct Plan: Decodable {
        var generatedAt: String?
        var bundleId: String?
        var uploader: String?
        var remoteKnown: Bool?
        var items: [PlanItem]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !items.isEmpty {
                Text(meta).font(.caption).foregroundStyle(.secondary)
                Table(items) {
                    TableColumn(L.t("plan.area"), value: \.area).width(100)
                    TableColumn(L.t("plan.locale")) { Text($0.locale ?? "") }.width(60)
                    TableColumn(L.t("plan.field")) { Text($0.field ?? $0.target ?? $0.file ?? "").lineLimit(1) }.width(min: 120)
                    TableColumn(L.t("plan.change")) { i in Pill(i.change, i.change == "unchanged" ? .neutral : i.change == "unknown" ? .info : .warn) }.width(90)
                    TableColumn(L.t("plan.local")) { Text($0.local ?? "").lineLimit(1).truncationMode(.tail) }
                    TableColumn(L.t("plan.via")) { Text($0.via ?? "") }.width(70)
                }
                .frame(height: min(CGFloat(items.count) * 26 + 30, 360))
            }
        }
        .task(id: tick) {
            guard let f = try? await session.readFile("metadata/upload-plan.json"), f.exists, let p = try? JSONDecoder().decode(Plan.self, from: Data(f.text.utf8)) else { items = []; return }
            items = p.items
            meta = [p.bundleId, p.uploader, L.date(p.generatedAt), p.remoteKnown == true ? nil : L.t("plan.remoteUnknown")].compactMap { $0 }.joined(separator: " · ")
        }
    }
}

struct DoctorChecks: View {
    var checks: [JSONValue]
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(checks.enumerated()), id: \.offset) { _, c in
                if let o = c.objectValue {
                    HStack(alignment: .top, spacing: 6) {
                        let status = o["status"]?.stringValue ?? ""
                        Image(systemName: status == "ok" ? "checkmark.circle.fill" : status == "warn" ? "exclamationmark.triangle.fill" : status == "skip" ? "minus.circle" : "xmark.circle.fill")
                            .foregroundStyle(status == "ok" ? .green : status == "warn" ? .orange : status == "skip" ? .secondary : .red).font(.caption)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(o["title"]?.stringValue ?? "").font(.caption.weight(.medium))
                            if let d = o["detail"]?.stringValue { Text(d).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                            if let f = o["fix"]?.stringValue { Text("→ \(f)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
    }
}
