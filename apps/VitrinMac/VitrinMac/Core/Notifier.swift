import Foundation
import UserNotifications

/// User notifications for finished stages, Claude's questions and new versions; silent when the user turned them off
/// or the bundle cannot register (an unsigned build started from the command line).
@MainActor final class Notifier {
    static let shared = Notifier()
    private var asked = false
    private var available = true

    private func center() async -> UNUserNotificationCenter? {
        guard AppSettings.shared.notifications, available, Bundle.main.bundleIdentifier != nil else { return nil }
        let c = UNUserNotificationCenter.current()
        if !asked {
            asked = true
            do { _ = try await c.requestAuthorization(options: [.alert, .sound, .badge]) } catch { available = false; return nil }
        }
        let s = await c.notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional ? c : nil
    }

    func post(id: String, title: String, body: String) {
        Task {
            guard let c = await center() else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            try? await c.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    func jobFinished(project: String, name: String, status: String) {
        let key = status == "ok" ? "toast.jobDone" : status == "needs-input" ? "toast.jobNeedsInput" : "toast.jobFailed"
        post(id: "job-\(UUID().uuidString)", title: project, body: L.t(key).replacingOccurrences(of: "{name}", with: name))
    }
}
