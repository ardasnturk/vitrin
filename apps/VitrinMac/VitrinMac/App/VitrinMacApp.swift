import SwiftUI

@main
struct VitrinMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared
    @State private var settings = AppSettings.shared
    @State private var language = LanguageState.shared

    var body: some Scene {
        Window("Vitrin", id: "main") {
            MainWindow()
                .environment(model)
                .environment(settings)
                .environment(language)
                .frame(minWidth: 1120, minHeight: 680)
                .task { await model.bootstrap() }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L.t("projects.add")) { model.pickProjectFolder() }.keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button(L.t("log.toggle")) { model.showLog.toggle() }.keyboardShortcut("l", modifiers: [.command, .shift])
                Button(L.t("claude.toggle")) { model.showClaude.toggle() }.keyboardShortcut("k", modifiers: [.command, .shift])
            }
            CommandGroup(after: .appInfo) {
                Button(L.t("updates.check")) { Task { await model.updates.check(notify: false) } }
            }
            CommandGroup(replacing: .help) {
                Button(L.t("onb.showAgain")) { settings.onboardingDone = false }
            }
        }

        MenuBarExtra(isInserted: Binding(get: { settings.showMenuBarExtra }, set: { settings.showMenuBarExtra = $0 })) {
            MenuBarView()
                .environment(model)
                .environment(settings)
                .environment(language)
        } label: {
            Image(systemName: model.pendingDecisions > 0 ? "storefront.fill" : "storefront")
                .symbolEffect(.pulse, isActive: model.runningJob != nil)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .environment(settings)
                .environment(language)
        }
    }
}
