import SwiftUI

/// Head-to-head scouting, after 1678's OverRate: after each match, tap an alliance's robots from
/// best to worst. Every ordering becomes "A beat B" pairs, and those build an Elo rating that sorts
/// teams on what stand strategists actually saw.
struct CompareView: View {
    @Environment(Store.self) private var store
    @AppStorage("event") private var event = ""
    @AppStorage("scout") private var scout = ""
    @AppStorage("compareRed") private var red = true
    @State private var type = MatchType.qual
    @State private var match = 0
    @State private var teams = [0, 0, 0]
    @State private var order: [Int] = []          // indices into teams, best first
    @State private var shared: Comparison?
    @State private var confirmDeleteAll = false
    @State private var typed: [Bool: [Int]] = [:]   // robots typed per alliance, so Red and Blue stay separate
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        let stats = store.db.stats(event: event)
        let names = store.db.info?.names ?? [:]
        let leaders = stats.filter { $0.h2h > 0 }.sorted { $0.h2h > $1.h2h }
        let ready = order.count == 3 && teams.allSatisfy { $0 > 0 }
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        (hSize == .compact ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))) {
                            Choice(options: MatchType.allCases.map { ($0, $0.rawValue) }, selection: $type, base: .surface)
                            Choice(options: [(true, "Red"), (false, "Blue")], selection: $red, color: .alliance(red), base: .surface)
                                .frame(maxWidth: hSize == .compact ? .infinity : 220)
                        }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("MATCH").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.secondary)
                                NumberField(title: "–", value: $match)
                                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                                    .padding(.horizontal, 12)
                                    .frame(width: 110, height: 52)
                                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            ForEach(0..<3, id: \.self) { i in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("ROBOT \(i + 1)").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.secondary)
                                    NumberField(title: "–", value: $teams[i])
                                        .font(.title3.weight(.bold))
                                        .padding(.horizontal, 10)
                                        .frame(height: 52)
                                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }
                    .padding(18)
                    .background(LinearGradient(colors: [Color.fuel.opacity(0.35), Color.fuel.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Who helped their alliance most?", systemImage: "arrow.up.arrow.down", color: .alliance(red),
                                      detail: order.isEmpty ? "tap best first" : "tap a robot to start over")
                        HStack(spacing: 12) {
                            ForEach(0..<3, id: \.self) { i in robotCard(i, name: names[String(teams[i])]) }
                        }
                        Button(action: save) {
                            Label("Save comparison", systemImage: "checkmark.circle.fill")
                                .font(.title3.weight(.heavy))
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .foregroundStyle(Color.navy)
                                .background(Color.fuel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(Pressable())
                        .disabled(!ready)
                        .opacity(ready ? 1 : 0.45)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Head-to-head leaders", systemImage: "trophy.fill", color: .endPhase,
                                      detail: "\(store.db.rankings.filter { $0.event == event }.count) comparisons")
                        if leaders.isEmpty {
                            Text("Ratings show up after the first comparison.").foregroundStyle(.secondary)
                        }
                        ForEach(Array(leaders.prefix(15).enumerated()), id: \.element.team) { i, s in
                            HStack(spacing: 12) {
                                Text("\(i + 1)").font(.headline).monospacedDigit().foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                                Text(verbatim: "\(s.team)").font(.headline)
                                Text(s.name).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Text(verbatim: String(Int(s.h2h.rounded()))).font(.headline).monospacedDigit()
                                    .foregroundStyle(s.h2h >= 1500 ? Color.telePhase : Color.redAlliance)
                            }
                        }
                    }
                    .card()

                    let mine = store.db.rankings.filter { $0.event == event }
                        .sorted { Fetch.order($0.type, $0.match) > Fetch.order($1.type, $1.match) }
                    if !mine.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Comparisons", systemImage: "list.bullet", color: .gray, detail: "tap the trash to delete one")
                            ForEach(mine) { c in
                                HStack(spacing: 12) {
                                    Text("\(c.type.rawValue) \(c.match)").font(.headline).frame(width: 110, alignment: .leading)
                                    Text(c.order.map(String.init).joined(separator: "  ›  ")).monospacedDigit()
                                    Spacer()
                                    Text(c.scout).font(.caption).foregroundStyle(.secondary)
                                    Button("Delete comparison", systemImage: "trash", role: .destructive) {
                                        withAnimation { store.db.rankings.removeAll { $0.id == c.id } }
                                    }
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(Color.redAlliance)
                                }
                                .padding(.vertical, 2)
                            }
                            Button("Delete all for this event", systemImage: "trash", role: .destructive) { confirmDeleteAll = true }
                                .padding(.top, 6)
                        }
                        .card()
                    }
                }
                .padding()
            }
            .background(Color.page)
            .confirmationDialog("Delete all head-to-head data for \(event.isEmpty ? "this event" : event)?",
                                isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete \(store.db.rankings.filter { $0.event == event }.count) comparisons", role: .destructive) {
                    store.db.rankings.removeAll { $0.event == event }
                }
            } message: {
                Text("Ratings reset. Other events and other iPads keep theirs.")
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Head-to-head")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { HelpButton(title: "Head-to-head", items: Help.h2h) }
            .onChange(of: match) { typed = [:]; autofill() }
            .onChange(of: type) { typed = [:]; autofill() }
            .onChange(of: red) { old, new in
                typed[old] = teams
                teams = typed[new] ?? [0, 0, 0]
                autofill()
            }
            .onChange(of: teams) { order = [] }
            .sheet(item: $shared) { c in
                QRSheet(title: "Compare · match \(c.match)", snapshot: Snapshot(rankings: [c]))
            }
        }
    }

    private func robotCard(_ i: Int, name: String?) -> some View {
        let place = order.firstIndex(of: i)
        return Button {
            if place != nil { order = [] } else {
                order.append(i)
                if order.count == 2, let last = (0..<3).first(where: { !order.contains($0) }) { order.append(last) }
            }
        } label: {
            VStack(spacing: 6) {
                Text(place.map { ["1st", "2nd", "3rd"][$0] } ?? " ")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(place == nil ? Color.secondary : Color.white)
                    .frame(width: 56, height: 30)
                    .background(place == nil ? Color.clear : [Color.fuel, Color.gray, Color.brown][place!], in: Capsule())
                Text(teams[i] == 0 ? "–" : "\(teams[i])").font(.system(size: 40, weight: .heavy, design: .rounded))
                Text(name ?? " ").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(place == nil ? Color.well : Color.alliance(red).opacity(0.15), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(place == 0 ? Color.alliance(red) : .clear, lineWidth: 3))
        }
        .buttonStyle(Pressable())
        .disabled(teams[i] == 0)
        .accessibilityLabel("Team \(teams[i])\(place.map { ", ranked \($0 + 1)" } ?? "")")
    }

    private func save() {
        let c = Comparison(event: event, scout: scout, type: type, match: match, order: order.map { teams[$0] })
        store.save(c)
        shared = store.db.rankings.first { $0.id == c.id }
        order = []
        match += 1
    }

    /// Robots from the schedule for this match and alliance; typing over them is the override.
    private func autofill() {
        order = []
        guard let m = store.db.info?.schedule.first(where: { $0.type == type && $0.match == match }) else { return }
        let alliance = red ? m.red : m.blue
        if alliance.count == 3 { teams = alliance }
    }
}
