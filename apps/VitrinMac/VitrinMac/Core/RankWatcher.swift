import Foundation

enum RankSchedule: String, CaseIterable, Sendable {
    case off, daily, weekly

    var days: Int? {
        switch self {
        case .off: nil
        case .daily: 1
        case .weekly: 7
        }
    }
}

/// When to run `vitrin rank` by itself, and what in its result is worth a notification. The snapshots in
/// `metadata/rankings/` are the only record of the last check, so a check run from the Studio or the terminal counts.
enum RankWatcher {
    struct Move: Decodable, Equatable, Sendable {
        var term: String
        var after: Int?
    }

    struct Highlights: Decodable, Equatable, Sendable {
        var up: Int
        var down: Int
        var enteredTop10: [Move]
        var leftTop10: [Move]
    }

    struct Result: Decodable, Sendable {
        var date: String
        var highlights: Highlights?
    }

    static let interval: Duration = .seconds(3600)
    /// Twenty terms per language at the search API's pace, for several languages.
    static let timeout: TimeInterval = 1800
    /// After a failure (offline, no bundle id): enough to not retry all day, soon enough to catch today's check.
    private static let retryAfter: TimeInterval = 6 * 3600

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// The date of the newest snapshot; nil when the project was never measured.
    static func newestSnapshot(in projectPath: String) -> String? {
        let folder = URL(fileURLWithPath: projectPath).appendingPathComponent("metadata/rankings")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return files.compactMap { name -> String? in
            guard name.hasSuffix(".json") else { return nil }
            let day = String(name.dropLast(5))
            return dayFormat.date(from: day) == nil ? nil : day
        }.max()
    }

    /// A project nobody measured stays out: the app may not be live, and the schedule shouldn't start one on its own.
    static func isDue(newest: String?, schedule: RankSchedule, lastAttempt: Date?, now: Date) -> Bool {
        guard let days = schedule.days, let newest, let last = dayFormat.date(from: newest) else { return false }
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < retryAfter { return false }
        return now.timeIntervalSince(last) >= Double(days) * 86400
    }

    /// One line for the notification, the most important news first; nil when nothing is worth interrupting for.
    @MainActor static func message(_ h: Highlights?) -> String? {
        guard let h else { return nil }
        if let top = h.enteredTop10.first, let rank = top.after { return L.t("rank.enteredTop10", top.term, rank) }
        if let lost = h.leftTop10.first { return L.t("rank.leftTop10", lost.term) }
        return h.up + h.down > 0 ? L.t("rank.moves", h.up, h.down) : nil
    }
}
