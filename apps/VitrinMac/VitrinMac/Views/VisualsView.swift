import SwiftUI

/// Screenshots, design samples with the store preview, App Previews and creatives, as the Studio serves them.
struct VisualsView: View {
    @Environment(AppModel.self) private var model
    var session: ProjectSession
    var overview: Overview
    @State private var tab: Tab = .screenshots
    @State private var locale = ""
    @State private var preview: RenderedFile?

    enum Tab: String, CaseIterable, Identifiable {
        case screenshots, samples, previews, creatives, raw
        var id: String { rawValue }
    }

    private var client: StudioClient? { session.client }
    private var bust: String { String(session.changedTick) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                // Title, then the stage buttons on their own wrapping row, then the tabs and the language: nothing here
                // has a minimum width larger than the page, so a narrow page (the Claude column open) never overflows.
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("page.visuals")).font(.title.bold())
                    // No vertical fixedSize here: measured at a zero width it grew a letter per line and pushed the whole window up.
                    Text(L.t("visuals.intro")).foregroundStyle(.secondary).lineLimit(2)
                }
                stageButtons
                HStack(spacing: 10) {
                    // The tabs as a segmented control when it fits, else a menu: never wider than the page.
                    ViewThatFits(in: .horizontal) {
                        Picker("", selection: $tab) { ForEach(Tab.allCases) { Text(L.t("visuals.\($0.rawValue)")).tag($0) } }.labelsHidden().pickerStyle(.segmented).fixedSize()
                        Picker("", selection: $tab) { ForEach(Tab.allCases) { Text(L.t("visuals.\($0.rawValue)")).tag($0) } }.labelsHidden().fixedSize()
                    }
                    Spacer(minLength: 0)
                    if tab != .samples {
                        Picker("", selection: $locale) { ForEach(overview.config?.locales ?? [], id: \.self) { Text($0).tag($0) } }.labelsHidden().fixedSize()
                    }
                }
            }
            .padding(20)
            Divider()
            content
        }
        .onAppear { if locale.isEmpty { locale = overview.config?.startLocale ?? "en-US" } }
        .sheet(item: $preview) { f in
            if let c = client { MediaSheet(file: f, url: c.fileURL(f.path, bust: bust)) { preview = nil } }
        }
    }

    /// The stage buttons with their labels when they fit, icons only when the page is narrow.
    private var stageButtons: some View {
        ViewThatFits(in: .horizontal) {
            stageButtonRow.fixedSize()
            stageButtonRow.labelStyle(.iconOnly).fixedSize()
        }
    }

    private var stageButtonRow: some View {
        HStack(spacing: 6) {
            ForEach(["capture", "mockups", "design", "video"], id: \.self) { id in
                if let view = overview.stage(id), view.stageStatus != .skipped {
                    if let b = view.brief {
                        ClaudeButton(session: session, overview: overview, stage: b, small: true).help(L.stage(id))
                    } else if let c = Pipeline.command(for: id) {
                        Button { Task { await session.run(c.command, args: c.args) } } label: { Label(L.t("short.\(id)"), systemImage: symbol(id)) }
                            .disabled(session.isBusy).help(AppSettings.shared.developerMode ? "vitrin \(c.command)" : L.stage(id))
                    }
                }
            }
        }
    }

    private func symbol(_ id: String) -> String {
        switch id {
        case "capture": return "camera"
        case "mockups": return "iphone"
        case "design": return "paintbrush"
        default: return "film"
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .screenshots: grid(overview.screenshots[locale] ?? [], empty: L.t("visuals.noScreenshots"))
        case .creatives: grid(overview.creatives[locale] ?? [], empty: L.t("visuals.noCreatives"), height: 180)
        case .previews: previewsView
        case .raw: rawView
        case .samples: samplesView
        }
    }

    private func grid(_ files: [RenderedFile], empty: String, height: CGFloat = 240) -> some View {
        ScrollView {
            if files.isEmpty {
                EmptyHint(text: empty, symbol: "photo")
            } else if let c = client {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: height * 0.6, maximum: height * 1.2), spacing: 12)], spacing: 12) {
                    ForEach(files) { f in
                        MediaThumb(file: f, url: c.fileURL(f.path, bust: bust), height: height)
                            .onTapGesture { preview = f }
                            .contextMenu { Button(L.t("common.reveal")) { Task { await session.openInFinder(f.path) } } }
                    }
                }
                .padding(20)
                Text(L.t("visuals.count", files.count, TextLimits.maxScreenshots)).font(.caption).foregroundStyle(.secondary).padding(.bottom, 12)
            }
        }
    }

    private var previewsView: some View {
        ScrollView {
            let files = overview.previews[locale] ?? []
            if files.isEmpty {
                EmptyHint(text: L.t("visuals.noPreviews"), symbol: "play.rectangle")
            } else if let c = client {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 12)], spacing: 12) {
                    ForEach(files) { f in
                        VStack(spacing: 4) {
                            VideoView(url: c.fileURL(f.path, bust: bust)).frame(height: 420)
                            Text(f.name).font(.caption).lineLimit(1)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(f.bytes), countStyle: .file)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
                if let styles = overview.videoStyles[locale], !styles.isEmpty {
                    Text(L.t("visuals.videoStyles")).font(.headline).padding(.horizontal, 20)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12)], spacing: 12) {
                        ForEach(styles) { f in MediaThumb(file: f, url: c.fileURL(f.path, bust: bust), height: 300) }
                    }.padding(20)
                }
            }
        }
    }

    private var rawView: some View {
        ScrollView {
            let families = overview.raw[locale] ?? [:]
            if families.isEmpty {
                EmptyHint(text: L.t("visuals.noRaw"), symbol: "camera")
            } else if let c = client {
                ForEach(families.keys.sorted(), id: \.self) { fam in
                    Text(fam).font(.headline).padding(.horizontal, 20).padding(.top, 12)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 10)], spacing: 10) {
                        ForEach(families[fam] ?? []) { f in MediaThumb(file: f, url: c.fileURL(f.path, bust: bust), height: 200).onTapGesture { preview = f } }
                    }.padding(.horizontal, 20)
                }
            }
        }
    }

    private var samplesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let s = overview.samples, let c = client {
                    Card(L.t("visuals.samplesTitle")) {
                        Text(L.t("visuals.samplesIntro")).font(.callout).foregroundStyle(.secondary)
                        DesignOptions(session: session, overview: overview)
                        if let sheet = s.contactSheet {
                            AsyncImage(url: c.fileURL(sheet, bust: bust)) { img in img.resizable().aspectRatio(contentMode: .fit) } placeholder: { ProgressView() }
                                .frame(maxHeight: 420)
                        }
                    }
                    if let p = s.storePreview {
                        Card(L.t("visuals.storePreview")) {
                            WebView(url: c.fileURL(p, bust: bust)).frame(height: 720).clipShape(RoundedRectangle(cornerRadius: 8))
                            Button(L.t("common.openInBrowser")) { NSWorkspace.shared.open(c.fileURL(p)) }.controlSize(.small)
                        }
                    }
                } else {
                    Card {
                        Text(L.t("visuals.noSamples")).foregroundStyle(.secondary)
                        Button(L.t("visuals.renderSamples")) { Task { await session.run("design", args: ["samples": true]) } }.disabled(session.isBusy).cliHelp("vitrin design --samples")
                    }
                }
                if let m = overview.mockups, !m.screens.isEmpty, let c = client {
                    Card(L.t("visuals.mockups")) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 10)], spacing: 10) {
                            ForEach(m.screens) { f in MediaThumb(file: f, url: c.fileURL(f.path, bust: bust), height: 200).onTapGesture { preview = f } }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

struct MediaSheet: View {
    var file: RenderedFile
    var url: URL
    var close: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(file.path).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(L.t("common.openInBrowser")) { NSWorkspace.shared.open(url) }
                Button(L.t("common.close")) { close() }.keyboardShortcut(.cancelAction)
            }
            if file.name.lowercased().hasSuffix(".mp4") || file.name.lowercased().hasSuffix(".mov") {
                VideoView(url: url)
            } else {
                AsyncImage(url: url) { img in img.resizable().aspectRatio(contentMode: .fit) } placeholder: { ProgressView() }
            }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 640)
    }
}
