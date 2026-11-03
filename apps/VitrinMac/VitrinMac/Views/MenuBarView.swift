import SwiftUI

/// The menu bar panel in the Remote Code family look (`.menuBarExtraStyle(.window)`, 360 pt): a gradient header with
/// the counts, glass cards for what runs, what waits and the projects, the apps that need attention, and a footer.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var contentHeight: CGFloat = 200
    @State private var credentials = ASCCredentials.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 10) { sections }
                    .padding(12)
                    // MenuBarExtra windows collapse a ScrollView without a measured height.
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(contentHeight, 500))
            footer
        }
        .frame(width: 360)
        .background(BrandBackground(intensity: 0.8))
    }

    private var attention: [ASCApp] { model.ascApps.apps.filter { $0.current.map { [.err, .warn, .info].contains(ASCWords.tone($0.state)) } ?? false } }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Vitrin").font(.title3.bold())
                    Text(model.connection.isConnected ? L.t("account.apps").replacingOccurrences(of: "{n}", with: "\(model.ascApps.apps.count)") : L.t("account.none")).font(.caption).opacity(0.85)
                }
                Spacer()
                StatusPill(text: Text(statusText), color: statusColor, onGradient: true)
            }
            HStack(spacing: 6) {
                stat("square.grid.2x2", model.ascApps.apps.count, L.t("home.stat.apps"))
                stat("hourglass", attention.filter { ASCWords.tone($0.current!.state) == .info }.count, L.t("home.stat.review"))
                stat("bell.badge", model.pendingDecisions, L.t("home.stat.waiting"))
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(Brand.gradient)
    }

    private var statusText: String {
        if model.runningJob != nil || model.sessions.values.contains(where: \.claudeRunning) { return L.t("menu.working") }
        if model.cli == nil || model.ascApps.error != nil { return L.t("menu.attention") }
        return L.t("menu.ready")
    }
    private var statusColor: Color {
        if model.runningJob != nil || model.sessions.values.contains(where: \.claudeRunning) { return .orange }
        if model.cli == nil || model.ascApps.error != nil { return .red }
        return .green
    }

    private func stat(_ symbol: String, _ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) { Image(systemName: symbol); Text("\(value)").font(.headline.monospacedDigit()) }
            Text(label).font(.caption2).opacity(0.85).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    @ViewBuilder private var sections: some View {
        if !model.connection.isConnected || model.cli == nil {
            row(symbol: "exclamationmark.triangle.fill", colors: BadgeColors.alert, title: model.cli == nil ? L.t("cli.notFound") : L.t("account.none"), detail: model.cli == nil ? L.t("menu.cliDetail") : L.t("account.noneDetail")) { open() }
                .glassCard()
        }
        if let r = model.runningJob {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(L.t("menu.running"))
                HStack(spacing: 8) {
                    IconBadge(symbol: "sparkles", colors: BadgeColors.brand, size: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L.job(r.job)).font(.callout.weight(.semibold)).lineLimit(1)
                        Text(r.project.name).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ProgressBar(fraction: nil)
            }
            .glassCard()
        }
        let waiting = model.store.projects.filter { (model.sessions[$0.id]?.overview?.pendingCount ?? 0) > 0 }
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(L.t("home.waiting"))
                ForEach(waiting) { p in
                    let o = model.sessions[p.id]?.overview
                    row(symbol: "bell.badge.fill", colors: BadgeColors.alert, title: model.displayName(for: p), detail: o?.next.map { L.stage($0.stage) } ?? "", badge: o?.pendingCount) { open(p) }
                }
            }
            .glassCard()
        }
        if !attention.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(L.t("menu.inASC"))
                ForEach(attention.prefix(5)) { a in
                    let v = a.current!
                    HStack(spacing: 8) {
                        AppIconPlaceholder(size: 22)
                        Text(a.name).font(.callout).lineLimit(1)
                        Spacer()
                        Pill(ASCWords.state(v.state), ASCWords.tone(v.state)).lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { openWindow(id: "main"); NSApp.activate(); Task { await model.select(app: a) } }
                }
            }
            .glassCard()
        }
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(L.t("projects.title"))
            if model.store.projects.isEmpty { Text(L.t("home.noProjects")).font(.caption).foregroundStyle(.secondary) }
            ForEach(model.store.projects) { p in
                let o = model.sessions[p.id]?.overview
                row(symbol: "folder.fill", colors: BadgeColors.warm, title: model.displayName(for: p), detail: o?.next.map { L.stage($0.stage) } ?? p.path) { open(p) }
            }
        }
        .glassCard()
        HStack(spacing: 8) {
            Button { open() } label: { Label(L.t("menu.openApp"), systemImage: "macwindow") }
                .buttonStyle(GradientButtonStyle()).keyboardShortcut("v")
            Button { Task { await model.refreshApps() } } label: { Image(systemName: "arrow.clockwise").frame(width: 34, height: 34) }
                .buttonStyle(.plain)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .help(L.t("apps.refresh"))
        }
    }

    private func row(symbol: String, colors: [Color], title: String, detail: String, badge: Int? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                IconBadge(symbol: symbol, colors: colors, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if let badge { Pill("\(badge)", .warn) }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func open(_ p: Project? = nil) {
        openWindow(id: "main")
        NSApp.activate()
        if let p { Task { await model.open(p) } }
    }

    private var footer: some View {
        HStack {
            SettingsLink { Label(L.t("settings.title"), systemImage: "gearshape") }
            Spacer()
            Text("v\(model.updates.appVersion)").font(.caption).foregroundStyle(.tertiary)
            Spacer()
            Button { NSApp.terminate(nil) } label: { Label(L.t("menu.quit"), systemImage: "power") }.keyboardShortcut("q")
        }
        .labelStyle(.titleAndIcon)
        .font(.callout)
        .buttonStyle(.borderless)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.bar)
    }
}
