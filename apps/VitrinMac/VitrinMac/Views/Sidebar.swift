import SwiftUI

/// The sidebar in the Remote Code family look: an overview row, the local projects with their pages, the team's App
/// Store Connect apps (each row a gradient badge), and the account and CLI state at the bottom.
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @State private var credentials = ASCCredentials.shared

    var body: some View {
        List(selection: Binding(get: { current }, set: { sel in select(sel) })) {
            Label { Text(L.t("home.title")) } icon: { IconBadge(symbol: "square.grid.2x2.fill", colors: BadgeColors.brand) }
                .padding(.vertical, 2)
                .tag(Selection(home: true))
                .accessibilityIdentifier("sidebar.home")

            Section {
                ForEach(model.store.projects) { project in
                    DisclosureGroup(isExpanded: Binding(get: { model.selectedProjectID == project.id && !model.showHome && model.selectedAppID == nil }, set: { if $0 { Task { await model.open(project) } } })) {
                        // The App Store Connect page only for a project linked to an app of the team.
                        ForEach(ProjectPage.allCases.filter { $0 != .asc || model.ascApp(for: project) != nil }) { page in
                            Label {
                                HStack {
                                    Text(L.t(page.titleKey))
                                    Spacer()
                                    badge(project: project, page: page)
                                }
                            } icon: { IconBadge(symbol: page.badgeSymbol, colors: page.badgeColors, size: 20) }
                            .padding(.vertical, 1)
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
                Button { model.pickProjectFolder() } label: {
                    Label { Text(L.t("projects.add")).foregroundStyle(.secondary) } icon: { Image(systemName: "plus").foregroundStyle(.secondary) }
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("sidebar.addProject")
            } header: {
                Text(L.t("projects.title"))
            }
            Section(L.t("team.title")) {
                ForEach(TeamPage.allCases) { p in
                    Label { Text(L.t(p.titleKey)) } icon: { IconBadge(symbol: p.symbol, colors: p.colors) }
                        .padding(.vertical, 1)
                        .tag(Selection(team: p.rawValue))
                        .accessibilityIdentifier("sidebar.team.\(p.rawValue)")
                }
            }
            Section {
                appsRows
            } header: {
                HStack {
                    Text(L.t("apps.title"))
                    Spacer()
                    if model.ascApps.loading { ProgressView().controlSize(.mini) }
                    else if model.connection.isConnected {
                        Button { Task { await model.refreshApps() } } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless).controlSize(.small).help(L.t("apps.refresh")).accessibilityIdentifier("sidebar.refreshApps")
                    }
                }
            }

        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var current: Selection? {
        if let t = model.selectedTeamPage { return Selection(team: t.rawValue) }
        if model.showHome || (model.selectedAppID == nil && model.selectedProjectID == nil) { return Selection(home: true) }
        if let a = model.selectedAppID { return Selection(app: a) }
        return Selection(project: model.selectedProjectID, page: model.selectedPage)
    }

    private func select(_ sel: Selection?) {
        guard let sel else { return }
        if let t = sel.team.flatMap(TeamPage.init(rawValue:)) {
            model.selectedAppID = nil
            model.selectedTeamPage = t
            return
        }
        model.selectedTeamPage = nil
        if sel.home {
            model.selectedAppID = nil
            model.showHome = true
            return
        }
        if let appID = sel.app {
            if let app = model.ascApps.app(appID) { Task { await model.select(app: app) } }
            return
        }
        model.selectedAppID = nil
        model.showHome = false
        if let id = sel.project, id != model.selectedProjectID || model.sessions[id]?.isReady != true, let p = model.store.project(id) { Task { await model.open(p) } }
        model.selectedPage = sel.page
    }

    /// The key and the CLI, the way Promo Studio shows its account: a badge, a line, a dot and the gear.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                IconBadge(symbol: "key.horizontal.fill", colors: model.connection.isConnected ? BadgeColors.cool : BadgeColors.gray, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.connection.isConnected ? L.t("account.connected") : L.t("account.none")).font(.callout.weight(.medium)).lineLimit(1)
                    Text(accountDetail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Circle().fill(accountTone.color).frame(width: 7, height: 7)
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.borderless).help(L.t("settings.title"))
            }
            HStack(spacing: 6) {
                if model.locating { ProgressView().controlSize(.mini) }
                else { Image(systemName: model.cli == nil ? "exclamationmark.circle" : "terminal").foregroundStyle(model.cli == nil ? .orange : .secondary) }
                Text(model.cli.map { "Vitrin CLI \($0.version ?? "")" } ?? L.t(model.locating ? "cli.locating" : "cli.notFound")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .help(model.cli?.displayPath ?? model.cliError ?? "")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    private var accountDetail: String {
        let keyId: String
        switch model.connection.state {
        case .vitrinKey(let id): keyId = id
        case .ascLogin(let name, let id): keyId = "asc · \(name) · \(id)"
        case .missingCLI: return L.t("asc.missing")
        default: return L.t("account.noneDetail")
        }
        if model.ascApps.loading { return L.t("apps.loading") }
        if model.ascApps.error != nil { return L.t("account.error") }
        return L.t("account.apps").replacingOccurrences(of: "{n}", with: "\(model.ascApps.apps.count)") + " · \(keyId)"
    }

    private var accountTone: Tone {
        guard model.connection.isConnected else { return .neutral }
        if model.ascApps.error != nil { return .err }
        return model.ascApps.loadedAt != nil ? .ok : .warn
    }

    struct Selection: Hashable {
        var project: String?
        var page: ProjectPage = .flow
        /// An App Store Connect app row (then `project` and `page` are not used).
        var app: String?
        var home = false
        var team: String?
    }

    /// One line without a key; the error line; the apps, each linked to its project when one has the bundle id.
    @ViewBuilder private var appsRows: some View {
        if !model.connection.isConnected {
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("apps.noKey")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                SettingsLink { Label(L.t("account.add"), systemImage: "key.horizontal") }.controlSize(.small)
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

extension ProjectPage {
    /// The filled symbol on the page's sidebar badge and page header.
    var badgeSymbol: String {
        switch self {
        case .flow: return "point.3.connected.trianglepath.dotted"
        case .research: return "magnifyingglass"
        case .listing: return "text.alignleft"
        case .visuals: return "photo.fill.on.rectangle.fill"
        case .review: return "checkmark.seal.fill"
        case .upload: return "arrow.up"
        case .asc: return "storefront.fill"
        }
    }
    var badgeColors: [Color] {
        switch self {
        case .flow: return BadgeColors.brand
        case .research: return BadgeColors.deep
        case .listing: return BadgeColors.magic
        case .visuals: return BadgeColors.warm
        case .review: return BadgeColors.fresh
        case .upload: return BadgeColors.cool
        case .asc: return BadgeColors.deep
        }
    }
}

struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    var project: Project
    var session: ProjectSession?
    var body: some View {
        HStack(spacing: 8) {
            if let s = session, let o = s.overview, let icon = o.app?.icon, let url = s.client?.fileURL(icon) {
                AsyncImage(url: url) { img in img.resizable() } placeholder: { IconBadge(symbol: "app.fill", colors: BadgeColors.warm) }
                    .frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 22 * 0.26, style: .continuous))
            } else {
                IconBadge(symbol: project.hasConfig ? "app.fill" : "folder.fill", colors: BadgeColors.warm)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayName(for: project)).font(.body.weight(.medium)).lineLimit(1)
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
        .padding(.vertical, 2)
    }
}

/// An App Store Connect app: a badge, the name, the version and its state, a coloured dot, and a link badge when a
/// local project has this bundle id.
struct AppRow: View {
    var app: ASCApp
    var linked: Project?
    var body: some View {
        HStack(spacing: 8) {
            AppIconPlaceholder(size: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(app.name).lineLimit(1)
                    if let linked { Image(systemName: "link").font(.caption2).foregroundStyle(.secondary).help(L.t("apps.linked").replacingOccurrences(of: "{project}", with: linked.name)) }
                }
                if let v = app.current {
                    Text("\(v.version) · \(ASCWords.state(v.state))").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(app.bundleId).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            if let v = app.current { Circle().fill(ASCWords.tone(v.state).color).frame(width: 7, height: 7).help("\(ASCWords.platform(v.platform)) \(v.version): \(ASCWords.state(v.state))") }
        }
        .padding(.vertical, 1)
        .accessibilityIdentifier("sidebar.app.\(app.bundleId)")
    }
}

/// The icon the API does not give (the Studio's overview has the project's): a badge in the team colours.
struct AppIconPlaceholder: View {
    var size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: BadgeColors.cool, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Image(systemName: "app.fill").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
