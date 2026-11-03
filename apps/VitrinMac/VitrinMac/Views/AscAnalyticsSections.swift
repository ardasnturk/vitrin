import SwiftUI

/// `asc insights weekly`: this week against last week, each metric with why it is missing when it is.
struct WeeklyInsights: View {
    var appID: String
    /// Monday of last week.
    private var week: String {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        let monday = c.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let last = c.date(byAdding: .day, value: -7, to: monday) ?? monday
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = c.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: last)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(L.t("asc.analytics.weekly"))
            AscLoad(args: ["insights", "weekly", "--app", appID, "--source", "analytics", "--week", week]) { doc, _ in
                let metrics = (doc.objectValue?["metrics"]?.arrayValue ?? []).compactMap(\.objectValue)
                let missing = metrics.filter { $0["status"]?.stringValue == "unavailable" }
                let shown = metrics.filter { $0["status"]?.stringValue != "unavailable" }
                VStack(alignment: .leading, spacing: 8) {
                    if !shown.isEmpty { AscRowList(rows: shown.enumerated().compactMap { AscDataView.row(.object($0.element), index: $0.offset) }) }
                    if let why = missing.first?["reason"]?.stringValue {
                        Label(why.contains("not permitted") ? L.t("asc.analytics.noPermission") : why, systemImage: "lock.fill").font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).glassCard(padding: 14)
                    }
                }
            }
        }
    }
}

/// `asc performance overview`: Xcode's performance categories and trends, or a sentence when Apple has none yet.
struct PerformanceOverview: View {
    var appID: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(L.t("asc.analytics.performance"))
            AscLoad(args: ["performance", "overview", "--app", appID], errorText: L.t("asc.analytics.noPerformance")) { doc, _ in
                let o = doc.objectValue ?? [:]
                let insights = o["insights"]?.objectValue ?? [:]
                let categories = o["categories"]?.arrayValue ?? []
                let trends = (insights["regressions"]?.arrayValue ?? []) + (insights["trendingUp"]?.arrayValue ?? [])
                if categories.isEmpty && trends.isEmpty {
                    AscDataView(doc: .array([]), empty: L.t("asc.analytics.noPerformance"))
                } else {
                    if !trends.isEmpty { AscDataView(doc: .array(trends)) }
                    if !categories.isEmpty { AscDataView(doc: .array(categories)) }
                }
            }
        }
    }
}
