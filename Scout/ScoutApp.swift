import SwiftUI

@main
struct ScoutApp: App {
    @State private var store = Store()
    // Remembered between launches; `-tab board` as a launch argument also works (UserDefaults reads it).
    @AppStorage("tab") private var tab = "match"

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                NavigationStack { MatchForm() }.tabItem { Label("Match", systemImage: "binoculars") }.tag("match")
                NavigationStack { PitForm() }.tabItem { Label("Pit", systemImage: "wrench.and.screwdriver") }.tag("pit")
                TeamsView().tabItem { Label("Teams", systemImage: "tablecells") }.tag("teams")
                PicklistView().tabItem { Label("Picklist", systemImage: "list.number") }.tag("picklist")
                BoardView().tabItem { Label("Board", systemImage: "pencil.and.outline") }.tag("board")
                DataView().tabItem { Label("Data", systemImage: "qrcode") }.tag("data")
            }
            .environment(store)
            .task {
                // Nexus is live at events: keep the schedule and "now queuing" fresh while the app is open.
                while !Task.isCancelled {
                    let defaults = UserDefaults.standard
                    if let key = defaults.string(forKey: "nexusKey"), !key.isEmpty,
                       let event = defaults.string(forKey: "event"), !event.isEmpty {
                        let (info, _) = await Fetch.event(event, tbaKey: "", nexusKey: key, into: store.db.info)
                        if info != store.db.info { store.db.info = info }
                    }
                    try? await Task.sleep(for: .seconds(60))
                }
            }
        }
    }
}

/// Integer field that updates its binding on every keystroke (TextField(value:) waits for return).
struct NumberField: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        TextField(title, text: Binding(
            get: { value == 0 ? "" : String(value) },
            set: { value = Int($0.filter(\.isNumber).prefix(5)) ?? 0 }))
        .keyboardType(.numberPad)
        .monospacedDigit()
    }
}

/// Big tap targets for counting while watching the field: -1, +1, +5, +10.
struct Counter: View {
    let title: String
    @Binding var value: Int
    var steps = [1, 5, 10]

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Text("\(value)").font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
            }
            HStack(spacing: 8) {
                Button { value = max(0, value - 1) } label: {
                    Image(systemName: "minus").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Minus one \(title)")
                ForEach(steps, id: \.self) { step in
                    Button { withAnimation(.snappy) { value += step } } label: {
                        Text("+\(step)").font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Add \(step) \(title)")
                }
            }
        }
        .sensoryFeedback(.increase, trigger: value)
    }
}

/// 1-5 rating where tapping the current value clears it back to 0 (not rated).
struct Rating: View {
    let title: String
    @Binding var value: Int
    var caption = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { n in
                    Button { value = value == n ? 0 : n } label: {
                        Text("\(n)").font(.headline).frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                    .tint(value == n ? .accentColor : .secondary)
                    .accessibilityAddTraits(value == n ? .isSelected : [])
                }
            }
        }
    }
}
