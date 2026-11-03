import SwiftUI

/// Competitors and keywords from metadata/research/, read through the Studio's file API.
struct ResearchView: View {
    var session: ProjectSession
    var overview: Overview
    @State private var competitors: Competitors?
    @State private var keywords: KeywordPlan?
    @State private var locale = ""
    @State private var error: String?
    @State private var sortOrder = [KeyPathComparator(\KeywordCandidate.totalSort, order: .reverse)]

    struct Competitors: Decodable {
        struct App: Decodable, Identifiable {
            var trackId: Int
            var name: String
            var sellerName: String?
            var bundleId: String?
            var storefront: String?
            var averageUserRating: Double?
            var userRatingCount: Int?
            var formattedPrice: String?
            var primaryGenre: String?
            var id: Int { trackId }
        }
        struct Analysis: Decodable {
            struct Term: Decodable { var term: String; var count: Int }
            var nameTerms: [Term]?
            var gaps: [String]?
        }
        var generatedAt: String?
        var storefronts: [String]
        var seeds: [String]
        var apps: [App]
        var analysis: Analysis?
    }
    struct KeywordCandidate: Decodable, Identifiable {
        struct Score: Decodable { var score: Double }
        var term: String
        var relevance: Double?
        var competition: Score
        var popularity: Score
        var total: Double?
        var ownRank: Int?
        var id: String { term }
        var totalSort: Double { total ?? -1 }
        var relevanceSort: Double { relevance ?? -1 }
    }
    struct KeywordPlan: Decodable {
        struct Selected: Decodable { var name: [String]?; var subtitle: [String]?; var keywords: [String]? }
        var locale: String
        var storefront: String
        var generatedAt: String?
        var candidates: [KeywordCandidate]
        var selected: Selected?
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.t("page.research")).font(.title.bold())
                        Text(L.t("research.intro")).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L.stage("research")) { Task { await session.run("research") } }.buttonStyle(.borderedProminent).disabled(session.isBusy).cliHelp("vitrin research")
                    Button(L.stage("rank")) { Task { await session.run("rank") } }.disabled(session.isBusy).cliHelp("vitrin rank")
                }
                if let error { Text(error).foregroundStyle(.red).font(.callout) }
                keywordCard
                competitorCard
            }
            .padding(20)
        }
        .task(id: "\(session.changedTick)-\(locale)") { await load() }
        .onAppear { if locale.isEmpty { locale = overview.config?.startLocale ?? "en-US" } }
    }

    private var keywordCard: some View {
        Card {
            HStack {
                Text(L.t("research.keywords")).font(.headline)
                Picker("", selection: $locale) { ForEach(overview.config?.locales ?? [], id: \.self) { Text($0).tag($0) } }.frame(width: 120)
                if let k = keywords { Text("\(k.storefront) · \(L.date(k.generatedAt))").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if let s = keywords?.selected {
                    FlowLayout(spacing: 4) {
                        ForEach((s.name ?? []), id: \.self) { Pill($0, .accent) }
                        ForEach((s.subtitle ?? []), id: \.self) { Pill($0, .info) }
                        ForEach((s.keywords ?? []), id: \.self) { Pill($0) }
                    }.frame(maxWidth: 520)
                }
            }
            if let k = keywords {
                Table(k.candidates.sorted(using: sortOrder), sortOrder: $sortOrder) {
                    TableColumn(L.t("research.term"), value: \.term).width(min: 160)
                    TableColumn(L.t("research.relevance"), value: \.relevanceSort) { c in ScoreBar(value: c.relevance) }.width(110)
                    TableColumn(L.t("research.popularity"), value: \.popularity.score) { c in ScoreBar(value: c.popularity.score) }.width(110)
                    TableColumn(L.t("research.competition"), value: \.competition.score) { c in ScoreBar(value: c.competition.score, invert: true) }.width(110)
                    TableColumn(L.t("research.total"), value: \.totalSort) { c in Text(c.total.map { String(format: "%.2f", $0) } ?? "—").monospacedDigit() }.width(70)
                    TableColumn(L.t("research.ownRank")) { c in Text(c.ownRank.map(String.init) ?? "—").monospacedDigit() }.width(70)
                }
                .frame(height: min(CGFloat(k.candidates.count) * 26 + 30, 520))
            } else {
                Text(L.t("research.noKeywords")).foregroundStyle(.secondary)
            }
        }
    }

    private var competitorCard: some View {
        Card {
            HStack {
                Text(L.t("research.competitors")).font(.headline)
                if let c = competitors { Text("\(c.apps.count) · \(c.storefronts.joined(separator: ", ")) · \(L.date(c.generatedAt))").font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }
            if let c = competitors {
                if let terms = c.analysis?.nameTerms, !terms.isEmpty {
                    FlowLayout(spacing: 4) { ForEach(terms.prefix(24), id: \.term) { Pill("\($0.term) ×\($0.count)") } }
                }
                if let gaps = c.analysis?.gaps, !gaps.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L.t("research.gaps")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(gaps, id: \.self) { Text("• \($0)").font(.callout) }
                    }
                }
                Table(c.apps) {
                    TableColumn(L.t("research.app")) { a in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.name).lineLimit(1)
                            Text(a.sellerName ?? a.bundleId ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.width(min: 220)
                    TableColumn(L.t("research.rating")) { a in Text(a.averageUserRating.map { String(format: "%.2f", $0) } ?? "—").monospacedDigit() }.width(60)
                    TableColumn(L.t("research.ratings")) { a in Text(a.userRatingCount.map { $0.formatted() } ?? "—").monospacedDigit() }.width(90)
                    TableColumn(L.t("research.price")) { a in Text(a.formattedPrice ?? "—") }.width(70)
                    TableColumn(L.t("research.genre")) { a in Text(a.primaryGenre ?? "—") }.width(140)
                    TableColumn(L.t("research.storefront")) { a in Text(a.storefront ?? "—") }.width(70)
                    TableColumn("") { a in
                        Button { NSWorkspace.shared.open(URL(string: "https://apps.apple.com/\(a.storefront ?? "us")/app/id\(a.trackId)")!) } label: { Image(systemName: "arrow.up.right.square") }.buttonStyle(.borderless)
                    }.width(30)
                }
                .frame(height: min(CGFloat(c.apps.count) * 36 + 30, 560))
            } else {
                Text(L.t("research.noCompetitors")).foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        error = nil
        if overview.files["competitors"] == true, let f = try? await session.readFile("metadata/research/competitors.json") {
            competitors = try? JSONDecoder().decode(Competitors.self, from: Data(f.text.utf8))
        } else { competitors = nil }
        if !locale.isEmpty, let f = try? await session.readFile("metadata/research/keywords/\(locale).json"), f.exists {
            keywords = try? JSONDecoder().decode(KeywordPlan.self, from: Data(f.text.utf8))
        } else { keywords = nil }
    }
}

struct ScoreBar: View {
    var value: Double?
    var invert = false
    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(nsColor: .quaternaryLabelColor).opacity(0.4))
                    if let v = value { Capsule().fill(color(v)).frame(width: max(2, g.size.width * v)) }
                }
            }.frame(height: 6)
            Text(value.map { String(format: "%.2f", $0) } ?? "—").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
        }
    }
    private func color(_ v: Double) -> Color {
        let good = invert ? 1 - v : v
        return good > 0.66 ? .green : good > 0.33 ? .orange : .red
    }
}
