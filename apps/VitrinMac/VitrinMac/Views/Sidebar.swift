import SwiftUI

/// Projects, each with its pages; a dot per page tells the most urgent stage status on it.
struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: Binding(get: { Selection(project: model.selectedProjectID, page: model.selectedPage) }, set: { sel in
            guard let sel else { return }
            if let id = sel.project, id != model.selectedProjectID, let p = model.store.project(id) { Task { await model.open(p) } }
            model.selectedPage = sel.page
        })) {
            Section(L.t("projects.title")) {
                ForEach(model.store.projects) { project in
                    DisclosureGroup(isExpanded: Binding(get: { model.selectedProjectID == project.id }, set: { if $0 { Task { await model.open(project) } } })) {
                        ForEach(ProjectPage.allCases) { page in
                            Label {
                                HStack {
                                    Text(L.t(page.titleKey))
                                    Spacer()
                                    badge(project: project, page: page)
                                }
                            } icon: { Image(systemName: page.symbol) }
                            .tag(Selection(project: project.id, page: page))
                        }
                    } label: {
                        ProjectRow(project: project, session: model.sessions[project.id])
                            .tag(Selection(project: project.id, page: .flow))
                            .contextMenu {
                                Button(L.t("projects.reveal")) { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path) }
                                if let s = model.sessions[project.id], let url = s.url { Button(L.t("project.openStudio")) { NSWorkspace.shared.open(url) } }
                                if let s = model.sessions[project.id], s.isReady { Button(L.t("project.restartStudio")) { Task { if let cli = model.cli { await s.restart(cli: cli) } } } }
                                Divider()
                                Button(L.t("projects.remove"), role: .destructive) { model.removeProject(project.id) }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Button { model.pickProjectFolder() } label: { Label(L.t("projects.add"), systemImage: "plus") }.buttonStyle(.borderless).accessibilityIdentifier("sidebar.addProject")
                HStack(spacing: 6) {
                    if model.locating { ProgressView().controlSize(.mini) }
                    if !model.locating { Image(systemName: model.cli == nil ? "exclamationmark.circle" : "checkmark.circle").foregroundStyle(model.cli == nil ? .orange : .green) }
                    Text(model.cli.map { "Vitrin CLI \($0.version ?? "")" } ?? L.t(model.locating ? "cli.locating" : "cli.notFound")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .help(model.cli?.displayPath ?? model.cliError ?? "")
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }

    struct Selection: Hashable {
        var project: String?
        var page: ProjectPage
    }

    @ViewBuilder private func badge(project: Project, page: ProjectPage) -> some View {
        if let o = model.sessions[project.id]?.overview {
            if page == .flow, o.pendingCount > 0 {
                Text("\(o.pendingCount)").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(.orange.opacity(0.2))).foregroundStyle(.orange)
            } else if page == .review, let v = o.validation, !v.ok {
                Text("\(v.counts.error)").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(.red.opacity(0.2))).foregroundStyle(.red)
            } else if let tone = pageTone(o, page) {
                Circle().fill(tone.color).frame(width: 7, height: 7)
            }
        }
    }

    /// The most urgent status among the stages that live on a page.
    private func pageTone(_ o: Overview, _ page: ProjectPage) -> Tone? {
        let views = o.flow.filter { Pipeline.page(for: $0.id) == page && $0.stageStatus != .skipped && !($0.isOptional && $0.stageStatus == .notRun) }
        guard !views.isEmpty else { return nil }
        if views.contains(where: { $0.stageStatus == .blocked }) { return .err }
        if views.contains(where: { $0.stageStatus == .needsUser || $0.stageStatus == .needsClaude }) { return .warn }
        if views.contains(where: { $0.stageStatus == .outdated }) { return .info }
        if views.allSatisfy({ $0.stageStatus == .done }) { return .ok }
        return nil
    }
}

struct ProjectRow: View {
    var project: Project
    var session: ProjectSession?
    var body: some View {
        HStack(spacing: 8) {
            if let s = session, let o = s.overview, let icon = o.app?.icon, let url = s.client?.fileURL(icon) {
                AsyncImage(url: url) { img in img.resizable() } placeholder: { Image(systemName: "app.dashed") }
                    .frame(width: 20, height: 20).clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                Image(systemName: project.hasConfig ? "app.badge.checkmark" : "folder").frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(session?.overview?.app?.name ?? project.name).lineLimit(1)
                if let s = session {
                    if let j = s.job { Text(L.job(j)).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    else if let n = s.overview?.next { Text(L.stage(n.stage)).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
            Spacer()
            if let s = session {
                if s.job != nil || s.claudeRunning { ProgressView().controlSize(.mini) }
                else if s.loadError != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption) }
                else if s.isReady { StatusDot(tone: s.connected ? .ok : .warn) }
            }
        }
    }
}
