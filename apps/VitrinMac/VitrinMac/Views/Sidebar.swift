import SwiftUI

/// The team's App Store Connect apps, then the projects, each with its pages; a dot per page tells the most urgent
/// stage status on it.
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @State private var credentials = ASCCredentials.shared

    var body: some View {
        @Bindable var model = model
        List(selection: Binding(get: { model.selectedAppID.map { Selection(app: $0) } ?? Selection(project: model.selectedProjectID, page: model.selectedPage) }, set: { sel in
            guard let sel else { return }
            if let appID = sel.app {
                if let app = model.ascApps.app(appID) { Task { await model.select(app: app) } }
                return
            }
            model.selectedAppID = nil
            if let id = sel.project, id != model.selectedProjectID, let p = model.store.project(id) { Task { await model.open(p) } }
            model.selectedPage = sel.page
        })) {
            Section {
                appsRows
            } header: {
                HStack {
                    Text(L.t("apps.title"))
                    Spacer()
                    if model.ascApps.loading { ProgressView().controlSize(.mini) }
                    else if credentials.isSet {
                        Button { Task { await model.refreshApps() } } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless).controlSize(.small).help(L.t("apps.refresh")).accessibilityIdentifier("sidebar.refreshApps")
                    }
                }
            }
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
        var page: ProjectPage = .flow
        /// An App Store Connect app row (then `project` and `page` are not used).
        var app: String?
    }

    /// One line without a key; the error line; the apps, each linked to its project when one has the bundle id.
    @ViewBuilder private var appsRows: some View {
        if !credentials.isSet {
            VStack(alignment: .leading, spacing: 4) {
                Label(L.t("apps.noKey"), systemImage: "key").font(.callout).foregroundStyle(.secondary)
                SettingsLink { Text(L.t("settings.account")) }.controlSize(.small)
            }
            .padding(.vertical, 2).accessibilityIdentifier("sidebar.appsNoKey")
        } else if let e = model.ascApps.error, model.ascApps.apps.isEmpty {
            Label { Text(e).lineLimit(3) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                .font(.caption).foregroundStyle(.secondary).help(e)
        } else if model.ascApps.apps.isEmpty && !model.ascApps.loading && model.ascApps.loadedAt != nil {
            Text(L.t("apps.empty")).font(.callout).foregroundStyle(.secondary)
        } else if model.ascApps.apps.isEmpty {
            Text(L.t("apps.loading")).font(.callout).foregroundStyle(.secondary)
        } else {
            ForEach(model.ascApps.apps) { app in
                AppRow(app: app, linked: model.linkedProject(for: app))
                    .tag(Selection(app: app.id))
                    .contextMenu {
                        Button(L.t("apps.openASC")) { NSWorkspace.shared.open(app.ascURL) }
                        if model.linkedProject(for: app) == nil { Button(L.t("apps.linkProject")) { model.pickProjectFolder() } }
                    }
            }
        }
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

/// An App Store Connect app: a placeholder icon, the name, the bundle id, the current version with its state, and a
/// link badge when a local project has this bundle id.
struct AppRow: View {
    var app: ASCApp
    var linked: Project?
    var body: some View {
        HStack(spacing: 8) {
            AppIconPlaceholder(size: 20)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(app.name).lineLimit(1)
                    if let linked { Image(systemName: "link").font(.caption2).foregroundStyle(.secondary).help(L.t("apps.linked").replacingOccurrences(of: "{project}", with: linked.name)) }
                }
                Text(app.bundleId).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if let v = app.current {
                Pill("\(v.version) · \(ASCWords.state(v.state))", ASCWords.tone(v.state)).lineLimit(1).help("\(ASCWords.platform(v.platform)) \(v.version): \(ASCWords.state(v.state))")
            }
        }
        .accessibilityIdentifier("sidebar.app.\(app.bundleId)")
    }
}

/// The icon the API does not give (the Studio's overview has the project's); a rounded dashed app shape.
struct AppIconPlaceholder: View {
    var size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22)
            .fill(Color.accentColor.opacity(0.12))
            .overlay(Image(systemName: "app.dashed").font(.system(size: size * 0.6)).foregroundStyle(Color.accentColor.opacity(0.7)))
            .frame(width: size, height: size)
    }
}
