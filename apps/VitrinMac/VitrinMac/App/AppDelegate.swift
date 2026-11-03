import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
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
