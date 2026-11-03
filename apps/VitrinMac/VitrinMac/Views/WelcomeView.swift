import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text(L.t("welcome.title")).font(.largeTitle.bold())
            Text(L.t("welcome.intro")).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 520)
            Button { model.pickProjectFolder() } label: { Label(L.t("projects.add"), systemImage: "folder.badge.plus") }.buttonStyle(.borderedProminent).controlSize(.large)
            if model.cli == nil, !model.locating { CLIMissingCard() }
            else if let cli = model.cli { Text("\(L.t("cli.found")) · \(cli.description)").font(.caption).foregroundStyle(.tertiary) }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Install instructions when no CLI is found (Node.js and Vitrin).
struct CLIMissingCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Card(L.t("cli.notFound"), accent: true) {
            if let e = model.cliError { Text(e).font(.callout).foregroundStyle(.secondary) }
            Text(L.t("cli.installIntro")).font(.callout)
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("cli.installNode")).font(.callout)
                CopyCode(text: "brew install node")
                Text(L.t("cli.installVitrin")).font(.callout)
                CopyCode(text: "npm install -g @ardasnturk/vitrin")
                Text(L.t("cli.installPlugin")).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button(L.t("cli.searchAgain")) { Task { await model.locateCLI(); if let p = model.selectedProject { await model.open(p) } } }
                SettingsLink { Text(L.t("cli.setPath")) }
            }
        }
        .frame(maxWidth: 560)
    }
}

struct CLIMissingView: View {
    var body: some View {
        VStack { CLIMissingCard() }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
