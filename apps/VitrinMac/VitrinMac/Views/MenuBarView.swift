import SwiftUI

/// The menu bar extra: the running or last stage, pending decisions per project, and quick actions.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let r = model.runningJob {
            Text("\(r.project.name): \(L.job(r.job))…")
        } else if let f = model.lastFinishedJob {
            Text("\(f.project.name): \(L.job(f.job)) · \(L.t("job.\(f.job.status)"))")
        } else {
            Text(L.t("log.idle"))
        }
        if model.pendingDecisions > 0 { Text(L.t("menu.pending", model.pendingDecisions)) }
        Divider()
        ForEach(model.store.projects) { p in
            let s = model.sessions[p.id]
            Button {
                openWindow(id: "main")
                Task { await model.open(p) }
            } label: {
                let pending = s?.overview?.pendingCount ?? 0
                let next = s?.overview?.next.map { L.stage($0.stage) }
                Text(p.name + (pending > 0 ? " · \(pending)" : "") + (next.map { " · \($0)" } ?? ""))
            }
        }
        Divider()
        Button(L.t("menu.openApp")) { openWindow(id: "main"); NSApp.activate() }.keyboardShortcut("v")
        if let s = model.selectedSession, let url = s.url { Button(L.t("project.openStudio")) { NSWorkspace.shared.open(url) } }
        if let p = model.selectedProject { Button(L.t("menu.openLast").replacingOccurrences(of: "{name}", with: p.name)) { openWindow(id: "main"); Task { await model.open(p) } } }
        Button(L.t("updates.checkNow")) { Task { await model.updates.check() } }
        SettingsLink { Text(L.t("settings.title")) }
        Divider()
        Button(L.t("menu.quit")) { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
