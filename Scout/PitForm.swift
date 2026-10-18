import SwiftUI

/// Every team at the event as a tile, so the pit scout can see who's left (the readme's goal:
/// pit scout everyone by the end of load-in day).
struct PitList: View {
    @Environment(Store.self) private var store
    @AppStorage("event") private var event = ""
    @State private var shared: PitRecord?
    @State private var manual = false
    @State private var removing: Int?
    @AppStorage("pitTodoOnly") private var todoOnly = false

    var body: some View {
        let info = store.db.info?.key == event ? store.db.info : nil
        let teams = Set(info?.names.keys.compactMap { Int($0) } ?? [])
            .union(store.db.pits.map(\.team))
            .union(store.db.matches.filter { $0.event == event }.map(\.team))
            .subtracting(store.db.removed[event] ?? [])
            .sorted()
        let done = teams.filter { store.pit($0) != nil }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !teams.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(done) of \(teams.count)").font(.title.weight(.heavy)).monospacedDigit()
                            Text("pit scouted").foregroundStyle(.secondary)
                            Spacer()
                        }
                        ProgressView(value: Double(done), total: Double(max(teams.count, 1))).tint(.green)
                    }
                    .card()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 12)], spacing: 12) {
                    ForEach(teams.filter { !todoOnly || store.pit($0) == nil }, id: \.self) { team in
                        NavigationLink(value: team) { tile(team, info: info) }
                            .buttonStyle(Pressable())
                            .contextMenu {
                                if store.pit(team) != nil {
                                    Button("Mark as not scouted", systemImage: "arrow.uturn.backward") {
                                        store.db.pits.removeAll { $0.team == team }
                                    }
                                }
                                Button("Remove team from event", systemImage: "trash", role: .destructive) { removing = team }
                            }
                    }
                }
            }
            .padding()
        }
        .background(Color.page)
        .overlay {
            if teams.isEmpty {
                ContentUnavailableView("No teams yet", systemImage: "wrench.and.screwdriver",
                    description: Text("Pick your event in Data to list every team, or add one by number with +."))
            }
        }
        .navigationTitle("Pit scouting")
        .navigationDestination(for: Int.self) { team in
            PitForm(team: team) { shared = $0 }
        }
        .navigationDestination(isPresented: $manual) {
            PitForm(team: 0) { shared = $0 }
        }
        .toolbar {
            HelpButton(title: "Pit scouting", items: Help.pit)
            Toggle(isOn: $todoOnly) { Label("To do only", systemImage: "line.3.horizontal.decrease.circle") }
                .toggleStyle(.button)
            Button("Add team", systemImage: "plus") { manual = true }
        }
        .confirmRemove($removing, store: store, event: event)
        .sheet(item: $shared) { pit in
            QRSheet(title: "Pit · \(pit.team)", snapshot: Snapshot(pits: [pit]))
        }
    }

    private func tile(_ team: Int, info: EventData?) -> some View {
        let pit = store.pit(team)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: "\(team)").font(.title2.weight(.heavy)).foregroundStyle(.primary)
                Spacer()
                if let pit { RobustBadge(value: pit.robustness) }
                else { Text("To do").font(.caption.weight(.bold)).foregroundStyle(.secondary) }
            }
            Text(info?.names[String(team)] ?? " ").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 6) {
                if let address = info?.pits[String(team)] {
                    Label(address, systemImage: "mappin").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Spacer()
                if pit != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        }
        .padding(14)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(pit == nil ? Color.clear : Color.green.opacity(0.5), lineWidth: 2))
        .accessibilityElement(children: .combine)
    }
}

/// Pit scouting for one team. Robustness follows the 1678 District Event readme rubric; the rest is
/// what other teams asked in REBUILT pits (Viper, VScouter, 247): ask what you can't see on the
/// field, and have them show you instead of just telling you.
struct PitForm: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var p: PitRecord
    @State private var loaded = false
    @State private var confirmUnmark = false
    private let pickTeam: Bool
    private let onSave: (PitRecord) -> Void

    init(team: Int, onSave: @escaping (PitRecord) -> Void) {
        _p = State(initialValue: PitRecord(team: team))
        pickTeam = team == 0
        self.onSave = onSave
    }

    static let rubric = [
        1: ("I expect this to fail on the field. Likely DNP. Bad in an unfixable way.",
            "Big loads on unsupported hex shafts, undersized structure, high-load live hex axles, no cross bracing.",
            "Rat's nest of wires, wires in motion paths or too short, no strain relief, no ferrules, poor connections."),
        2: ("Looks unreliable. Some reservations about picking. Bad in a potentially fixable way.",
            "Structure moves under load (could break in a big hit), undersized, missing, or loose fasteners, untensioned chains.",
            "Loose wires in risky areas, long unsecured wires, inconsistent connectors, no strain relief."),
        3: ("A normal robot. Can likely play elims with no incap.",
            "Some small cantilevered loads, supported structure, minimal superstructure wiggle, long chains tensioned.",
            "Routes thought out but untidy, zip ties hold things roughly in place, good practices with poor attention to detail."),
        4: ("Sturdy and well built. No work necessary.",
            "Sturdy structure, right-sized motion parts, hex shafts short or low-load, long spans are spline or large tube, chains tensioned.",
            "Tidy wiring with no obvious issues."),
        5: ("Appears indestructible. We could learn from them.",
            "Short load paths, large dead-axle pivots, rigid structure, oversized motion parts, tensioned belts and chains.",
            "Short secured wire runs, protected critical parts, soldered CAN, ferrules, hot-glued ethernet."),
    ]

    var body: some View {
        let name = store.db.info?.names[String(p.team)]
        Form {
            if pickTeam {
                Section {
                    NumberField(title: "Team number", value: $p.team).font(.title2.bold())
                        .onChange(of: p.team) { _, team in load(team) }
                }
            }

            Section {
                Picker("Robustness", selection: $p.robustness) {
                    Text("–").tag(0)
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                if let level = Self.rubric[p.robustness] {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { RobustBadge(value: p.robustness); Text(level.0).font(.headline) }
                        Text("Mechanical: ").bold() + Text(level.1)
                        Text("Electrical: ").bold() + Text(level.2)
                    }
                    .font(.callout)
                }
            } header: {
                Text("Robustness")
            } footer: {
                Text("A mechanically experienced member rates build quality, per the 1678 readme.")
            }

            Section("Drivetrain") {
                Picker("Drivetrain", selection: $p.drivetrain) {
                    ForEach(["Swerve", "Tank", "Mecanum", "Other"], id: \.self) { Text($0) }
                }
                Toggle("Fits under the trench", isOn: $p.trench)
                Toggle("Drives over the bump", isOn: $p.bump)
            }

            Section {
                Toggle("From the floor", isOn: $p.floorIntake)
                Toggle("From the outpost (human player)", isOn: $p.outpostIntake)
                Toggle("From the depot", isOn: $p.depotIntake)
                number("Fuel it holds", $p.hopper)
            } header: {
                Text("Intake")
            } footer: {
                Text("Ask them to show you: count fuel into the hopper rather than taking their number.")
            }

            Section {
                Picker("Range", selection: $p.range) {
                    Text("Not sure").tag(0)
                    Text("At the hub").tag(1)
                    Text("Anywhere in our zone").tag(2)
                    Text("From the neutral zone").tag(3)
                }
                number("Shot rate (fuel / second)", $p.shotRate)
                Toggle("Turret", isOn: $p.turret)
                Toggle("Shoots while moving", isOn: $p.shootsOnMove)
                Toggle("Passes fuel from midfield back to its own side", isOn: $p.canPass)
            } header: {
                Text("Shooting")
            } footer: {
                Text("Claimed numbers are compared with scouted ones on the team page.")
            }

            Section("Tower") {
                Picker("Highest climb", selection: $p.maxClimb) {
                    Text("None").tag(0)
                    ForEach(1...3, id: \.self) { Text("Level \($0)").tag($0) }
                }
                number("Seconds to climb", $p.climbSeconds)
                Toggle("Climbs on the side (leaves room for partners)", isOn: $p.sideClimb)
                Toggle("Climbs Level 1 in auto", isOn: $p.autoClimb)
            }

            Section("Auto") {
                number("Autos they can run", $p.autoCount)
                number("Fuel in their best auto", $p.autoFuelClaim)
                Toggle("Goes to the neutral zone in auto", isOn: $p.autoNeutral)
                Picker("How often their auto works", selection: $p.autoConsistency) {
                    ForEach(PitRecord.autoConsistencyLabels.indices, id: \.self) { Text(PitRecord.autoConsistencyLabels[$0]).tag($0) }
                }
            }

            Section("Team") {
                Picker("Role they want", selection: $p.role) {
                    ForEach(Role.allCases, id: \.self) { Text($0.rawValue) }
                }
                Picker("Driver experience", selection: $p.driverYears) {
                    Text("Not sure").tag(0)
                    Text("1st year").tag(1)
                    Text("2nd year").tag(2)
                    Text("3+ years").tag(3)
                }
            }

            Section("Notes") {
                TextField("What's broken or worrying them?", text: $p.worries, axis: .vertical)
                    .lineLimit(2...6)
                TextField("Architecture, autos, anything odd…", text: $p.notes, axis: .vertical)
                    .lineLimit(3...8)
            }

            Section {
                Button {
                    store.save(p)
                    if let saved = store.pit(p.team) { onSave(saved) }
                    dismiss()
                } label: {
                    Label("Save pit record", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(Color.navy)
                        .background(Color.fuel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(Pressable())
                .disabled(p.team == 0)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if store.pit(p.team) != nil {
                Section {
                    Button("Mark as not scouted", systemImage: "arrow.uturn.backward", role: .destructive) { confirmUnmark = true }
                        .frame(maxWidth: .infinity)
                } footer: {
                    Text("Deletes this team's pit answers on this device so it shows as To do again.")
                }
            }
        }
        .confirmationDialog("Mark \(String(p.team)) as not scouted?", isPresented: $confirmUnmark, titleVisibility: .visible) {
            Button("Delete pit answers", role: .destructive) {
                store.db.pits.removeAll { $0.team == p.team }
                dismiss()
            }
        } message: {
            Text("Its pit answers are deleted from this device.")
        }
        .navigationTitle(p.team == 0 ? Text("New pit record") : Text(verbatim: "\(p.team)\(name.map { " · \($0)" } ?? "")"))
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if !loaded { load(p.team); loaded = true }
        }
    }

    private func number(_ title: String, _ value: Binding<Int>) -> some View {
        LabeledContent(title) {
            NumberField(title: "–", value: value).multilineTextAlignment(.trailing)
        }
    }

    private func load(_ team: Int) {
        p = store.pit(team) ?? PitRecord(team: team)
    }
}
