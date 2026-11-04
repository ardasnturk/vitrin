import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var signalSources: [DispatchSourceSignal] = []

    /// SIGTERM/SIGINT/SIGHUP (a `kill`, a logout) do not go through applicationWillTerminate; stop the Studios first.
    func applicationDidFinishLaunching(_ notification: Notification) {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { AppModel.shared.stopAll(); exit(0) }
            src.resume()
            signalSources.append(src)
        }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification, NSWindow.didChangeOcclusionStateNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowsChanged), name: name, object: nil)
        }
    }

    /// `willClose` comes while the window is still on screen: look once it is gone.
    @objc private func windowsChanged() {
        Task { updateDockIcon() }
    }

    /// With a window open Vitrin is an ordinary app: the Dock icon, ⌘Tab and its menus. With none it lives in the menu
    /// bar, like Remote Code. Without the menu bar item the Dock icon stays, or nothing would lead back to the app.
    private func updateDockIcon() {
        let settings = AppSettings.shared
        let menuBarOnly = settings.keepInMenuBar && settings.showMenuBarExtra && !NSApp.windows.contains(where: Self.isOpen)
        let policy: NSApplication.ActivationPolicy = menuBarOnly ? .accessory : .regular
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // A window opened from the menu bar needs this for the app's menus to come back.
        if policy == .regular { NSApp.activate() }
    }

    /// A document-like window: not the menu bar panel or the status item. A minimized one is only reachable in the Dock.
    private static func isOpen(_ window: NSWindow) -> Bool {
        !(window is NSPanel) && window.styleMask.contains(.titled) && (window.isVisible || window.isMiniaturized)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // With "keep in menu bar" the app lives on in the menu bar; the Studios keep running for their projects.
        !AppSettings.shared.keepInMenuBar
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }?.makeKeyAndOrderFront(nil) }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stopAll()
    }
}
