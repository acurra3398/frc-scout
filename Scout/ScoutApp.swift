import SwiftUI

@main
struct ScoutApp: App {
    @State private var store = Store()
    // Remembered between launches; `-tab board` as a launch argument also works (UserDefaults reads it).
    @AppStorage("tab") private var tab = "match"

    @ViewBuilder private func screen(_ id: String) -> some View {
        switch id {
        case "match": NavigationStack { MatchForm() }.tabItem { Label("Match", systemImage: "binoculars") }.tag(id)
        case "pit": NavigationStack { PitList() }.tabItem { Label("Pit", systemImage: "wrench.and.screwdriver") }.tag(id)
        case "teams": TeamsView().tabItem { Label("Teams", systemImage: "tablecells") }.tag(id)
        case "compare": CompareView().tabItem { Label("H2H", systemImage: "arrow.up.arrow.down") }.tag(id)
        case "picklist": PicklistView().tabItem { Label("Picks", systemImage: "list.number") }.tag(id)
        case "board": BoardView().tabItem { Label("Board", systemImage: "pencil.and.outline") }.tag(id)
        default: DataView().tabItem { Label("Data", systemImage: "gearshape") }.tag(id)
        }
    }

    var body: some Scene {
        WindowGroup {
            // An iPhone shows four tabs and puts the rest under More: keep the scout's tabs (and setup) up front.
            TabView(selection: $tab) {
                ForEach(UIDevice.current.userInterfaceIdiom == .phone
                        ? ["match", "pit", "teams", "data", "compare", "picklist", "board"]
                        : ["match", "pit", "teams", "compare", "picklist", "board", "data"], id: \.self) { screen($0) }
            }
            .onAppear {
                // First launch: setup comes first, since nothing works without a name and an event.
                if (UserDefaults.standard.string(forKey: "event") ?? "").isEmpty { tab = "data" }
            }
            .fontDesign(.rounded)
            .environment(store)
            .task {
                // Every 20 s while the app is open: team sync (when set up). Every minute: Nexus (live
                // queue and picks). Every 5 minutes: TBA and Statbotics. Also right at launch.
                // Offline tries change nothing.
                let defaults = UserDefaults.standard
                if let event = defaults.string(forKey: "event"), let name = defaults.string(forKey: "eventName"),
                   !event.isEmpty, !name.isEmpty, store.db.eventNames[event] == nil {
                    store.db.eventNames[event] = name
                }
                var tick = 0
                while !Task.isCancelled {
                    let defaults = UserDefaults.standard
                    let event = defaults.string(forKey: "event") ?? ""
                    let code = defaults.string(forKey: "syncCode") ?? ""
                    let server = defaults.string(forKey: "syncURL") ?? Fetch.defaultServer
                    if !event.isEmpty {
                        let nexus = !(defaults.string(forKey: "nexusKey") ?? "").isEmpty || !code.isEmpty
                        if tick % 15 == 0 || (tick % 3 == 0 && nexus) {
                            let full = tick % 15 == 0
                            let (info, _) = await Fetch.event(event, tbaKey: full ? defaults.string(forKey: "tbaKey") ?? "" : "",
                                                              nexusKey: defaults.string(forKey: "nexusKey") ?? "", statbotics: full, into: store.db.info)
                            if info != store.db.info { store.db.info = info }
                        }
                        if !code.isEmpty { await store.runSync(server: server, code: code, event: event) }
                    }
                    tick += 1
                    try? await Task.sleep(for: .seconds(20))
                }
            }
        }
    }
}
