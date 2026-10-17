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
                NavigationStack { PitList() }.tabItem { Label("Pit", systemImage: "wrench.and.screwdriver") }.tag("pit")
                TeamsView().tabItem { Label("Teams", systemImage: "tablecells") }.tag("teams")
                CompareView().tabItem { Label("H2H", systemImage: "arrow.up.arrow.down") }.tag("compare")
                PicklistView().tabItem { Label("Picks", systemImage: "list.number") }.tag("picklist")
                BoardView().tabItem { Label("Board", systemImage: "pencil.and.outline") }.tag("board")
                DataView().tabItem { Label("Data", systemImage: "qrcode") }.tag("data")
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
