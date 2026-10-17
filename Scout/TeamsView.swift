import Charts
import SwiftUI

/// Every team at the current event: TBA/Statbotics numbers beside your scouted averages.
/// Tap a column header to sort.
struct TeamsView: View {
    @Environment(Store.self) private var store
    @AppStorage("event") private var event = ""
    @AppStorage("eventName") private var eventName = ""
    @AppStorage("ourTeam") private var ourTeam = 0
    @State private var sort = [KeyPathComparator(\TeamStats.pointsKey, order: .reverse)]
    @State private var search = ""
    @AppStorage("onlyUnscouted") private var onlyUnscouted = false
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        let rows = store.db.stats(event: event)
            .filter { search.isEmpty || String($0.team).hasPrefix(search) || $0.name.localizedCaseInsensitiveContains(search) }
            .filter { !onlyUnscouted || $0.matches == 0 }
            .sorted(using: sort)
        let next: [Int: String] = onlyUnscouted ? nextMatches() : [:]
        NavigationStack {
            Group { if hSize == .compact { compactList(rows, next: next) } else {
            Table(rows, sortOrder: $sort) {
                Group {
                    TableColumn("Team", value: \.team) { (s: TeamStats) in teamCell(s, next: next[s.team]) }
                    .width(min: 120)
                    TableColumn("Rank", value: \.rank) { (s: TeamStats) in Text(s.rank == 0 ? "–" : String(s.rank)) }
                    TableColumn("H2H", value: \.h2h) { (s: TeamStats) in Text(s.h2h == 0 ? "–" : String(Int(s.h2h.rounded()))) }
                        .width(min: 46)
                }
                Group {
                    TableColumn("EPA", value: \.epa) { (s: TeamStats) in Text(short(s.epa)) }
                    TableColumn("Live", value: \.liveEPA) { (s: TeamStats) in Text(short(s.liveEPA)).foregroundStyle(Color.telePhase) }
                    TableColumn("OPR", value: \.opr) { (s: TeamStats) in Text(short(s.opr)) }
                    TableColumn("Pts", value: \.pointsKey) { (s: TeamStats) in Text(short(s.points)).bold().foregroundStyle(Color.accentColor) }
                        .width(min: 56)
                }
                Group {
                    TableColumn("Auto", value: \.autoKey) { (s: TeamStats) in Text(short(s.autoFuel)) }
                    TableColumn("Tele", value: \.teleKey) { (s: TeamStats) in Text(short(s.teleFuel)) }
                    TableColumn("Tower", value: \.towerKey) { (s: TeamStats) in Text(short(s.tower)) }
                }
                Group {
                    TableColumn("Drive", value: \.driverKey) { (s: TeamStats) in Text(short(s.driver)) }
                    TableColumn("Def", value: \.defenseKey) { (s: TeamStats) in Text(short(s.defense)) }
                    TableColumn("Robust", value: \.robustness) { (s: TeamStats) in RobustBadge(value: Int(s.robustness)) }
                        .width(min: 64)
                }
            }
            } }
            .navigationTitle(event.isEmpty ? "Teams" : "Teams · \(event)")
            .navigationDestination(for: Int.self) { TeamDetail(team: $0) }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Show", selection: $onlyUnscouted) {
                        Text(hSize == .compact ? "All" : "All teams").tag(false)
                        Text(hSize == .compact ? "Unscouted" : "Not scouted yet").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: hSize == .compact ? 180 : 260)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    HelpButton(title: "Teams", items: Help.teams)
                    ShareLink(item: Slack.overview(db: store.db, event: event, eventName: eventName, ourTeam: ourTeam)) {
                        Label("Share overview to Slack", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .searchable(text: $search, prompt: "Team number or name")
            .overlay {
                if rows.isEmpty && onlyUnscouted {
                    ContentUnavailableView("Every team has been scouted", systemImage: "checkmark.circle",
                        description: Text("Each team at the event has at least one scouted match."))
                } else if rows.isEmpty {
                    ContentUnavailableView("No teams yet", systemImage: "tablecells",
                        description: Text("Pick your event in Data to load every team, or scan your scouts' QR codes."))
                }
            }
        }
    }
}

extension TeamsView {
    /// iPhone: Apple's tables show one column there, so a list with the key numbers instead, plus a
    /// Sort menu in place of the column headers.
    func compactList(_ rows: [TeamStats], next: [Int: String]) -> some View {
        List(rows) { s in
            NavigationLink(value: s.team) {
                HStack(spacing: 12) {
                    teamLabel(s, next: next[s.team])
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(short(s.points)) pts").font(.headline).monospacedDigit().foregroundStyle(Color.accentColor)
                        Text("\(s.liveEPA > 0 ? "live" : "EPA") \(short(s.liveEPA > 0 ? s.liveEPA : s.epa)) · tower \(short(s.tower))")
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    RobustBadge(value: Int(s.robustness))
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu("Sort", systemImage: "arrow.up.arrow.down") {
                    Button("Scouted points") { sort = [KeyPathComparator(\TeamStats.pointsKey, order: .reverse)] }
                    Button("Live EPA") { sort = [KeyPathComparator(\TeamStats.liveEPA, order: .reverse)] }
                    Button("Season EPA") { sort = [KeyPathComparator(\TeamStats.epa, order: .reverse)] }
                    Button("Tower") { sort = [KeyPathComparator(\TeamStats.towerKey, order: .reverse)] }
                    Button("Rank") { sort = [KeyPathComparator(\TeamStats.rank)] }
                    Button("Team number") { sort = [KeyPathComparator(\TeamStats.team)] }
                }
            }
        }
    }

    func teamCell(_ s: TeamStats, next: String?) -> some View {
        NavigationLink(value: s.team) { teamLabel(s, next: next) }
    }

    func teamLabel(_ s: TeamStats, next: String?) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "\(s.team)").font(.headline) + Text("  \(s.matches)m").font(.caption).foregroundStyle(.secondary)
                    + Text(s.tier > 0 ? "  T\(s.tier)" : "").font(.caption.weight(.heavy)).foregroundStyle(tierColor(s.tier))
                if !s.name.isEmpty { Text(s.name).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                if let next { Text("next: \(next)").font(.caption.weight(.bold)).foregroundStyle(Color.telePhase) }
            }
    }

    /// Each team's next scheduled match after the latest one scouted, so scouts know when to catch it.
    func nextMatches() -> [Int: String] {
        let schedule = store.db.info?.schedule ?? []
        let scouted = store.db.matches.filter { $0.event == event }.map { Fetch.order($0.type, $0.match) }.max()
        var next: [Int: String] = [:]
        for m in schedule where Fetch.order(m.type, m.match) > (scouted ?? -1) {
            for (i, t) in (m.red + m.blue).enumerated() where t > 0 && next[t] == nil {
                next[t] = "\(m.label) \(i < 3 ? "Red" : "Blue") \(i % 3 + 1)"
            }
        }
        return next
    }
}

/// Whole numbers from 10 up so 13 columns fit on an iPad mini.
private func short(_ x: Double) -> String { x == 0 ? "–" : x >= 10 ? String(Int(x.rounded())) : String(format: "%.1f", x) }

/// Scouted numbers: a dash only when never scouted, so a real 0 shows as 0.
private func short(_ x: Double?) -> String { x.map { $0 == 0 ? "0" : $0 >= 10 ? String(Int($0.rounded())) : String(format: "%.1f", $0) } ?? "–" }

struct TeamDetail: View {
    let team: Int
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("event") private var event = ""
    @State private var removing: Int?

    var body: some View {
        let info = store.db.info
        let s = store.db.stats(event: event).first { $0.team == team }
        let all = store.db.matches.filter { $0.team == team }.sorted { ($0.event, $0.match) < ($1.event, $1.match) }
        let here = all.filter { event.isEmpty || $0.event == event }
        let scheduled = info?.schedule.filter { ($0.red + $0.blue).contains(team) } ?? []
        let shots = here.flatMap(\.shots)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "\(team)").font(.system(size: 48, weight: .heavy, design: .rounded))
                        Text(s?.name.isEmpty == false ? s!.name : "Team \(team)").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            if let rank = s?.rank, rank > 0 { pill("Rank \(rank)", .accentColor) }
                            if let address = info?.pits[String(team)] { pill("Pit \(address)", .gray) }
                            if store.db.dnp.contains(team) { pill("DNP", .redAlliance) }
                            if store.db.picked.contains(team) { pill("Taken", .gray) }
                        }
                    }
                    Spacer()
                }
                .card()

                if let s {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                        StatTile(label: "Avg points", value: f(s.points), color: .accentColor)
                        StatTile(label: "Season EPA", value: f(s.epa))
                        StatTile(label: "Live EPA", value: f(s.liveEPA), color: .telePhase)
                        StatTile(label: "OPR", value: f(s.opr))
                        StatTile(label: "Head-to-head", value: s.h2h == 0 ? "–" : String(Int(s.h2h.rounded())), color: .endPhase)
                        StatTile(label: "Auto fuel", value: f(s.autoFuel), color: .autoPhase)
                        StatTile(label: "Tele fuel", value: f(s.teleFuel), color: .telePhase)
                        StatTile(label: "Tower pts", value: f(s.tower), color: .endPhase)
                        StatTile(label: "Passes", value: f(s.passes))
                        StatTile(label: "Accuracy", value: f(s.accuracy))
                        StatTile(label: "Driver", value: f(s.driver))
                        StatTile(label: "Defense", value: f(s.defense))
                        StatTile(label: "Died", value: s.died.map { "\(Int($0 * 100))%" } ?? "–", color: (s.died ?? 0) > 0 ? .redAlliance : .primary)
                    }
                    .card()
                }

                PreScoutCard(team: team)

                if !here.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Points by match", systemImage: "chart.bar.fill", color: .telePhase)
                        Chart {
                            ForEach(here) { m in
                                let x = "\(m.type == .qual ? "Q" : m.type == .playoff ? "P" : "Pr")\(m.match)"
                                BarMark(x: .value("Match", x), y: .value("Points", (m.autoFuel ?? 0) + (m.autoClimb ? Points.autoTower : 0)))
                                    .foregroundStyle(by: .value("Phase", "Auto"))
                                BarMark(x: .value("Match", x), y: .value("Points", m.teleFuel ?? 0))
                                    .foregroundStyle(by: .value("Phase", "Teleop"))
                                BarMark(x: .value("Match", x), y: .value("Points", Points.tower[min(max(m.climb ?? 0, 0), 3)]))
                                    .foregroundStyle(by: .value("Phase", "Tower"))
                            }
                        }
                        .chartForegroundStyleScale(["Auto": Color.autoPhase, "Teleop": Color.telePhase, "Tower": Color.endPhase])
                        .frame(height: 220)
                    }
                    .card()
                }

                if !shots.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Where they shoot from", systemImage: "scope", color: .accentColor, detail: "\(shots.count) spots")
                        ShotField(shots: shots)
                    }
                    .card()
                }

                if let p = store.pit(team) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionHeader(title: "Pit", systemImage: "wrench.and.screwdriver.fill", color: .gray, detail: "claims vs scouted")
                            RobustBadge(value: p.robustness)
                        }
                        LabeledContent("Drivetrain", value: "\(p.drivetrain) · \(p.trench ? "under trench" : "no trench") · \(p.bump ? "over bump" : "no bump")")
                        LabeledContent("Intake", value: list([p.floorIntake ? "floor" : nil, p.outpostIntake ? "outpost" : nil, p.depotIntake ? "depot" : nil])
                                       + (p.hopper > 0 ? " · holds \(p.hopper)" : ""))
                        LabeledContent("Shooting", value: list([["", "at the hub", "whole zone", "from neutral zone"][min(max(p.range, 0), 3)],
                                                                 p.shotRate > 0 ? "\(p.shotRate)/s claimed" : nil, p.turret ? "turret" : nil,
                                                                 p.shootsOnMove ? "on the move" : nil, p.canPass ? "passes to its side" : nil]))
                        LabeledContent("Tower", value: list([p.maxClimb > 0 ? "claims L\(p.maxClimb)" : "no climb claimed",
                                                              p.climbSeconds > 0 ? "\(p.climbSeconds) s" : nil, p.sideClimb ? "side" : nil,
                                                              p.autoClimb ? "L1 in auto" : nil,
                                                              s.map { $0.matches > 0 ? "scouted \(f($0.tower)) pts" : nil } ?? nil]))
                        LabeledContent("Auto", value: list([p.autoCount > 0 ? "\(p.autoCount) autos" : nil,
                                                             p.autoFuelClaim > 0 ? "claims \(p.autoFuelClaim) fuel" : nil,
                                                             s.map { $0.matches > 0 ? "scouted \(f($0.autoFuel))" : nil } ?? nil,
                                                             p.autoNeutral ? "neutral zone" : nil,
                                                             p.autoConsistency > 0 ? "works: \(PitRecord.autoConsistencyLabels[min(p.autoConsistency, 4)].lowercased())" : nil]))
                        LabeledContent("Team", value: list(["wants \(p.role.rawValue.lowercased())",
                                                             ["", "1st-year driver", "2nd-year driver", "3+ year driver"][min(max(p.driverYears, 0), 3)]]))
                        if !p.worries.isEmpty { Label(p.worries, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.autoPhase) }
                        if !p.notes.isEmpty { Text(p.notes).padding(.top, 4) }
                    }
                    .card()
                }

                if !scheduled.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Schedule", systemImage: "calendar", color: .gray)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                            ForEach(scheduled, id: \.self) { m in
                                Text(m.label).font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .foregroundStyle(.white)
                                    .background(Color.alliance(m.red.contains(team)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                    .card()
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Matches", systemImage: "list.bullet", color: .gray, detail: "touch and hold to delete")
                    if all.isEmpty { Text("Not scouted yet.").foregroundStyle(.secondary) }
                    ForEach(all.reversed()) { m in
                        NavigationLink { MatchForm(editing: m) } label: { matchRow(m) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete this record", systemImage: "trash", role: .destructive) {
                                    store.db.matches.removeAll { $0.id == m.id }
                                }
                            }
                    }
                }
                .card()

                let elsewhere = Dictionary(grouping: all.filter { $0.event != event }, by: \.event)
                if !elsewhere.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Other events", systemImage: "clock.arrow.circlepath", color: .gray, detail: "past competitions")
                        ForEach(elsewhere.keys.sorted(), id: \.self) { key in
                            let ms = elsewhere[key]!.sorted { Fetch.order($0.type, $0.match) < Fetch.order($1.type, $1.match) }
                            let scored = ms.filter(\.hasData)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.db.eventNames[key].map { "\($0) (\(key))" } ?? key).font(.headline)
                                Text("\(ms.count) matches scouted · \(scored.isEmpty ? "–" : f(Double(scored.map(\.points).reduce(0, +)) / Double(scored.count))) avg pts")
                                    .font(.callout).foregroundStyle(.secondary)
                                ForEach(ms.filter { !($0.notes + $0.weaknesses + $0.breaks).isEmpty }) { m in
                                    Text("\(m.type == .qual ? "Q" : m.type == .playoff ? "P" : "Pr")\(m.match): \([m.notes, m.weaknesses, m.breaks].filter { !$0.isEmpty }.joined(separator: " · "))")
                                        .font(.callout)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .card()
                }

                Button("Remove team from this event", systemImage: "trash", role: .destructive) { removing = team }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .padding()
        }
        .background(Color.page)
        .navigationTitle(Text(verbatim: "Team \(team)"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmRemove($removing, store: store, event: event) { dismiss() }
        .toolbar {
            ShareLink(item: Slack.team(team, db: store.db, event: event)) { Label("Share to Slack", systemImage: "square.and.arrow.up") }
            Link("TBA", destination: URL(string: "https://www.thebluealliance.com/team/\(team)")!)
            Link("Statbotics", destination: URL(string: "https://www.statbotics.io/team/\(team)")!)
        }
    }

    /// A scored number, or a dash when it wasn't scored.
    private func n(_ x: Int?) -> String { x.map(String.init) ?? "–" }

    private func list(_ parts: [String?]) -> String {
        let kept = parts.compactMap { $0 }.filter { !$0.isEmpty }
        return kept.isEmpty ? "–" : kept.joined(separator: " · ")
    }

    private func matchRow(_ m: MatchRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(Color.alliance(m.alliance == .red)).frame(width: 10, height: 10)
                Text("\(m.type.rawValue) \(m.match)").font(.headline)
                if m.died { pill("DIED", .redAlliance) }
                if m.tipped { pill("TIPPED", .redAlliance) }
                if m.eStopped { pill("E-STOP", .redAlliance) }
                if m.noShoot { pill("NO SHOTS", .gray) }
                if m.aStopped { pill("A-STOP", .autoPhase) }
                Spacer()
                Text("\(m.points) pts").font(.headline).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            Text("Auto \(n(m.autoFuel))\(m.autoClimb ? " + L1" : "") · tele \(n(m.teleFuel)) · \(n(m.passes)) passes · \(m.climb.map { $0 == 0 ? "no climb" : "L\($0)" } ?? "climb –") · \(m.role?.rawValue ?? "role –")")
                .font(.callout).foregroundStyle(.secondary)
            if !m.weaknesses.isEmpty { Label(m.weaknesses, systemImage: "scope").font(.callout) }
            if !m.breaks.isEmpty { Label(m.breaks, systemImage: "wrench.adjustable").font(.callout).foregroundStyle(Color.autoPhase) }
            if !m.notes.isEmpty { Text(m.notes).font(.callout) }
            Text("\(m.scout.isEmpty ? "unknown scout" : m.scout) · \(m.event)").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct TeamRef: Identifiable { let id: Int }

func tierColor(_ tier: Int) -> Color { [Color.secondary, .green, .telePhase, .orange, .redAlliance][min(max(tier, 0), 4)] }

/// Pre-scouting for one team: a tier and notes from videos, TBA, or past events. Saved with a tap
/// so typing doesn't rewrite the whole save file on every key.
struct PreScoutCard: View {
    let team: Int
    @Environment(Store.self) private var store
    @State private var draft = PreScout()
    @State private var loaded = false

    var body: some View {
        let saved = store.db.prescouts.first { $0.team == team }
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Pre-scout", systemImage: "binoculars.fill", color: tierColor(draft.tier == 0 ? 2 : draft.tier),
                          detail: saved.map { "saved \($0.updated.formatted(date: .abbreviated, time: .omitted))" } ?? "before the event")
            Choice(options: PreScout.tiers.indices.map { ($0, $0 == 0 ? "–" : "T\($0)") }, selection: $draft.tier, color: tierColor(draft.tier))
            Text(PreScout.tiers[draft.tier]).font(.caption).foregroundStyle(.secondary)
            TextField("What did you see in videos, TBA, or past events?", text: $draft.notes, axis: .vertical)
                .lineLimit(2...6)
                .padding(10)
                .background(Color.well, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if draft.tier != (saved?.tier ?? 0) || draft.notes != (saved?.notes ?? "") {
                Button("Save pre-scout", systemImage: "checkmark.circle.fill") { store.save(draft) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .card()
        .onAppear {
            guard !loaded else { return }
            draft = saved ?? PreScout(team: team)
            loaded = true
        }
    }
}

/// Build a picklist from several factors at once: set a weight for each, watch the ranking change,
/// then apply it. Weights are remembered.
struct WeightedSort: View {
    let stats: [TeamStats]
    let apply: ([Int]) -> Void
    @AppStorage("pickWeights") private var saved = ""
    @State private var weights: [String: Double] = Pick.defaultWeights
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let scores = Pick.scores(stats, weights: weights)
        let ranked = stats.sorted { (scores[$0.team] ?? 0, $0.pointsKey) > (scores[$1.team] ?? 0, $1.pointsKey) }
        NavigationStack {
            Form {
                Section {
                    ForEach(Pick.factors, id: \.key) { factor in
                        HStack {
                            Text(factor.label).frame(width: 190, alignment: .leading)
                            Slider(value: Binding(get: { weights[factor.key] ?? 0 }, set: { weights[factor.key] = $0.rounded() }), in: 0...5, step: 1)
                            Text(weights[factor.key, default: 0] == 0 ? "off" : "×\(Int(weights[factor.key, default: 0]))")
                                .monospacedDigit().foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("How much each factor counts")
                } footer: {
                    Text("Each factor is scaled 0-100 across this event's teams. Teams with no data for a factor get the middle, so missing data neither helps nor hurts.")
                }
                Section("Ranking") {
                    ForEach(Array(ranked.prefix(24).enumerated()), id: \.element.team) { i, s in
                        HStack(spacing: 12) {
                            Text("\(i + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                            Text(verbatim: "\(s.team)").font(.headline).frame(width: 60, alignment: .leading)
                            Text(s.name).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Gauge(value: scores[s.team] ?? 0) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity).frame(width: 90).tint(Color.accentColor)
                            Text("\(Int(((scores[s.team] ?? 0) * 100).rounded()))").monospacedDigit().bold().frame(width: 34, alignment: .trailing)
                        }
                    }
                }
            }
            .navigationTitle("Weighted picklist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply to picklist") { apply(ranked.map(\.team)); dismiss() }.bold().disabled(scores.isEmpty)
                }
            }
            .onAppear {
                if let data = saved.data(using: .utf8), let w = try? JSONDecoder().decode([String: Double].self, from: data) { weights = w }
            }
            .onChange(of: weights) {
                saved = String(decoding: (try? JSONEncoder().encode(weights)) ?? Data(), as: UTF8.self)
            }
        }
    }
}

/// Small colored label used across team views.
func pill(_ text: String, _ color: Color) -> some View {
    Text(text).font(.caption.weight(.heavy))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(.white)
        .background(color, in: Capsule())
}

/// The ordered picklist. Rank mode follows the readme's draft night: drag to sort, swipe for DNP.
/// Alliance selection mode is for the field: tap a team the moment it's picked, and the best
/// available team stays on top. Picks from Nexus / TBA alliances are marked automatically.
struct PicklistView: View {
    @Environment(Store.self) private var store
    @AppStorage("event") private var event = ""
    @AppStorage("ourTeam") private var ourTeam = 0
    @AppStorage("tbaKey") private var tbaKey = ""
    @AppStorage("nexusKey") private var nexusKey = ""
    @State private var selecting = false
    @State private var removing: Int?
    @State private var weighting = false
    @State private var info: TeamRef?
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        let stats = Dictionary(uniqueKeysWithValues: store.db.stats(event: event).map { ($0.team, $0) })
        let alliances = store.db.info?.key == event ? store.db.info?.alliances ?? [] : []
        var allianceOf: [Int: Int] = [:]
        for (i, teams) in alliances.enumerated() { for t in teams { allianceOf[t] = i + 1 } }
        let taken = Set(store.db.picked).union(allianceOf.keys)
        let available = store.db.picklist.filter { !taken.contains($0) && !store.db.dnp.contains($0) && $0 != ourTeam }

        return NavigationStack {
            List {
                if hSize == .compact { modePicker.listRowBackground(Color.clear).listRowInsets(EdgeInsets()) }
                if selecting {
                    Section {
                        if let best = available.first {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("BEST AVAILABLE").font(.caption.weight(.heavy)).tracking(1).foregroundStyle(.secondary)
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(verbatim: "\(best)").font(.system(size: 52, weight: .heavy, design: .rounded))
                                    Text(stats[best]?.name ?? "").font(.title3.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                                    Spacer()
                                    Button("More about \(best)", systemImage: "info.circle") { info = TeamRef(id: best) }
                                        .labelStyle(.iconOnly).font(.title2).buttonStyle(.borderless)
                                }
                                if let s = stats[best] { Text(summary(s)).font(.callout.weight(.semibold)) }
                                ForEach(notes(best).prefix(3), id: \.self) { note in
                                    Text(note).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                }
                                if available.count > 1 {
                                    Text("Then " + available.dropFirst().prefix(4).map(String.init).joined(separator: " · "))
                                        .font(.headline).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                        } else {
                            Text("Nobody left on the list.").foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Tap a team when it's picked or becomes a captain. Pull down to load picks from Nexus or TBA.")
                    }
                }

                Section {
                    ForEach(Array(store.db.picklist.enumerated()), id: \.element) { rank, team in
                        let isTaken = taken.contains(team)
                        if selecting {
                            HStack(spacing: 10) {
                                Button {
                                    if allianceOf[team] == nil { toggle(team, in: \.picked) }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        row(rank, team, stats[team], taken: isTaken, alliance: allianceOf[team])
                                        if !isTaken, let note = notes(team).first {
                                            Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(.leading, 48)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint(isTaken ? "Marks it available again" : "Marks it taken")
                                Button("More about \(team)", systemImage: "info.circle") { info = TeamRef(id: team) }
                                    .labelStyle(.iconOnly).font(.title3).buttonStyle(.borderless)
                            }
                        } else {
                            NavigationLink(value: team) {
                                row(rank, team, stats[team], taken: isTaken, alliance: allianceOf[team])
                            }
                            .swipeActions(edge: .trailing) {
                                Button(store.db.dnp.contains(team) ? "Undo DNP" : "DNP") { toggle(team, in: \.dnp) }.tint(.red)
                                Button(isTaken ? "Available" : "Taken") { toggle(team, in: \.picked) }.tint(.gray)
                            }
                            .swipeActions(edge: .leading) {
                                Button("Remove", systemImage: "trash") { removing = team }.tint(.red)
                            }
                        }
                    }
                    .onMove(perform: selecting ? nil : { store.db.picklist.move(fromOffsets: $0, toOffset: $1) })
                }
            }
            .confirmRemove($removing, store: store, event: event)
            .sheet(item: $info) { ref in
                NavigationStack {
                    TeamDetail(team: ref.id)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { info = nil } } }
                }
            }
            .sheet(isPresented: $weighting) {
                WeightedSort(stats: Array(stats.values)) { store.db.picklist = $0 }
            }
            .navigationTitle(selecting ? "Alliance selection" : "Picklist")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Int.self) { TeamDetail(team: $0) }
            .refreshable {
                guard !event.isEmpty else { return }
                let (info, _) = await Fetch.event(event, tbaKey: tbaKey, nexusKey: nexusKey, statbotics: false, into: store.db.info)
                store.db.info = info
            }
            .toolbar {
                if hSize != .compact {
                    ToolbarItem(placement: .principal) { modePicker.frame(width: 300) }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    HelpButton(title: "Picks", items: Help.picks)
                    if selecting {
                        Button("Clear taken", systemImage: "arrow.counterclockwise") { store.db.picked = [] }
                    } else {
                        Menu("Sort", systemImage: "arrow.up.arrow.down") {
                            Button("Weighted (pick your factors)…", systemImage: "slider.horizontal.3") { weighting = true }
                            Divider()
                            Button("By scouted points") { sortBy(\.pointsKey) }
                            Button("By EPA (Statbotics)") { sortBy(\.epa) }
                            Button("By live EPA") { sortBy(\.liveEPA) }
                            Button("By OPR (TBA)") { sortBy(\.opr) }
                            Button("By head-to-head") { sortBy(\.h2h) }
                        }
                        ShareLink(item: Slack.picklist(db: store.db, event: event, taken: taken)) { Label("Share to Slack", systemImage: "square.and.arrow.up") }
                        EditButton()
                    }
                }
            }
            .overlay {
                if store.db.picklist.isEmpty {
                    ContentUnavailableView("No teams yet", systemImage: "list.number",
                        description: Text("Pick your event in Data and every team shows up here. Tap Edit to drag them into order; swipe for DNP."))
                }
            }
            .onAppear {
                // New teams join the bottom; the order people dragged stays put.
                let missing = stats.values.sorted { $0.pointsKey > $1.pointsKey }.map(\.team).filter { !store.db.picklist.contains($0) }
                if !missing.isEmpty { store.db.picklist += missing }
            }
        }
    }

    private func row(_ rank: Int, _ team: Int, _ s: TeamStats?, taken: Bool, alliance: Int?) -> some View {
        HStack(spacing: 14) {
            Text("\(rank + 1)").font(.headline).monospacedDigit().foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: "\(team)").font(.title3.weight(.heavy)).strikethrough(taken).lineLimit(1).fixedSize()
                    if team == ourTeam { pill("US", .accentColor) }
                    if store.db.dnp.contains(team) { pill("DNP", .redAlliance) }
                    if let alliance { pill(hSize == .compact ? "A\(alliance)" : "Alliance \(alliance)", .gray) } else if taken { pill("Taken", .gray) }
                }
                Text(s?.name ?? "").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let s {
                HStack(spacing: 16) {
                    metric("pts", s.points)
                    if hSize != .compact { if s.liveEPA > 0 { metric("live", s.liveEPA) } else { metric("EPA", nz(s.epa)) } }
                    if hSize != .compact {
                        if s.h2h > 0 { metric("H2H", s.h2h.rounded()) }
                        metric("tower", s.tower)
                    }
                }
                RobustBadge(value: Int(s.robustness))
            }
        }
        .padding(.vertical, 4)
        .opacity(taken ? 0.35 : 1)
        .contentShape(Rectangle())
    }

    private var modePicker: some View {
        Picker("Mode", selection: $selecting.animation()) {
            Text("Rank").tag(false)
            Text("Alliance selection").tag(true)
        }
        .pickerStyle(.segmented)
    }

    /// One line of the numbers that matter in selection, for the best-available card.
    private func summary(_ s: TeamStats) -> String {
        let pit = store.pit(s.team)
        return [s.points.map { "\(f($0)) pts" }, s.liveEPA > 0 ? "live EPA \(f(s.liveEPA))" : s.epa > 0 ? "EPA \(f(s.epa))" : nil,
                s.autoFuel.map { "auto \(f($0))" }, s.tower.map { "tower \(f($0))" },
                pit.map { $0.maxClimb > 0 ? "climbs L\($0.maxClimb)" : "no climb" },
                s.robustness > 0 ? "robust \(Int(s.robustness))/5" : nil,
                s.died.flatMap { $0 > 0 ? "died \(Int($0 * 100))%" : nil }, s.matches > 0 ? "\(s.matches) scouted" : "not scouted"]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// What scouts wrote about a team at this event, newest first (match notes, weaknesses, breaks).
    private func notes(_ team: Int) -> [String] {
        store.db.matches.filter { $0.team == team && $0.event == event }
            .sorted { Fetch.order($0.type, $0.match) > Fetch.order($1.type, $1.match) }
            .compactMap { m in
                let said = [m.notes, m.weaknesses.isEmpty ? "" : "weakness: \(m.weaknesses)", m.breaks.isEmpty ? "" : "broke: \(m.breaks)"]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
                return said.isEmpty ? nil : "\(m.type == .qual ? "Q" : m.type == .playoff ? "P" : "Pr")\(m.match): \(said)"
            }
    }

    private func metric(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value.map { $0 >= 10 ? String(Int($0.rounded())) : String(format: "%.1f", $0) } ?? "–")
                .font(.headline).monospacedDigit().lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(minWidth: 44, alignment: .trailing)
    }

    private func sortBy(_ key: KeyPath<TeamStats, Double>) {
        store.db.picklist = store.db.stats(event: event).sorted { $0[keyPath: key] > $1[keyPath: key] }.map(\.team)
    }

    private func toggle(_ team: Int, in list: WritableKeyPath<Snapshot, [Int]>) {
        if let i = store.db[keyPath: list].firstIndex(of: team) {
            store.db[keyPath: list].remove(at: i)
        } else {
            store.db[keyPath: list].append(team)
        }
    }
}
