import SwiftUI

/// An App Store Connect app without a linked project folder: what the API says about it, read-only, and the button
/// that links a folder so Vitrin's pipeline can run for it.
struct AppOverviewView: View {
    @Environment(AppModel.self) private var model
    var app: ASCApp

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    AppIconPlaceholder(size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name).font(.title2.bold())
                        Text(app.bundleId).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        HStack(spacing: 6) {
                            ForEach(app.platforms, id: \.self) { Pill(ASCWords.platform($0), .accent) }
                            if app.platforms.isEmpty { Text(L.t("apps.noVersions")).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    Spacer()
                    Button(L.t("apps.openASC")) { NSWorkspace.shared.open(app.ascURL) }
                }

                Card(L.t("apps.versions")) {
                    if app.versions.isEmpty {
                        Text(L.t("apps.noVersions")).foregroundStyle(.secondary)
                    } else {
                        ForEach(app.versions) { v in
                            HStack(spacing: 10) {
                                Text(ASCWords.platform(v.platform)).frame(width: 90, alignment: .leading)
                                Text(v.version).font(.body.monospacedDigit()).frame(width: 90, alignment: .leading)
                                Pill(ASCWords.state(v.state), ASCWords.tone(v.state))
                                Spacer()
                                if let c = v.createdAt { Text(L.date(c)).font(.caption).foregroundStyle(.secondary) }
                            }
                            .font(.callout)
                        }
                    }
                }

                Card {
                    KeyValueRow(key: L.t("apps.sku"), value: app.sku)
                    KeyValueRow(key: L.t("apps.primaryLocale"), value: app.primaryLocale)
                    KeyValueRow(key: L.t("apps.ascId"), value: app.id)
                    if let at = model.ascApps.loadedAt { Text(L.t("apps.refreshedAt").replacingOccurrences(of: "{time}", with: L.relative(at.ISO8601Format()))).font(.caption).foregroundStyle(.tertiary) }
                }

                Card(accent: true) {
                    if let linked = model.linkedProject(for: app) {
                        Text(L.t("apps.linked").replacingOccurrences(of: "{project}", with: linked.name)).font(.callout)
                        Button(L.t("apps.openProject")) { Task { await model.open(linked) } }.buttonStyle(.borderedProminent)
                    } else {
                        Text(L.t("apps.linkHint")).font(.callout)
                        Button { model.pickProjectFolder() } label: { Label(L.t("apps.linkProject"), systemImage: "link.badge.plus") }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("app.linkProject")
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("app.overview")
    }
}
