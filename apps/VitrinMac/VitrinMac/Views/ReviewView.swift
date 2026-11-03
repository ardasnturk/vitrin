import SwiftUI

/// The review gallery (metadata/report.html) with approve and reject, exactly as `vitrin review --serve` offers it:
/// the gallery is shown read-only; the decisions are the app's own buttons, recorded with the session token.
struct ReviewView: View {
    var session: ProjectSession
    var overview: Overview
    @State private var review: ReviewState?
    @State private var loading = false
    @State private var confirmApprove = false
    @State private var showReject = false
    @State private var frameKey = 0

    private var invalid: Bool { overview.validation.map { !$0.ok } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("page.review")).font(.title.bold())
                        Text(L.t("review.intro")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L.stage("validate")) { Task { await session.run("validate") } }.disabled(session.isBusy).cliHelp("vitrin validate")
                    Button(L.t("review.rebuild")) { Task { await load() } }.disabled(session.isBusy || loading).cliHelp("vitrin review")
                    Button(L.t("review.reject")) { showReject = true }.disabled(session.isBusy || review == nil).accessibilityIdentifier("review.reject")
                    Button(L.t("review.approveAll")) { confirmApprove = true }.buttonStyle(.borderedProminent).accessibilityIdentifier("review.approveAll")
                        .disabled(session.isBusy || loading || review == nil || review?.approval.ok == true || invalid)
                }
                HStack(spacing: 8) {
                    if loading { ProgressView().controlSize(.small) }
                    if let r = review {
                        if r.approval.ok, let a = overview.approval, a.valid { Pill("\(L.t("review.approved")) · \(L.date(a.approvedAt))", .ok) }
                        else if r.approval.ok, let a = overview.approval { Pill(L.t("review.approvalInvalid").replacingOccurrences(of: "{reason}", with: L.reason(StageView(id: "review", status: "blocked", reason: a.problem), overview)), .err) }
                        else { Pill(r.approval.reason ?? L.t("review.notApproved"), .warn) }
                        Text("\(L.t("review.items", r.items.count)) · \(L.t("review.hash")) \(r.overallHash.prefix(12))").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    if let v = overview.validation { Pill(v.ok ? L.t("review.validationOk") : L.t("review.validationErrors", v.counts.error), v.ok ? .ok : .err) }
                    if let a = overview.approval, a.rejections > 0 { Pill(L.t("review.rejections", a.rejections), .warn) }
                }
                if invalid, review?.approval.ok != true { Text(L.t("review.needsValid")).font(.callout).foregroundStyle(.secondary) }
                if let r = review, !r.summary.isEmpty { FlowLayout(spacing: 4) { ForEach(r.summary, id: \.self) { Pill($0) } } }
            }
            .padding(20)
            Divider()
            if overview.files["report"] == true, let c = session.client {
                // `embed=app`: the gallery hides its own decision bar; the buttons above record the decision.
                WebView(url: URL(string: c.fileURL("metadata/report.html", bust: String(frameKey)).absoluteString + "&embed=app")!).id(frameKey)
            } else {
                EmptyHint(text: L.t("review.noReport"), symbol: "checklist")
            }
        }
        .task(id: session.changedTick) { if session.job == nil { await load() } }
        .confirmationDialog(L.t("review.approveAll"), isPresented: $confirmApprove, titleVisibility: .visible) {
            Button(L.t("review.approveConfirm", review?.items.count ?? 0)) { Task { await approve() } }
            Button(L.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(L.t("review.approveMessage") + "\n" + (review?.summary.joined(separator: "\n") ?? "") + "\n" + (review?.overallHash ?? ""))
        }
        .sheet(isPresented: $showReject) {
            if let r = review { RejectSheet(review: r, session: session) { showReject = false; Task { await load() } } }
        }
    }

    private func load() async {
        guard let c = session.client else { return }
        loading = true
        defer { loading = false }
        do {
            review = try await c.review()
            frameKey += 1
        } catch {
            session.report(error)
        }
    }

    private func approve() async {
        guard let c = session.client, let r = review else { return }
        do {
            try await c.approve(overallHash: r.overallHash)
            session.toast(L.t("review.approved"), .ok)
        } catch {
            session.report(error)
        }
        await load()
        await session.refresh()
    }
}

/// Reject items with a comment each; Claude reads them from metadata/review-feedback.json.
struct RejectSheet: View {
    var review: ReviewState
    var session: ProjectSession
    var done: () -> Void
    @State private var selected: Set<String> = []
    @State private var comment = ""
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("review.reject")).font(.headline)
            Text(L.t("review.rejectIntro")).foregroundStyle(.secondary).font(.callout)
            List(review.items, selection: $selected) { item in
                HStack {
                    Text(item.label)
                    Spacer()
                    Text([item.kind, item.locale, item.target].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
                .tag(item.id)
            }
            .frame(minHeight: 260)
            TextField(L.t("review.comment"), text: $comment, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
            HStack {
                Text(L.t("review.selected", selected.count)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L.t("common.cancel")) { done() }.keyboardShortcut(.cancelAction)
                Button(L.t("review.sendRejections")) { Task { await send() } }.buttonStyle(.borderedProminent)
                    .disabled(sending || selected.isEmpty || comment.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 460)
    }

    private func send() async {
        guard let c = session.client else { return }
        sending = true
        defer { sending = false }
        do {
            let n = try await c.reject(overallHash: review.overallHash, rejections: selected.sorted().map { StudioClient.Rejection(item: $0, comment: comment.trimmingCharacters(in: .whitespaces)) })
            session.toast(L.t("review.rejectionsSent", n), .ok)
            done()
        } catch {
            session.report(error)
        }
    }
}
