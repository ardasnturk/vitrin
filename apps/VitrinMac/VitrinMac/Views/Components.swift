import AVKit
import SwiftUI
import WebKit

/// Small reusable pieces in the app's visual language: cards, pills, numbered steps, a web view and a video player.

struct Card<Content: View>: View {
    var title: String?
    var accent = false
    @ViewBuilder var content: Content
    init(_ title: String? = nil, accent: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accent = accent
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.headline) }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(accent ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent ? Color.accentColor.opacity(0.4) : Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

enum Tone { case ok, warn, err, info, accent, neutral }

extension Tone {
    var color: Color {
        switch self {
        case .ok: return .green
        case .warn: return .orange
        case .err: return .red
        case .info: return .blue
        case .accent: return .accentColor
        case .neutral: return .secondary
        }
    }
    static func of(_ s: StageStatus) -> Tone {
        switch s {
        case .done: return .ok
        case .needsClaude, .needsUser: return .warn
        case .blocked: return .err
        case .outdated: return .info
        case .notRun, .skipped, .unknown: return .neutral
        }
    }
    static func ofJob(_ status: String) -> Tone {
        switch status {
        case "ok": return .ok
        case "running": return .accent
        case "needs-input": return .warn
        default: return .err
        }
    }
}

struct Pill: View {
    var text: String
    var tone: Tone = .neutral
    init(_ text: String, _ tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }
    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(tone.color.opacity(0.15)))
            .foregroundStyle(tone == .neutral ? Color.secondary : tone.color)
    }
}

struct StatusDot: View {
    var tone: Tone
    var pulsing = false
    @State private var on = false
    var body: some View {
        Circle().fill(tone.color).frame(width: 8, height: 8)
            .opacity(pulsing ? (on ? 1 : 0.3) : 1)
            .animation(pulsing ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: on)
            .onAppear { on = true }
    }
}

/// A numbered circle that turns into a check mark once its step is done.
struct StepNumber: View {
    var n: Int
    var done: Bool
    var tone: Tone = .neutral
    var running = false
    var body: some View {
        ZStack {
            Circle().fill(done ? Color.green.opacity(0.18) : (tone == .neutral ? Color(nsColor: .quaternaryLabelColor).opacity(0.3) : tone.color.opacity(0.18)))
            if running { ProgressView().controlSize(.small) }
            else if done { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.green) }
            else { Text("\(n)").font(.caption.bold()).foregroundStyle(tone == .neutral ? Color.secondary : tone.color) }
        }
        .frame(width: 26, height: 26)
    }
}

/// A command or install line the user copies.
struct CopyCode: View {
    var text: String
    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .textBackgroundColor)))
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: { Image(systemName: "doc.on.doc") }
            .buttonStyle(.borderless).help(L.t("common.copy"))
        }
    }
}

struct EmptyHint: View {
    var text: String
    var symbol = "tray"
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
    }
}

/// The toast strip at the bottom of a project page.
struct ToastStack: View {
    var session: ProjectSession
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(session.toasts) { t in
                HStack(spacing: 8) {
                    Image(systemName: t.tone == .ok ? "checkmark.circle.fill" : t.tone == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundStyle(t.tone == .ok ? .green : t.tone == .error ? .red : .blue)
                    Text(t.text).lineLimit(4).textSelection(.enabled)
                    Button { session.dismiss(t) } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial).shadow(radius: 6, y: 2))
                .frame(maxWidth: 520)
            }
        }
        .padding(12)
        .animation(.spring(duration: 0.3), value: session.toasts)
    }
}

/// A WKWebView that shows a page the Studio serves (sandboxed HTML from metadata/).
struct WebView: NSViewRepresentable {
    var url: URL
    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.setValue(false, forKey: "drawsBackground")
        v.load(URLRequest(url: url))
        return v
    }
    func updateNSView(_ v: WKWebView, context: Context) {
        if v.url != url { v.load(URLRequest(url: url)) }
    }
}

/// An App Preview or raw recording, played from the Studio's /files route (range requests are supported).
struct VideoView: View {
    var url: URL
    @State private var player: AVPlayer?
    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player = AVPlayer(url: url) }
            .onChange(of: url) { _, new in player = AVPlayer(url: new) }
            .onDisappear { player?.pause() }
    }
}

/// A screenshot or creative thumbnail with its file name and size.
struct MediaThumb: View {
    var file: RenderedFile
    var url: URL
    var height: CGFloat = 220
    var body: some View {
        VStack(spacing: 4) {
            if file.name.lowercased().hasSuffix(".mp4") || file.name.lowercased().hasSuffix(".mov") {
                VideoView(url: url).frame(height: height)
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().aspectRatio(contentMode: .fit)
                    case .failure: Image(systemName: "photo").foregroundStyle(.tertiary)
                    default: ProgressView()
                    }
                }
                .frame(height: height)
            }
            Text(file.name).font(.caption).lineLimit(1).truncationMode(.middle)
            Text(ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file)).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct KeyValueRow: View {
    var key: String
    var value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(.secondary).frame(width: 140, alignment: .leading)
            Text(value).textSelection(.enabled)
        }
        .font(.callout)
    }
}

extension View {
    /// Shows the CLI command behind a control when developer mode is on.
    func cliHelp(_ cmd: String) -> some View {
        self.help(AppSettings.shared.developerMode ? cmd : "")
    }
}
