import SwiftUI

/// Genel bakış: the team and the projects at a glance. A gradient header with the counts, what waits for the user
/// across every project, the apps by state, and the projects with their next step.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var credentials = ASCCredentials.shared

    private var apps: [ASCApp] { model.ascApps.apps }
    private func count(_ tone: Tone) -> Int { apps.filter { $0.current.map { ASCWords.tone($0.state) == tone } ?? false }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if model.cli == nil, !model.locating { CLIMissingCard() }
                if !model.connection.isConnected { keyCard }
                waiting
                projectsCard
                if !apps.isEmpty { appsCard }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .brandWindowBackground()
        .accessibilityIdentifier("home")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t("home.title")).font(.largeTitle.bold())
                    Text(L.t("onb.welcome.tagline")).font(.callout).opacity(0.9)
                }
                Spacer()
                StatusPill(text: Text(model.connection.isConnected ? L.t("account.connected") : L.t("account.none")), color: model.connection.isConnected ? (model.ascApps.error == nil ? .green : .red) : .orange, onGradient: true)
            }
            HStack(spacing: 8) {
                tile("square.grid.2x2", "\(apps.count)", L.t("home.stat.apps"))
                tile("hourglass", "\(count(.info))", L.t("home.stat.review"))
                tile("exclamationmark.triangle", "\(count(.err))", L.t("home.stat.attention"))
                tile("folder", "\(model.store.projects.count)", L.t("home.stat.projects"))
                tile("bell.badge", "\(model.pendingDecisions)", L.t("home.stat.waiting"))
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func tile(_ symbol: String, _ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                Text(value).font(.headline.monospacedDigit())
            }
            Text(label).font(.caption2).opacity(0.85).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var keyCard: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol: "key.horizontal.fill", colors: BadgeColors.cool, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("home.key.title")).font(.headline)
                Text(L.t("home.key.detail")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            SettingsButton { Text(L.t("account.add")) }.buttonStyle(GradientButtonStyle(fullWidth: false))
        }
        .glassCard(padding: 14)
    }

    /// Claude's questions, blockers and approvals across the open projects.
    @ViewBuilder private var waiting: some View {
        let items = model.store.projects.compactMap { p -> (Project, Overview)? in
            guard let o = model.sessions[p.id]?.overview, o.pendingCount > 0 else { return nil }
            return (p, o)
        }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(L.t("home.waiting"))
                ForEach(items, id: \.0.id) { p, o in
                    Button { Task { await model.open(p); model.selectedPage = .flow } } label: {
                        HStack(spacing: 10) {
                            IconBadge(symbol: "bell.badge.fill", colors: BadgeColors.alert, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.displayName(for: p)).font(.callout.weight(.semibold))
                                Text(o.next.map { L.stage($0.stage) } ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Pill("\(o.pendingCount)", .warn)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .glassCard(padding: 14)
        }
    }

    private var appsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(L.t("apps.title"))
                Spacer()
                if model.connection.isConnected {
                    Button { model.showNewApp = true } label: { Label(L.t("newapp.title"), systemImage: "plus.app") }.controlSize(.small)
                }
                if let at = model.ascApps.loadedAt { Text(L.t("apps.refreshedAt").replacingOccurrences(of: "{time}", with: L.relative(at.ISO8601Format()))).font(.caption).foregroundStyle(.tertiary) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
                ForEach(apps) { app in
                    Button { Task { await model.select(app: app) } } label: {
                        HStack(spacing: 10) {
                            AppIcon(app: app, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name).font(.callout.weight(.medium)).lineLimit(1)
                                if let v = app.current {
                                    Text("\(ASCWords.platform(v.platform)) \(v.version)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 4)
                            if let v = app.current { Pill(ASCWords.state(v.state), ASCWords.tone(v.state)).lineLimit(1) }
                        }
                        .padding(8)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .glassCard(padding: 14)
    }

    private var projectsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(L.t("projects.title"))
                Spacer()
                Button { model.pickProjectFolder() } label: { Label(L.t("projects.add"), systemImage: "folder.badge.plus") }.controlSize(.small)
            }
            if model.store.projects.isEmpty {
                HStack(spacing: 12) {
                    IconBadge(symbol: "folder.fill", colors: BadgeColors.warm, size: 32)
                    Text(L.t("home.noProjects")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(model.store.projects) { p in
                Button { Task { await model.open(p) } } label: {
                    HStack(spacing: 10) {
                        ProjectRow(project: p, session: model.sessions[p.id])
                        if let a = model.ascApp(for: p) { Label(a.name, systemImage: "link").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .glassCard(padding: 14)
    }
}

/// Install instructions when no CLI is found (Node.js and Vitrin).
struct CLIMissingCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Card(L.t("cli.notFound"), accent: true) {
            if let e = model.cliError { Text(e).font(.callout).foregroundStyle(.secondary) }
            Text(L.t("cli.installIntro")).font(.callout)
            InstallCLIButton()
            Text(L.t("cli.installPlugin")).font(.callout).foregroundStyle(.secondary)
            HStack {
                Button(L.t("cli.searchAgain")) { Task { await model.locateCLI(); if let p = model.selectedProject { await model.open(p) } } }
                SettingsButton { Text(L.t("cli.setPath")) }
            }
        }
        .frame(maxWidth: 560)
    }
}

struct CLIMissingView: View {
    var body: some View {
        VStack { CLIMissingCard() }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity).brandWindowBackground()
    }
}
