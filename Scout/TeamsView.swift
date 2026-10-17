import SwiftUI

private func f(_ x: Double) -> String { x == 0 ? "–" : String(format: "%.1f", x) }

/// Every team at the current event, averaged. Tap a column header to sort.
struct TeamsView: View {
    @Environment(Store.self) private var store
    @AppStorage("event") private var event = ""
    @State private var sort = [KeyPathComparator(\TeamStats.points, order: .reverse)]
    @State private var search = ""

    var body: some View {
        let rows = store.db.stats(event: event)
            .filter { search.isEmpty || String($0.team).hasPrefix(search) }
            .sorted(using: sort)
        NavigationStack {
            Table(rows, sortOrder: $sort) {
                Group {
                    TableColumn("Team", value: \.team) { (s: TeamStats) in
                        NavigationLink(value: s.team) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(verbatim: "\(s.team)").bold() + Text("  \(s.matches)m").font(.caption).foregroundStyle(.secondary)
                                if !s.name.isEmpty { Text(s.name).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }
                        }
                    }
                    .width(min: 120)
                    TableColumn("Rank", value: \.rank) { (s: TeamStats) in Text(s.rank == 0 ? "–" : String(s.rank)) }
                    TableColumn("OPR", value: \.opr) { (s: TeamStats) in Text(f(s.opr)) }
                    TableColumn("Pts", value: \.points) { (s: TeamStats) in Text(f(s.points)).bold() }
                        .width(min: 56)
                }
                Group {
                    TableColumn("Auto", value: \.autoFuel) { (s: TeamStats) in Text(f(s.autoFuel)) }
                    TableColumn("Tele", value: \.teleFuel) { (s: TeamStats) in Text(f(s.teleFuel)) }
                    TableColumn("Tower", value: \.tower) { (s: TeamStats) in Text(f(s.tower)) }
                    TableColumn("Pass", value: \.passes) { (s: TeamStats) in Text(f(s.passes)) }
                }
                Group {
                    TableColumn("Acc", value: \.accuracy) { (s: TeamStats) in Text(f(s.accuracy)) }
                    TableColumn("Drive", value: \.driver) { (s: TeamStats) in Text(f(s.driver)) }
                    TableColumn("Def", value: \.defense) { (s: TeamStats) in Text(f(s.defense)) }
                    TableColumn("Robust", value: \.robustness) { (s: TeamStats) in
                        Text(s.robustness == 0 ? "–" : String(Int(s.robustness)))
                            .foregroundStyle(s.robustness == 0 ? Color.secondary : s.robustness <= 2 ? Color.red : Color.primary)
                    }
                    .width(min: 64)
                }
            }
            .navigationTitle(event.isEmpty ? "Teams" : "Teams · \(event)")
            .navigationDestination(for: Int.self) { TeamDetail(team: $0) }
            .searchable(text: $search, prompt: "Team number")
            .overlay {
                if rows.isEmpty {
                    ContentUnavailableView("No data yet", systemImage: "tablecells",
                        description: Text("Scout a match, or scan your scouts' QR codes in Data."))
                }
            }
        }
    }
}

struct TeamDetail: View {
    let team: Int
    @Environment(Store.self) private var store

    var body: some View {
        let matches = store.db.matches.filter { $0.team == team }.sorted { ($0.event, $0.match) < ($1.event, $1.match) }
        let info = store.db.info
        let scheduled = info?.schedule.filter { ($0.red + $0.blue).contains(team) } ?? []
        List {
            if let info, info.names[String(team)] != nil || info.pits[String(team)] != nil {
                Section("Event") {
                    if let name = info.names[String(team)] { LabeledContent("Name", value: name) }
                    if let rank = info.rank[String(team)] { LabeledContent("Rank", value: "\(rank)") }
                    if let opr = info.opr[String(team)] { LabeledContent("OPR", value: f(opr)) }
                    if let pit = info.pits[String(team)] { LabeledContent("Pit", value: pit) }
                    if !scheduled.isEmpty {
                        LabeledContent("Matches", value: scheduled.map { "\($0.label) \($0.red.contains(team) ? "red" : "blue")" }.joined(separator: " · "))
                    }
                }
            }
            if let photo = Photos.load(team) {
                Section { Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 320) }
            }
            if let p = store.pit(team) {
                Section("Pit") {
                    LabeledContent("Robustness", value: p.robustness == 0 ? "–" : "\(p.robustness) / 5")
                    LabeledContent("Drivetrain", value: p.drivetrain)
                    LabeledContent("Holds", value: "\(p.hopper) fuel")
                    LabeledContent("Trench / bump", value: "\(p.trench ? "under trench" : "no trench") · \(p.bump ? "over bump" : "no bump")")
                    LabeledContent("Climb", value: p.maxClimb == 0 ? "none" : "Level \(p.maxClimb)\(p.autoClimb ? ", in auto too" : "")")
                    LabeledContent("Shoots while moving", value: p.shootsOnMove ? "yes" : "no")
                    if !p.notes.isEmpty { Text(p.notes) }
                }
            }
            Section("Matches") {
                ForEach(matches) { m in
                    NavigationLink { MatchForm(editing: m) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(m.type.rawValue) \(m.match)").bold()
                                Text(m.alliance.rawValue).foregroundStyle(m.alliance == .red ? .red : .blue)
                                if m.died { Text("DIED").font(.caption.bold()).foregroundStyle(.red) }
                                Spacer()
                                Text("\(m.points) pts").monospacedDigit().bold()
                            }
                            Text("Auto \(m.autoFuel)\(m.autoClimb ? " + L1" : "") · tele \(m.teleFuel) · \(m.passes) passes · \(m.climb == 0 ? "no climb" : "L\(m.climb)") · \(m.role.rawValue)")
                                .font(.callout).foregroundStyle(.secondary)
                            if !m.notes.isEmpty { Text(m.notes).font(.callout) }
                            Text("\(m.scout.isEmpty ? "unknown scout" : m.scout) · \(m.event)").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { store.db.matches.removeAll { $0.id == m.id } }
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: "Team \(team)"))
        .toolbar {
            Link("The Blue Alliance", destination: URL(string: "https://www.thebluealliance.com/team/\(team)")!)
        }
    }
}

/// The ordered picklist, as in the readme's draft night: drag to sort by pickability, mark DNPs,
/// and cross teams off during alliance selection.
struct PicklistView: View {
    @Environment(Store.self) private var store
    @AppStorage("event") private var event = ""

    var body: some View {
        let stats = Dictionary(uniqueKeysWithValues: store.db.stats(event: event).map { ($0.team, $0) })
        NavigationStack {
            List {
                ForEach(Array(store.db.picklist.enumerated()), id: \.element) { rank, team in
                    let dnp = store.db.dnp.contains(team)
                    let picked = store.db.picked.contains(team)
                    NavigationLink(value: team) {
                        HStack(spacing: 14) {
                            Text("\(rank + 1)").font(.headline).monospacedDigit().foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
                            Text(verbatim: "\(team)").font(.title3.bold()).strikethrough(picked)
                            Text(stats[team]?.name ?? "").foregroundStyle(.secondary).lineLimit(1)
                            if dnp { Text("DNP").font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(.red, in: Capsule()).foregroundStyle(.white) }
                            Spacer()
                            if let s = stats[team] {
                                Text("\(f(s.points)) pts · tower \(f(s.tower)) · robust \(s.robustness == 0 ? "–" : "\(Int(s.robustness))")")
                                    .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .opacity(picked ? 0.4 : 1)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(dnp ? "Undo DNP" : "DNP") { toggle(team, in: \.dnp) }.tint(.red)
                        Button(picked ? "Unpick" : "Picked") { toggle(team, in: \.picked) }.tint(.gray)
                    }
                }
                .onMove { store.db.picklist.move(fromOffsets: $0, toOffset: $1) }
            }
            .navigationTitle("Picklist")
            .navigationDestination(for: Int.self) { TeamDetail(team: $0) }
            .toolbar {
                ToolbarItemGroup {
                    Button("Sort by points") { store.db.picklist = store.db.stats(event: event).map(\.team) }
                    ShareLink(item: shareText(stats)) { Label("Share", systemImage: "square.and.arrow.up") }
                    EditButton()
                }
            }
            .overlay {
                if store.db.picklist.isEmpty {
                    ContentUnavailableView("No teams yet", systemImage: "list.number",
                        description: Text("Teams show up here once they're scouted. Tap Edit to drag them into order, and swipe a team to mark it DNP or picked."))
                }
            }
            .onAppear {
                // New teams join the bottom of the list; the order people dragged stays put.
                let missing = stats.values.sorted { $0.points > $1.points }.map(\.team).filter { !store.db.picklist.contains($0) }
                if !missing.isEmpty { store.db.picklist += missing }
            }
        }
    }

    private func toggle(_ team: Int, in list: WritableKeyPath<Snapshot, [Int]>) {
        if let i = store.db[keyPath: list].firstIndex(of: team) {
            store.db[keyPath: list].remove(at: i)
        } else {
            store.db[keyPath: list].append(team)
        }
    }

    private func shareText(_ stats: [Int: TeamStats]) -> String {
        let lines = store.db.picklist.enumerated().map { rank, team in
            var line = "\(rank + 1). \(team)"
            if let s = stats[team] { line += " (\(f(s.points)) pts)" }
            if store.db.picked.contains(team) { line += " PICKED" }
            if store.db.dnp.contains(team) { line += " DNP" }
            return line
        }
        return (["Picklist\(event.isEmpty ? "" : " · \(event)")"] + lines).joined(separator: "\n")
    }
}
