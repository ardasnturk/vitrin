import SwiftUI

/// The asc commands of one area, where the area lives: each command group of the area as a card, its subcommands
/// as rows with asc's own one-line description, nested groups opening in place. A row opens the command as a form
/// (`AscCommandRunner`) with the app and the version already filled in. This replaces the flat "All commands" list:
/// every command group asc has is shown on the page it belongs to (see `AscAreas`).
struct AscCommandShelf: View {
    var title: String
    var groups: [String]
    var prefill: [String: String] = [:]
    @State private var helps: [String: AscHelp] = [:]
    @State private var open: [String]?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(groups, id: \.self) { g in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            IconBadge(symbol: AscAreas.symbol(g), colors: BadgeColors.gray, size: 22)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(AscAreas.title(g)).font(.headline)
                                Text(helps[g]?.description ?? "asc \(g)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        if let h = helps[g] {
                            if h.subcommands.isEmpty {
                                row(path: [g], name: g, summary: h.description)
                            } else {
                                ForEach(h.subcommands) { e in CommandRow(path: [g, e.name], entry: e, open: $open) }
                            }
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .glassCard(padding: 12)
                    .task { if helps[g] == nil { helps[g] = try? await AscHelp.load([g]) } }
                }
            }
        }
        .sheet(item: Binding(get: { open.map(OpenPath.init) }, set: { open = $0?.path })) { p in
            VStack(spacing: 0) {
                AscCommandRunner(path: p.path, appID: prefill["app"], prefill: prefill)
                Divider()
                HStack { Spacer(); Button(L.t("common.close")) { open = nil }.keyboardShortcut(.cancelAction) }.padding(12)
            }
            .frame(width: 720, height: 640)
        }
    }

    private func row(path: [String], name: String, summary: String) -> some View {
        Button { open = path } label: {
            HStack { Text(summary.isEmpty ? name : summary).font(.callout).lineLimit(1); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    struct OpenPath: Identifiable { var path: [String]; var id: String { path.joined(separator: " ") } }
}

/// One subcommand: its description first (what it does), the command name small; a group expands to its children.
private struct CommandRow: View {
    var path: [String]
    var entry: AscHelp.Entry
    @Binding var open: [String]?
    @State private var children: [AscHelp.Entry]?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                Task {
                    if children == nil { children = (try? await AscHelp.load(path))?.subcommands ?? [] }
                    if children?.isEmpty == false { expanded.toggle() } else { open = path }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: children?.isEmpty == false ? (expanded ? "chevron.down" : "chevron.right") : "circle.fill")
                        .font(.system(size: children?.isEmpty == false ? 9 : 4)).foregroundStyle(.tertiary).frame(width: 10)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(AscAreas.sentence(entry.summary, fallback: entry.name)).font(.callout).lineLimit(2)
                        Text(path.joined(separator: " ")).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 3)
                .padding(.leading, CGFloat(path.count - 2) * 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded, let children {
                ForEach(children) { c in CommandRow(path: path + [c.name], entry: c, open: $open) }
            }
        }
    }
}

/// Which asc command groups belong where. Every group asc lists appears in exactly one place, except the local
/// tooling the app does for you or that needs a terminal (`AscAreas.notInApp`).
enum AscAreas {
    // An app's tabs
    static let release = ["versions", "review", "submit", "release", "release-notes", "publish", "validate", "status"]
    static let listing = ["localizations", "metadata", "categories", "age-rating", "accessibility", "encryption", "eula", "app-tags", "app-setup", "apps"]
    static let visuals = ["screenshots", "video-previews", "product-pages", "app-events", "asset-library"]
    static let builds = ["builds", "build-localizations", "build-bundles"]
    static let testflight = ["testflight"]
    static let reviews = ["reviews"]
    static let money = ["pricing", "pre-orders", "iap", "subscriptions", "storekit"]
    static let analytics = ["analytics", "insights", "performance"]
    static let more = ["app-clips", "game-center", "background-assets", "marketplace", "alternative-distribution", "routing-coverage", "android-ios-mapping", "nominations"]
    // Team pages
    static let users = ["users", "actors", "sandbox"]
    static let devices = ["devices"]
    static let signing = ["certificates", "profiles", "bundle-ids", "signing", "merchant-ids", "pass-type-ids", "notarization"]
    static let reports = ["finance", "optimize"]
    static let automation = ["xcode-cloud", "webhooks", "workflow", "notify"]
    static let ads = ["ads"]
    static let account = ["account", "agreements", "system-status"]
    /// Done by the app itself or only meaningful in a terminal: sign-in, docs, local Xcode builds, raw API and
    /// schema access, shell completion, telemetry.
    static let notInApp = ["auth", "doctor", "install-skills", "init", "docs", "web", "xcode", "distribute", "ipa-info", "pkg-info", "migrate", "diff", "capabilities", "search", "snitch", "version", "completion", "schema", "api", "telemetry"]

    @MainActor static func title(_ g: String) -> String {
        let key = "ascgroup.\(g)"
        let t = L.t(key)
        return t == key ? g.replacingOccurrences(of: "-", with: " ").capitalized : t
    }

    static func symbol(_ g: String) -> String {
        switch g {
        case "versions", "release", "publish": return "shippingbox.fill"
        case "review", "submit", "validate": return "checkmark.seal.fill"
        case "localizations", "metadata": return "text.alignleft"
        case "screenshots", "asset-library": return "photo.fill"
        case "video-previews": return "play.rectangle.fill"
        case "product-pages", "app-events": return "rectangle.stack.fill"
        case "builds", "build-localizations", "build-bundles": return "hammer.fill"
        case "testflight", "sandbox": return "airplane"
        case "reviews": return "star.bubble.fill"
        case "pricing", "pre-orders", "iap", "subscriptions", "storekit", "finance": return "creditcard.fill"
        case "analytics", "insights", "performance", "optimize": return "chart.xyaxis.line"
        case "users", "actors": return "person.2.fill"
        case "devices": return "iphone.gen3"
        case "certificates", "profiles", "bundle-ids", "signing", "merchant-ids", "pass-type-ids", "notarization": return "lock.shield.fill"
        case "xcode-cloud", "webhooks", "workflow", "notify": return "gearshape.2.fill"
        case "ads": return "megaphone.fill"
        default: return "square.grid.2x2.fill"
        }
    }

    /// asc's summaries end with a period and start with a verb ("List App Store versions."): shown as they are,
    /// without the period.
    static func sentence(_ summary: String, fallback: String) -> String {
        let s = summary.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return fallback }
        return s.hasSuffix(".") ? String(s.dropLast()) : s
    }
}
