import SwiftUI

/// Objective scouting for one match: one robot, or a whole alliance at once (switch robots with the
/// big buttons; the shot map shows all three). Two columns so a match fits on an iPad, each phase in
/// its own color.
struct MatchForm: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize
    private var compact: Bool { hSize == .compact }   // iPhone: one column
    @AppStorage("scout") private var scout = ""
    @AppStorage("event") private var event = ""
    @AppStorage("station") private var station = 0
    @AppStorage("tbaKey") private var tbaKey = ""
    @AppStorage("eventName") private var eventName = ""
    @AppStorage("matchType") private var lastType = MatchType.qual
    @AppStorage("wholeAlliance") private var wholeAlliance = false
    @State private var crew: [MatchRecord]      // one robot, or the alliance's three
    @State private var current = 0              // which robot the form is editing
    @State private var shared: [MatchRecord] = []
    @State private var otherName: String?       // TBA name for a team that isn't at this event
    @State private var confirmClear = false
    @State private var seats: [Int: MatchRecord] = [:]  // one-robot mode: each seat's own record this match
    private let editing: Bool

    /// Whole-match robots: index 0-2 are Red 1-3, 3-5 are Blue 1-3. Each has its own dot color and label.
    static let robotColors: [Color] = [.red, .orange, .pink, .blue, .cyan, .indigo]
    static func seatName(_ i: Int) -> String { "\(i < 3 ? "R" : "B")\(i % 3 + 1)" }

    init(editing record: MatchRecord? = nil) {
        _crew = State(initialValue: [record ?? MatchRecord()])
        editing = record != nil
    }

    /// The robot being edited.
    private var r: MatchRecord {
        get { crew[min(current, crew.count - 1)] }
        nonmutating set { crew[min(current, crew.count - 1)] = newValue }
    }
    private var rb: Binding<MatchRecord> { $crew[min(current, crew.count - 1)] }
    private var multi: Bool { crew.count > 1 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if multi { switcher }

                if r.type == .playoff {
                    playoffForm
                } else {
                    columns {
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 14) {
                                SectionHeader(title: "Auto", systemImage: "timer", color: .autoPhase, detail: "20 s") {
                                    edit { $0.startPos = nil; $0.autoFuel = nil; $0.autoClimb = false; $0.autoNeutral = false }
                                }
                                Choice(options: [(nil, "–")] + StartPos.allCases.map { (Optional($0), $0.rawValue) }, selection: rb.startPos, color: .autoPhase)
                                Counter(title: "Fuel scored", value: rb.autoFuel, steps: [1, 5], color: .autoPhase)
                                HStack(spacing: 8) {
                                    Chip(title: "Climbed L1 · 15", systemImage: "arrow.up.to.line", isOn: rb.autoClimb, color: .autoPhase)
                                    Chip(title: "Neutral zone", systemImage: "arrow.right.circle", isOn: rb.autoNeutral, color: .autoPhase)
                                }
                            }
                            .card()

                            VStack(alignment: .leading, spacing: 14) {
                                SectionHeader(title: "End game", systemImage: "flag.checkered", color: .endPhase) {
                                    edit { $0.climb = nil }
                                }
                                Choice(options: towerOptions(points: true), selection: rb.climb, color: .endPhase)
                            }
                            .card()

                            VStack(alignment: .leading, spacing: 14) {
                                SectionHeader(title: "Problems", systemImage: "exclamationmark.triangle.fill", color: .redAlliance) {
                                    edit { $0.died = false; $0.tipped = false; $0.eStopped = false; $0.aStopped = false; $0.noShoot = false }
                                }
                                problemChips
                            }
                            .card()
                        }

                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 14) {
                                SectionHeader(title: "Teleop", systemImage: "gamecontroller.fill", color: .telePhase, detail: "active hub") {
                                    edit { $0.teleFuel = nil; $0.passes = nil; $0.role = nil; $0.shootsOnMove = false; $0.shots = [] }
                                }
                                Counter(title: "Fuel scored", value: rb.teleFuel, color: .telePhase)
                                Counter(title: "Passes (volleys)", value: rb.passes, steps: [1], color: .telePhase)
                                Choice(options: roleOptions, selection: rb.role, color: .telePhase)
                                Chip(title: "Shoots while moving", systemImage: "figure.run", isOn: rb.shootsOnMove, color: .telePhase)
                                shotMap
                            }
                            .card()

                            VStack(alignment: .leading, spacing: 14) {
                                SectionHeader(title: "Ratings", systemImage: "star.fill", color: .accentColor) {
                                    edit { $0.accuracy = 0; $0.driver = 0; $0.defense = 0 }
                                }
                                Rating(title: "Accuracy", value: rb.accuracy, caption: "5 rarely misses")
                                Rating(title: "Driver", value: rb.driver, caption: "agility, awareness")
                                Rating(title: "Defense", value: rb.defense, caption: "blank if they didn't")
                            }
                            .card()
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Notes", systemImage: "text.bubble.fill", color: .gray) { edit { $0.notes = "" } }
                        TextField("Playstyle, weaknesses, breaks, defense…", text: rb.notes, axis: .vertical)
                            .lineLimit(3...6)
                    }
                    .card()
                }

                Button(action: save) {
                    Label(editing ? "Save changes" : multi ? "Save \(toSave.count) robot\(toSave.count == 1 ? "" : "s")" : "Save match",
                          systemImage: "checkmark.circle.fill")
                        .font(.title3.weight(.heavy))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .foregroundStyle(Color.navy)
                        .background(Color.fuel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(Pressable())
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.45)

                Button(multi ? "Clear \(Self.seatName(current))'s answers" : "Clear this robot's answers", systemImage: "eraser", role: .destructive) {
                    confirmClear = true
                }
                .padding(.vertical, 4)
            }
            .padding()
        }
        .background(Color.page)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(editing ? Text(verbatim: "Edit match \(r.match) · \(r.team)") : Text("Match scouting"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            HelpButton(title: "Match scouting", items: Help.match)
            if !editing {
                Text("\(scout.isEmpty ? "No name set" : scout) · \(event.isEmpty ? "no event" : event)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            guard !editing else { return }
            r.type = lastType   // stays on Playoff through relaunches
            setCrew(wholeAlliance)
            snapToSchedule()
        }
        .onChange(of: r.match) { syncAndFill() }
        .onChange(of: r.type) {
            if !editing { lastType = r.type }
            snapToSchedule()
            syncAndFill()
        }
        .onChange(of: station) { old, new in switchSeat(from: old, to: new) }
        .onChange(of: wholeAlliance) { setCrew(wholeAlliance) }
        .task(id: r.team) {
            otherName = nil
            guard r.team > 0, store.db.info?.names[String(r.team)] == nil else { return }
            try? await Task.sleep(for: .milliseconds(600))   // wait for typing to finish
            if !Task.isCancelled { otherName = await Fetch.teamName(r.team, tbaKey: tbaKey) }
        }
        .confirmationDialog("Clear everything scored for \(r.team == 0 ? "this robot" : String(r.team))?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear answers", role: .destructive) {
                // Keeps who and which match; resets everything that was scored.
                withAnimation(.snappy) { r = MatchRecord(id: r.id, type: r.type, match: r.match, team: r.team, alliance: r.alliance) }
            }
        } message: {
            Text("The team and match number stay.")
        }
        .sheet(isPresented: Binding(get: { !shared.isEmpty }, set: { if !$0 { shared = [] } })) {
            QRSheet(title: "Match \(shared.first?.match ?? 0)",
                    codes: shared.map { ("Match \($0.match) · \($0.team)", Snapshot(matches: [$0])) })
        }
    }

    /// Whole match saves only robots someone actually scouted, so empty ones don't count as scouted.
    private var toSave: [Int] { crew.indices.filter { crew[$0].team > 0 && (!multi || crew[$0].hasData) } }
    private var canSave: Bool { r.match > 0 && !toSave.isEmpty }

    private var roleOptions: [(Role?, String)] { [(nil, "–")] + Role.allCases.map { (Optional($0), $0.rawValue) } }

    /// Changes several fields of the current robot in one go (one redraw, one undo-able step).
    private func edit(_ change: (inout MatchRecord) -> Void) {
        var copy = r
        change(&copy)
        r = copy
    }

    private var problemChips: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Chip(title: "Died / no-show", systemImage: "bolt.slash", isOn: rb.died, color: .redAlliance)
                Chip(title: "Tipped over", systemImage: "arrow.uturn.down", isOn: rb.tipped, color: .redAlliance)
            }
            GridRow {
                Chip(title: "E-stopped", systemImage: "stop.circle", isOn: rb.eStopped, color: .redAlliance)
                Chip(title: "A-stopped", systemImage: "pause.circle", isOn: rb.aStopped, color: .autoPhase)
            }
            GridRow {
                Chip(title: "Didn't shoot / drive only", systemImage: "nosign", isOn: rb.noShoot, color: .redAlliance)
                    .gridCellColumns(2)
            }
        }
    }

    private func towerOptions(points: Bool) -> [(Int?, String)] {
        [(nil, "–"), (0, "None"), (1, points ? "L1 · 10" : "L1"), (2, points ? "L2 · 20" : "L2"), (3, points ? "L3 · 30" : "L3")]
    }

    /// Six big buttons, Red 1-3 over Blue 1-3, to switch which robot the form is editing. Each robot
    /// keeps its own answers.
    private var switcher: some View {
        VStack(spacing: 8) {
            ForEach([0, 3], id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row..<row + 3, id: \.self) { i in robotButton(i) }
                }
            }
        }
    }

    private func robotButton(_ i: Int) -> some View {
        let red = i < 3
        return Button { withAnimation(.snappy) { current = i } } label: {
            HStack(spacing: 10) {
                Text(Self.seatName(i)).font(.caption.weight(.heavy)).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Self.robotColors[i], in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(crew[i].team == 0 ? "–" : String(crew[i].team)).font(.title3.weight(.heavy))
                    Text(crew[i].hasData ? "\(crew[i].points) pts entered" : status(crew[i].team).map(\.0).joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(current == i ? Color.alliance(red).opacity(0.18) : Color.surface,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(current == i ? Color.alliance(red) : Color.alliance(red).opacity(0.25), lineWidth: current == i ? 3 : 1))
        }
        .buttonStyle(Pressable())
        .accessibilityLabel("\(red ? "Red" : "Blue") \(i % 3 + 1), team \(crew[i].team)")
        .accessibilityAddTraits(current == i ? .isSelected : [])
    }

    /// Tap to add a spot for the selected robot; every robot in the crew shows in its own color.
    private var shotMap: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Where they shoot from").font(.headline)
                Spacer()
                Text("\(r.shots.count) spots").font(.subheadline).foregroundStyle(.secondary)
                Button("Undo spot", systemImage: "arrow.uturn.backward") { _ = r.shots.popLast() }
                    .labelStyle(.iconOnly)
                    .disabled(r.shots.isEmpty)
                Button("Clear all spots", systemImage: "trash") { withAnimation { r.shots = [] } }
                    .labelStyle(.iconOnly)
                    .disabled(r.shots.isEmpty)
            }
            if multi {
                // Pick the robot right here, then tap where it shot.
                Choice(options: crew.indices.map { ($0, Self.seatName($0)) },
                       selection: $current, color: Self.robotColors[min(current, 5)])
            }
            ShotField(series: crew.indices.map { i in
                ShotSeries(shots: crew[i].shots, color: multi ? Self.robotColors[i] : .fuel, label: multi ? Self.seatName(i) : "")
            }) { p in
                r.shots.append([(p.x * 1000).rounded() / 1000, (p.y * 1000).rounded() / 1000])
            }
        }
    }

    /// Playoffs turn around fast, so this is only what the elims strategists need (per the readme):
    /// role, weaknesses, breaks, and defense/strategy notes.
    private var playoffForm: some View {
        columns {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Playoff quick form", systemImage: "trophy.fill", color: .endPhase) {
                    edit {
                        $0.role = nil; $0.climb = nil; $0.died = false; $0.tipped = false
                        $0.eStopped = false; $0.aStopped = false; $0.noShoot = false; $0.defense = 0; $0.teleFuel = nil
                    }
                }
                Text("Role they played").font(.headline)
                Choice(options: roleOptions, selection: rb.role, color: .endPhase)
                Text("Tower").font(.headline)
                Choice(options: towerOptions(points: false), selection: rb.climb, color: .endPhase)
                problemChips
                Rating(title: "Defense", value: rb.defense, caption: "blank if they didn't", color: .endPhase)
                Counter(title: "Fuel scored (optional)", value: rb.teleFuel, color: .endPhase)
            }
            .card()

            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "For the strategists", systemImage: "text.bubble.fill", color: .gray) {
                    edit { $0.weaknesses = ""; $0.breaks = ""; $0.notes = "" }
                }
                note("Weaknesses we can use", "Slow intake, can't play through defense, misses from far…", rb.weaknesses)
                note("Breaks or surprises", "Lost the shooter in match 2, new auto…", rb.breaks)
                note("Defense and strategy notes", "Who they defended, where they shot from, how they climbed…", rb.notes)
            }
            .card()
        }
    }

    private func note(_ title: String, _ prompt: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            TextField(prompt, text: text, axis: .vertical)
                .lineLimit(3...6)
                .padding(10)
                .background(Color.well, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    /// Header in the icon's fuel yellow: who you're watching, what they can do, and points so far.
    private var header: some View {
        let info = store.db.info
        let pit = store.pit(r.team)
        let stations = (0..<6).map { ($0, $0 < 3 ? "Red \($0 + 1)" : "Blue \($0 - 2)") }
        let nameBlock = VStack(alignment: .leading, spacing: 6) {
                    Text(teamLabel(info))
                        .font(.headline).lineLimit(1)
                    if r.team > 0, info?.names[String(r.team)] == nil, !(info?.names.isEmpty ?? true) {
                        Label("Not on the \(eventName.isEmpty ? "event" : eventName) team list", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(Color.autoPhase)
                    }
                    HStack(spacing: 6) {
                        if let address = info?.pits[String(r.team)] { tag("Pit \(address)") }
                        if let pit, pit.hopper > 0 { tag("Holds \(pit.hopper)") }
                        if let pit { RobustBadge(value: pit.robustness) }
                        ForEach(status(r.team).filter { $0.1 != .secondary }, id: \.0) { text, color in
                            Text(text).font(.caption.weight(.heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4).background(color, in: Capsule())
                        }
                    }
                }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: compact ? 10 : 14) {
                if scheduled.isEmpty || editing { bigField("MATCH", rb.match) } else { matchPicker }
                bigField(editing ? "TEAM" : compact ? seatLabel : "TEAM · \(seatLabel)", rb.team)
                if !compact { nameBlock.padding(.top, 18) }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(r.points)")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.navy)
                        .contentTransition(.numericText(value: Double(r.points)))
                        .animation(.snappy, value: r.points)
                    Text(compact ? "PTS" : "EST. POINTS").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.secondary)
                }
            }
            if compact { nameBlock }
            (compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))) {
                Choice(options: MatchType.allCases.map { ($0, $0.rawValue) }, selection: rb.type, color: .accentColor, base: .surface)
                    .frame(maxWidth: compact ? .infinity : 300)
                if editing {
                    Choice(options: Alliance.allCases.map { ($0, $0.rawValue) }, selection: rb.alliance, color: .alliance(r.alliance == .red), base: .surface)
                } else if !multi {
                    // Your seat for the event; the team fills in from the downloaded schedule.
                    Choice(options: stations, selection: $station, color: .alliance(station < 3), base: .surface)
                }
            }
            HStack {
                if !editing {
                    Choice(options: [(false, "One robot"), (true, "Whole match")], selection: $wholeAlliance, color: .navy, base: .surface)
                        .frame(maxWidth: 320)
                }
                Spacer()
                if let queuing = info?.nowQueuing, !queuing.isEmpty, !editing {
                    Label("Now queuing: \(queuing)", systemImage: "clock.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Color.navy)
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Color.fuel.opacity(0.35), Color.fuel.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func teamLabel(_ info: EventData?) -> String {
        if r.team == 0 { return "Pick a team" }
        if let name = info?.names[String(r.team)] ?? otherName { return name }
        return info?.names.isEmpty ?? true ? "Pick your event in Data to see names" : "Team \(r.team)"
    }

    private func bigField(_ label: String, _ value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.secondary)
            NumberField(title: "–", value: value)
                .font(.system(size: compact ? 28 : 34, weight: .heavy, design: .rounded))
                .padding(.horizontal, 12)
                .frame(width: compact ? 104 : 140, height: 56)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.caption.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.surface, in: Capsule())
    }

    /// Two columns on iPad, one on iPhone.
    private var columns: AnyLayout {
        compact ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
    }

    /// This event's scheduled matches of the current type, so only real matches can be picked.
    private var scheduled: [ScheduledMatch] {
        guard let info = store.db.info, info.key == event else { return [] }
        return info.schedule.filter { $0.type == r.type }.sorted { $0.match < $1.match }
    }

    /// Picker of scheduled matches (each showing its six teams) with previous/next arrows.
    private var matchPicker: some View {
        let list = scheduled
        let index = list.firstIndex { $0.match == r.match }
        return VStack(alignment: .leading, spacing: 4) {
            Text("MATCH").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button { if let index, index > 0 { r.match = list[index - 1].match } } label: {
                    Image(systemName: "chevron.left").font(.title3.bold()).frame(width: compact ? 28 : 36, height: 56)
                }
                .disabled((index ?? 0) == 0)
                .accessibilityLabel("Previous match")
                Menu {
                    ForEach(list, id: \.self) { m in
                        Button("\(m.label) · \(m.red.map(String.init).joined(separator: " ")) vs \(m.blue.map(String.init).joined(separator: " "))") {
                            r.match = m.match
                        }
                    }
                } label: {
                    Text(r.match == 0 ? "–" : String(r.match))
                        .font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit()
                        .frame(width: compact ? 64 : 84, height: 56)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .accessibilityLabel("Match \(r.match), choose another")
                Button { if let index, index + 1 < list.count { r.match = list[index + 1].match } else if index == nil, let first = list.first { r.match = first.match } } label: {
                    Image(systemName: "chevron.right").font(.title3.bold()).frame(width: compact ? 28 : 36, height: 56)
                }
                .disabled(index.map { $0 + 1 >= list.count } ?? false)
                .accessibilityLabel("Next match")
            }
            .buttonStyle(Pressable())
            .foregroundStyle(Color.navy)
        }
    }

    /// When there's a schedule, keep the match on a real one: the next unscouted match by default.
    private func snapToSchedule() {
        let list = scheduled
        guard !editing, !list.isEmpty, !list.contains(where: { $0.match == r.match }) else { return }
        let scouted = store.db.matches.filter { $0.event == event && $0.type == r.type }.map(\.match).max() ?? 0
        let target = r.match > 0 ? r.match : scouted + 1
        r.match = (list.first { $0.match >= target } ?? list.last!).match
    }

    /// What we know about a team so far: no pit data yet, and how often it's been match scouted here.
    private func status(_ team: Int) -> [(String, Color)] {
        guard team > 0 else { return [("–", .secondary)] }
        let scouted = store.db.matches.filter { $0.event == event && $0.team == team }.count
        return [store.pit(team) == nil ? ("No pit data", .orange) : nil,
                scouted == 0 ? ("First match", .telePhase) : ("\(scouted) match\(scouted == 1 ? "" : "es")", .secondary)]
            .compactMap { $0 }
    }

    /// Red 1 / Blue 3 style name for the robot being edited.
    private var seatLabel: String {
        let i = multi ? current : station
        return "\(i < 3 ? "RED" : "BLUE") \(i % 3 + 1)"
    }

    /// One robot, or all six in this match as separate records. Whatever was entered for the
    /// current robot moves to its seat.
    private func setCrew(_ wholeMatch: Bool) {
        let keep = r
        if wholeMatch {
            crew = (0..<6).map { MatchRecord(type: keep.type, match: keep.match, alliance: $0 < 3 ? .red : .blue) }
            crew[station] = keep
            current = station
        } else {
            crew = [multi ? keep : r]
            current = 0
        }
        seats = [:]
        autofill()
    }

    private func save() {
        if editing {
            store.save(r)
            dismiss()
            return
        }
        var saved: [MatchRecord] = []
        for i in toSave {
            var m = crew[i]
            m.event = event
            m.scout = scout
            m.alliance = (multi ? i : station) < 3 ? .red : .blue
            store.save(m)
            if let stored = store.db.matches.first(where: { $0.id == m.id }) { saved.append(stored) }
        }
        shared = saved
        let next = r.match + 1, type = r.type
        crew = crew.indices.map { MatchRecord(type: type, match: next, alliance: (multi ? $0 : station) < 3 ? .red : .blue) }
        seats = [:]
        snapToSchedule()   // jump to the next scheduled match if match + 1 isn't one
        autofill()
    }

    /// One-robot mode: every seat is its own robot. Switching from Red 1 to Blue 1 puts Red 1's
    /// answers aside and starts Blue 1 fresh (or where it was left); switching back restores them.
    private func switchSeat(from old: Int, to new: Int) {
        guard !editing, !multi, old != new else { return }
        seats[old] = r
        r = seats[new] ?? MatchRecord(type: r.type, match: r.match)
        autofill()
    }

    /// Every robot in the crew is in the same match.
    private func syncAndFill() {
        seats = [:]   // a new match: other seats' answers belonged to the old one
        for i in crew.indices where i != current {
            crew[i].match = r.match
            crew[i].type = r.type
        }
        autofill()
    }

    /// Fills teams from the schedule: your station's robot, or all six. Typing over a team number
    /// is the override.
    private func autofill() {
        guard !editing,
              let m = store.db.info?.schedule.first(where: { $0.type == r.type && $0.match == r.match }) else { return }
        if multi {
            let teams = m.red + m.blue
            for i in crew.indices where i < teams.count && teams[i] > 0 { crew[i].team = teams[i] }
        } else {
            let teams = m.red + m.blue
            if station < teams.count, teams[station] > 0 { r.team = teams[station] }
        }
    }
}
