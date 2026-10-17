import SwiftUI

/// Objective scouting for one robot in one match. Laid out in two columns so a whole match fits
/// on an iPad without scrolling during play.
struct MatchForm: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("scout") private var scout = ""
    @AppStorage("event") private var event = ""
    @AppStorage("station") private var station = 0
    @State private var r: MatchRecord
    @State private var shared: MatchRecord?
    private let editing: Bool

    init(editing record: MatchRecord? = nil) {
        _r = State(initialValue: record ?? MatchRecord())
        editing = record != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GroupBox {
                    VStack(spacing: 12) {
                        HStack(spacing: 16) {
                            Picker("Type", selection: $r.type) {
                                ForEach(MatchType.allCases, id: \.self) { Text($0.rawValue) }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 260)
                            if editing {
                                Picker("Alliance", selection: $r.alliance) {
                                    ForEach(Alliance.allCases, id: \.self) { Text($0.rawValue) }
                                }
                                .pickerStyle(.segmented)
                            } else {
                                // Your seat for the event; the team fills in from the downloaded schedule.
                                Picker("Station", selection: $station) {
                                    ForEach(0..<6, id: \.self) { Text($0 < 3 ? "Red \($0 + 1)" : "Blue \($0 - 2)").tag($0) }
                                }
                                .pickerStyle(.segmented)
                                .background(RoundedRectangle(cornerRadius: 9).fill((station < 3 ? Color.red : .blue).opacity(0.25)))
                            }
                        }
                        HStack(spacing: 16) {
                            NumberField(title: "Match #", value: $r.match).textFieldStyle(.roundedBorder).frame(width: 100)
                            NumberField(title: "Team #", value: $r.team).textFieldStyle(.roundedBorder).frame(width: 100)
                            Text(store.db.info?.names[String(r.team)] ?? "").font(.headline).lineLimit(1)
                            Spacer()
                            if let queuing = store.db.info?.nowQueuing, !queuing.isEmpty {
                                Label("Now queuing: \(queuing)", systemImage: "clock").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        box("Auto · 20 s") {
                            Picker("Start", selection: $r.startPos) {
                                ForEach(StartPos.allCases, id: \.self) { Text($0.rawValue) }
                            }
                            .pickerStyle(.segmented)
                            Counter(title: "Fuel scored", value: $r.autoFuel, steps: [1, 5])
                            Toggle("Climbed Level 1 (15 pts)", isOn: $r.autoClimb)
                            Toggle("Drove to the neutral zone", isOn: $r.autoNeutral)
                        }
                        box("End game · tower") {
                            Picker("Climb", selection: $r.climb) {
                                Text("None").tag(0)
                                Text("L1 · 10").tag(1)
                                Text("L2 · 20").tag(2)
                                Text("L3 · 30").tag(3)
                            }
                            .pickerStyle(.segmented)
                        }
                        box("Problems") {
                            Toggle("Died or never moved", isOn: $r.died)
                            Toggle("Tipped over", isOn: $r.tipped)
                        }
                    }
                    VStack(spacing: 16) {
                        box("Teleop · count fuel into the active hub only") {
                            Counter(title: "Fuel scored", value: $r.teleFuel)
                            Counter(title: "Passes (volleys)", value: $r.passes, steps: [1])
                            Picker("Role", selection: $r.role) {
                                ForEach(Role.allCases, id: \.self) { Text($0.rawValue) }
                            }
                            .pickerStyle(.segmented)
                            Toggle("Shoots while moving", isOn: $r.shootsOnMove)
                        }
                        box("Ratings · tap again to clear") {
                            Rating(title: "Accuracy", value: $r.accuracy, caption: "1 misses most · 5 rarely misses")
                            Rating(title: "Driver", value: $r.driver, caption: "agility, awareness")
                            Rating(title: "Defense", value: $r.defense, caption: "blank if they didn't defend")
                        }
                    }
                }

                box("Notes") {
                    TextField("Playstyle, weaknesses, breaks, defense…", text: $r.notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Button(action: save) {
                    Text(editing ? "Save changes" : "Save match").font(.headline).frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(r.team == 0 || r.match == 0)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(editing ? Text(verbatim: "Edit match \(r.match) · \(r.team)") : Text("Match scouting"))
        .toolbar {
            if !editing {
                Text("\(scout.isEmpty ? "No name set" : scout) · \(event.isEmpty ? "no event" : event)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: autofill)
        .onChange(of: r.match) { autofill() }
        .onChange(of: r.type) { autofill() }
        .onChange(of: station) { autofill() }
        .sheet(item: $shared) { m in
            QRSheet(title: "Match \(m.match) · \(m.team)", snapshot: Snapshot(matches: [m]))
        }
    }

    private func box<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 12) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func save() {
        if editing {
            store.save(r)
            dismiss()
            return
        }
        r.event = event
        r.scout = scout
        r.alliance = station < 3 ? .red : .blue
        store.save(r)
        shared = store.db.matches.first { $0.id == r.id }
        r = MatchRecord(type: r.type, match: r.match + 1)
    }

    /// Fills the team from the schedule for this match and station. Typing over it is the override.
    private func autofill() {
        guard !editing,
              let m = store.db.info?.schedule.first(where: { $0.type == r.type && $0.match == r.match }) else { return }
        let teams = m.red + m.blue
        if station < teams.count, teams[station] > 0 { r.team = teams[station] }
    }
}
