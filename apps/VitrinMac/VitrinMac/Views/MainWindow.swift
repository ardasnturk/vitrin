import SwiftUI

/// Sidebar (projects and their pages) + detail (the page), with the live log at the bottom and Claude in a side column.
///
/// The Claude column is a plain `HStack`, not `.inspector`: the inspector's split view re-enters AppKit layout while
/// its hosting view resizes and while the column slides in, and both raise an NSException on macOS 15 and 26
/// (`_postWindowNeedsUpdateConstraints`, `AppKitPlatformViewHost.coreLayoutTraits`), which killed the app the first
/// time a user clicked "Let Claude do it".
struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(LanguageState.self) private var language
    @State private var claudeWidth: CGFloat = 400

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            HStack(spacing: 0) {
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.showClaude {
                    // A drag handle on the divider: the column is 320–560 wide, the page keeps the rest.
                    Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
                        .overlay(Rectangle().fill(.clear).frame(width: 7).contentShape(Rectangle()))
                        .gesture(DragGesture(minimumDistance: 1).onChanged { v in claudeWidth = min(max(320, claudeWidth - v.translation.width), 560) })
                        .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    Group {
                        if let s = model.selectedSession { ClaudePanel(session: s) } else { EmptyHint(text: L.t("projects.selectOne"), symbol: "sparkles") }
                    }
                    .frame(width: claudeWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .transaction { $0.animation = nil }
                    .accessibilityIdentifier("claude.column")
                }
            }
        }
        .toolbar { toolbar }
        .navigationTitle(model.selectedProject?.name ?? "Vitrin")
        .navigationSubtitle(model.selectedSession?.overview?.app?.bundleId ?? "")
        .onChange(of: model.selectedSession?.overview?.config?.language) { model.applyLanguage() }
        .onChange(of: model.settings.language) { model.applyLanguage() }
    }

    @ViewBuilder private var detail: some View {
        if model.cli == nil && !model.locating && model.store.projects.isEmpty == false {
            CLIMissingView()
        } else if let project = model.selectedProject {
            ProjectDetail(project: project, session: model.session(for: project))
        } else {
            WelcomeView()
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let s = model.selectedSession {
                // What runs is said where it runs: the job in the log bar, Claude in its column; the toolbar only hints.
                if s.job != nil || s.claudeRunning { ProgressView().controlSize(.small).help(s.job.map { L.job($0) } ?? L.t("claude.busy")) }
                Button { Task { await s.refresh() } } label: { Image(systemName: "arrow.clockwise") }.help(L.t("common.refresh")).disabled(!s.isReady).accessibilityIdentifier("toolbar.refresh")
                Button { model.showLog.toggle() } label: { Image(systemName: "terminal").symbolVariant(model.showLog ? .fill : .none) }.help(L.t("log.toggle")).accessibilityIdentifier("toolbar.log")
                Button { model.showClaude.toggle() } label: { Image(systemName: "sparkles").symbolVariant(model.showClaude ? .fill : .none) }.help(L.t("claude.toggle")).accessibilityIdentifier("toolbar.claude")
                if let url = s.url {
                    Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "safari") }.help(L.t("project.openStudio")).accessibilityIdentifier("toolbar.studio")
                }
            }
        }
    }
}

/// A project's pages, with the log panel under them.
struct ProjectDetail: View {
    @Environment(AppModel.self) private var model
    var project: Project
    var session: ProjectSession

    @State private var logHeight: CGFloat = 190

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                page
                ToastStack(session: session)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.showLog {
                // A drag handle instead of VSplitView, which hands the log most of the window.
                Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
                    .overlay(Rectangle().fill(.clear).frame(height: 7).contentShape(Rectangle()))
                    .gesture(DragGesture(minimumDistance: 1).onChanged { v in logHeight = min(max(110, logHeight - v.translation.height), 600) })
                    .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                LogPanel(session: session).frame(height: logHeight).accessibilityElement(children: .contain).accessibilityIdentifier("log.panel")
            }
        }
        .task(id: project.id) {
            if let cli = model.cli, !session.isReady, session.loadError == nil { await session.start(cli: cli) }
        }
    }

    @ViewBuilder private var page: some View {
        if !project.exists {
            EmptyHint(text: L.t("projects.missingFolder").replacingOccurrences(of: "{path}", with: project.path), symbol: "folder.badge.questionmark")
        } else if let err = session.loadError, session.overview == nil {
            StartFailedView(session: session, error: err)
        } else if let o = session.overview {
            if !o.initialized {
                InitOfferView(session: session, overview: o)
            } else {
                switch model.selectedPage {
                case .flow: FlowView(session: session, overview: o)
                case .research: ResearchView(session: session, overview: o)
                case .listing: ListingView(session: session, overview: o)
                case .visuals: VisualsView(session: session, overview: o)
                case .review: ReviewView(session: session, overview: o)
                case .upload: UploadView(session: session, overview: o)
                }
            }
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text(model.cli == nil ? L.t("cli.locating") : L.t("project.starting")).foregroundStyle(.secondary)
                if !session.process.output.isEmpty {
                    Text(session.process.output.suffix(3).joined(separator: "\n")).font(.caption.monospaced()).foregroundStyle(.tertiary).lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct StartFailedView: View {
    @Environment(AppModel.self) private var model
    var session: ProjectSession
    var error: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L.t("project.startFailed"), systemImage: "exclamationmark.triangle.fill").font(.title3).foregroundStyle(.red)
            Text(error).font(.callout.monospaced()).textSelection(.enabled)
            if !session.process.output.isEmpty {
                ScrollView { Text(session.process.output.joined(separator: "\n")).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 200)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            }
            HStack {
                Button(L.t("common.retry")) { Task { if let cli = model.cli { await session.restart(cli: cli) } } }.buttonStyle(.borderedProminent)
                SettingsLink { Text(L.t("settings.title")) }
            }
        }
        .padding(24)
        .frame(maxWidth: 720, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A folder without vitrin.config.yaml: offer `vitrin init`.
struct InitOfferView: View {
    var session: ProjectSession
    var overview: Overview
    @State private var language = "en"
    @State private var uploader = "asc"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L.t("init.title")).font(.title2.bold())
                Text(L.t("init.intro")).foregroundStyle(.secondary)
                Card {
                    Picker(L.t("init.language"), selection: $language) {
                        Text("English").tag("en")
                        Text("Türkçe").tag("tr")
                    }.frame(maxWidth: 360)
                    Picker(L.t("init.uploader"), selection: $uploader) {
                        Text("asc CLI").tag("asc")
                        Text("fastlane deliver").tag("deliver")
                    }.frame(maxWidth: 360)
                    Text(L.t("init.hint")).font(.callout).foregroundStyle(.secondary)
                    Button(L.t("init.run")) { Task { await session.run("init", args: ["language": .string(language), "uploader": .string(uploader)]) } }
                        .buttonStyle(.borderedProminent).disabled(session.isBusy).cliHelp("vitrin init --language \(language) --uploader \(uploader)")
                }
                Text(session.project.path).font(.caption.monospaced()).foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }
}
