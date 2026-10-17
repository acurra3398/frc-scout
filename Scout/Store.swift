import Foundation
import Observation

/// REBUILT (2026) point values from the game manual, section 6.
enum Points {
    static let autoTower = 15             // LEVEL 1 in AUTO
    static let tower = [0, 10, 20, 30]    // TELEOP LEVEL 1-3, one level per robot
}

enum MatchType: String, Codable, CaseIterable { case practice = "Practice", qual = "Qual", playoff = "Playoff" }
enum Alliance: String, Codable, CaseIterable { case red = "Red", blue = "Blue" }
enum StartPos: String, Codable, CaseIterable { case depot = "Depot", center = "Center", outpost = "Outpost" }
enum Role: String, Codable, CaseIterable { case scorer = "Scorer", passer = "Passer", defense = "Defense", mixed = "Mixed" }

/// One robot in one match, filled in by the objective scout watching it.
struct MatchRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var event = ""
    var scout = ""
    var type = MatchType.qual
    var match = 0
    var team = 0
    var alliance = Alliance.red
    // AUTO (20 s)
    // nil = not scored (the scout didn't record it); 0 = they really scored none
    var startPos: StartPos?
    var autoFuel: Int?
    var autoClimb = false        // LEVEL 1 in AUTO
    var autoNeutral = false      // drove out to the neutral zone
    // TELEOP: only FUEL into an active HUB scores
    var teleFuel: Int?
    var passes: Int?             // volleys shuttled toward its own alliance zone
    var shootsOnMove = false
    var role: Role?
    var shots: [[Double]] = []   // where it shot from, as [x, y] fractions of the field
    var climb: Int?              // TOWER level at the end, 0-3
    // Ratings, 0 = not rated / didn't happen
    var accuracy = 0
    var driver = 0
    var defense = 0
    var died = false
    var tipped = false
    var eStopped = false         // E-stop: disabled for the rest of the match
    var aStopped = false         // A-stop: stopped during auto only
    var noShoot = false          // never shot; just drove or played defense
    var weaknesses = ""          // playoffs: what we can use against them
    var breaks = ""              // playoffs: breaks and surprises
    var notes = ""
    var date = Date()

    /// Whether anything was recorded beyond who and which match.
    var hasData: Bool {
        autoFuel != nil || teleFuel != nil || passes != nil || climb != nil || startPos != nil || role != nil
            || autoClimb || autoNeutral || shootsOnMove || died || tipped || eStopped || aStopped || noShoot
            || accuracy > 0 || driver > 0 || defense > 0 || !shots.isEmpty
            || !notes.isEmpty || !weaknesses.isEmpty || !breaks.isEmpty
    }

    var towerPoints: Int { (autoClimb ? Points.autoTower : 0) + Points.tower[min(max(climb ?? 0, 0), 3)] }
    var points: Int { (autoFuel ?? 0) + (teleFuel ?? 0) + towerPoints }
}

/// What the pit scout saw. Robustness uses the 1678 readme's 1-5 rubric.
struct PitRecord: Codable, Identifiable, Hashable {
    var team = 0
    var robustness = 0
    var drivetrain = "Swerve"
    var hopper = 0               // FUEL it can hold
    var trench = false           // fits under the TRENCH
    var bump = false             // drives over the BUMP
    var maxClimb = 0
    var autoClimb = false
    var shootsOnMove = false
    // Intake: where it can pick up FUEL
    var floorIntake = false
    var outpostIntake = false
    var depotIntake = false
    // Shooting
    var turret = false
    var range = 0                // 0 unknown, 1 at the hub, 2 anywhere in its zone, 3 from the neutral zone
    var shotRate = 0             // FUEL per second, as the team claims it
    var canPass = false          // shoots or pushes FUEL from midfield back to its own alliance zone
    // Climb
    var climbSeconds = 0
    var sideClimb = false        // leaves the middle of the TOWER for partners
    // Auto
    var autoCount = 0            // autos they can run
    var autoFuelClaim = 0
    var autoNeutral = false
    var autoConsistency = 0      // 0 not asked, 1 still testing/rarely, 2 about half, 3 most matches, 4 every match
    // Team
    var role = Role.scorer       // what they want to play
    var driverYears = 0
    var worries = ""             // what's broken or worrying them
    var notes = ""
    var updated = Date()
    var id: Int { team }

    static let autoConsistencyLabels = ["Not asked", "Still testing / rarely", "About half the time", "Most matches", "Every match"]
}

/// What we know about a team before the event (videos, TBA, past events): a tier and notes.
/// Follows the team across events, like pit records.
struct PreScout: Codable, Identifiable, Hashable {
    var team = 0
    var tier = 0                 // 0 none, 1 elite, 2 strong, 3 solid, 4 weak
    var notes = ""
    var updated = Date()
    var id: Int { team }

    static let tiers = ["–", "Tier 1 · elite", "Tier 2 · strong", "Tier 3 · solid", "Tier 4 · weak"]
}

/// One head-to-head judgment (1678's OverRate idea): an alliance's robots ordered best to worst.
struct Comparison: Codable, Identifiable, Hashable {
    var id = UUID()
    var event = ""
    var scout = ""
    var type = MatchType.qual
    var match = 0
    var order: [Int] = []        // best first
    var date = Date()
}

/// Head-to-head ratings: Elo (start 1500, K 32) over every "A beat B" pair, oldest first.
func elo(_ comparisons: [Comparison]) -> [Int: Double] {
    var rating: [Int: Double] = [:]
    for c in comparisons.sorted(by: { $0.date < $1.date }) {
        let order = c.order.filter { $0 > 0 }
        for i in order.indices {
            for j in order.indices where j > i {
                let winner = rating[order[i], default: 1500], loser = rating[order[j], default: 1500]
                let change = 32 * (1 - 1 / (1 + pow(10, (loser - winner) / 400)))
                rating[order[i]] = winner + change
                rating[order[j]] = loser - change
            }
        }
    }
    return rating
}

/// Live EPA for one event. Every team starts at its season EPA (or the event's average when it has
/// none). After each played match, the alliance's score without fouls is compared with what its
/// three robots' EPAs predicted, and each robot takes a share of the miss: half its third in its
/// first 6 matches here, a third of its third after that, and half as much again in playoffs.
/// Statbotics' event EPA works the same way; its exact weights differ, so this is labeled "Live".
func liveEPA(start: [Int: Double], results: [PlayedMatch]) -> [Int: Double] {
    guard !results.isEmpty else { return [:] }
    let average = start.isEmpty
        ? Double(results.map { $0.redScore + $0.blueScore }.reduce(0, +)) / Double(results.count * 6)
        : start.values.reduce(0, +) / Double(start.count)
    var epa: [Int: Double] = [:]
    var played: [Int: Int] = [:]
    for m in results {
        for (teams, score) in [(m.red, m.redScore), (m.blue, m.blueScore)] {
            let robots = teams.filter { $0 > 0 }
            guard !robots.isEmpty else { continue }
            for t in robots where epa[t] == nil { epa[t] = start[t] ?? average }
            let miss = Double(score) - robots.map { epa[$0]! }.reduce(0, +)
            for t in robots {
                let weight = (played[t, default: 0] < 6 ? 0.5 : 0.33) * (m.type == .playoff ? 0.5 : 1)
                epa[t]! += weight * miss / Double(robots.count)
                played[t, default: 0] += 1
            }
        }
    }
    return epa
}

struct TeamStats: Identifiable {
    let team: Int
    let matches: Int
    // From our scouting; nil means never scouted (or never recorded), which is different from 0.
    let points, autoFuel, teleFuel, tower, passes, accuracy, driver, defense, died: Double?
    let robustness: Double       // 0 = not pit scouted
    var opr = 0.0, epa = 0.0, rank = 0, name = ""
    var h2h = 0.0                // head-to-head rating, 0 = never compared
    var tier = 0                 // pre-scout tier, 0 = none
    var liveEPA = 0.0            // EPA updated by this event's results, 0 = no matches yet
    var id: Int { team }

    // Sort keys: unscouted sorts below a real 0.
    var pointsKey: Double { points ?? -1 }
    var autoKey: Double { autoFuel ?? -1 }
    var teleKey: Double { teleFuel ?? -1 }
    var towerKey: Double { tower ?? -1 }
    var passesKey: Double { passes ?? -1 }
    var accuracyKey: Double { accuracy ?? -1 }
    var driverKey: Double { driver ?? -1 }
    var defenseKey: Double { defense ?? -1 }
}

/// One ingredient of a weighted picklist: how to read it from a team's stats (nil = no data).
struct PickFactor {
    let key: String
    let label: String
    let value: (TeamStats) -> Double?
}

enum Pick {
    static let factors: [PickFactor] = [
        PickFactor(key: "points", label: "Scouted points") { $0.points },
        PickFactor(key: "auto", label: "Auto fuel") { $0.autoFuel },
        PickFactor(key: "tele", label: "Teleop fuel") { $0.teleFuel },
        PickFactor(key: "tower", label: "Tower points") { $0.tower },
        PickFactor(key: "live", label: "Live EPA") { $0.liveEPA > 0 ? $0.liveEPA : nil },
        PickFactor(key: "epa", label: "Season EPA") { $0.epa > 0 ? $0.epa : nil },
        PickFactor(key: "opr", label: "OPR") { $0.opr != 0 ? $0.opr : nil },
        PickFactor(key: "h2h", label: "Head-to-head") { $0.h2h > 0 ? $0.h2h : nil },
        PickFactor(key: "robust", label: "Robustness (pit)") { $0.robustness > 0 ? $0.robustness : nil },
        PickFactor(key: "driver", label: "Driver rating") { $0.driver },
        PickFactor(key: "defense", label: "Defense rating") { $0.defense },
        PickFactor(key: "reliable", label: "Reliability (didn't die)") { $0.died.map { 1 - $0 } },
        PickFactor(key: "tier", label: "Pre-scout tier") { $0.tier > 0 ? Double(5 - $0.tier) : nil },
    ]
    static let defaultWeights: [String: Double] = ["points": 3, "tower": 2, "live": 2, "epa": 1, "robust": 2, "reliable": 2]

    /// 0-1 score per team. Each factor is scaled 0-1 across the teams that have it; teams without
    /// it get 0.5, so missing data neither helps nor hurts. Then factors are mixed by weight.
    static func scores(_ stats: [TeamStats], weights: [String: Double]) -> [Int: Double] {
        var total: [Int: Double] = [:]
        var weightSum = 0.0
        for factor in factors {
            let weight = weights[factor.key] ?? 0
            let have = Dictionary(stats.compactMap { s in factor.value(s).map { (s.team, $0) } }) { a, _ in a }
            guard weight > 0, let lo = have.values.min(), let hi = have.values.max() else { continue }
            weightSum += weight
            for s in stats {
                let scaled = have[s.team].map { hi > lo ? ($0 - lo) / (hi - lo) : 0.5 } ?? 0.5
                total[s.team, default: 0] += weight * scaled
            }
        }
        return weightSum > 0 ? total.mapValues { $0 / weightSum } : [:]
    }
}

/// Everything the app saves, and also what goes into a QR code or an export file.
struct Snapshot: Codable {
    var matches: [MatchRecord] = []
    var pits: [PitRecord] = []
    var picklist: [Int] = []
    var dnp: [Int] = []
    var picked: [Int] = []
    var info: EventData?         // downloaded TBA / Nexus data; left out of QR codes
    var rankings: [Comparison] = []
    var removed: [String: [Int]] = [:]   // event → teams taken off its lists (TBA refreshes don't bring them back)
    var prescouts: [PreScout] = []
    var eventNames: [String: String] = [:] // event key → name, for the list of past events

    /// Adds records it hasn't seen and newer edits of ones it has. Returns how many changed.
    @discardableResult
    mutating func merge(_ other: Snapshot) -> Int {
        var changed = 0
        for m in other.matches {
            if let i = matches.firstIndex(where: { $0.id == m.id }) {
                if m.date > matches[i].date { matches[i] = m; changed += 1 }
            } else {
                matches.append(m); changed += 1
            }
        }
        for p in other.pits {
            if let i = pits.firstIndex(where: { $0.team == p.team }) {
                if p.updated > pits[i].updated { pits[i] = p; changed += 1 }
            } else {
                pits.append(p); changed += 1
            }
        }
        for p in other.prescouts {
            if let i = prescouts.firstIndex(where: { $0.team == p.team }) {
                if p.updated > prescouts[i].updated { prescouts[i] = p; changed += 1 }
            } else {
                prescouts.append(p); changed += 1
            }
        }
        for c in other.rankings {
            if let i = rankings.firstIndex(where: { $0.id == c.id }) {
                if c.date > rankings[i].date { rankings[i] = c; changed += 1 }
            } else {
                rankings.append(c); changed += 1
            }
        }
        if let i = other.info, i.fetched > (info?.fetched ?? .distantPast) { info = i; changed += 1 }
        return changed
    }

    func stats(event: String) -> [TeamStats] {
        let all = matches.filter { event.isEmpty || $0.event == event }
        let info = self.info?.key == event ? self.info : nil
        let compared = rankings.filter { event.isEmpty || $0.event == event }
        let gone = Set(removed[event] ?? [])
        let live = liveEPA(start: Dictionary(info?.epa.compactMap { k, v in Int(k).map { ($0, v) } } ?? []) { a, _ in a },
                           results: info?.results ?? [])
        let h2h = elo(compared)
        let teams = Set(all.map(\.team)).union(pits.map(\.team)).union(info.map { Array($0.names.keys) + Array($0.epa.keys) }?.compactMap { Int($0) } ?? [])
            .union(compared.flatMap(\.order).filter { $0 > 0 })
            .subtracting(gone)
        return teams.map { team in
            let ms = all.filter { $0.team == team }
            // Each part averages only the matches where it was scored: a blank isn't a zero, and a
            // team nobody scouted has no numbers at all (shown as a dash), unlike a real 0.
            let opt = { (xs: [Int]) -> Double? in xs.isEmpty ? nil : avg(xs) }
            let autoFuel = opt(ms.compactMap(\.autoFuel)), teleFuel = opt(ms.compactMap(\.teleFuel))
            let tower: Double? = ms.isEmpty ? nil : avg(ms.map { $0.autoClimb ? Points.autoTower : 0 })
                + avg(ms.compactMap { $0.climb.map { Points.tower[min(max($0, 0), 3)] } })
            return TeamStats(
                team: team, matches: ms.count,
                points: ms.isEmpty ? nil : (autoFuel ?? 0) + (teleFuel ?? 0) + (tower ?? 0),
                autoFuel: autoFuel,
                teleFuel: teleFuel,
                tower: tower,
                passes: opt(ms.compactMap(\.passes)),
                accuracy: opt(ms.map(\.accuracy).filter { $0 > 0 }),
                driver: opt(ms.map(\.driver).filter { $0 > 0 }),
                defense: opt(ms.map(\.defense).filter { $0 > 0 }),
                died: ms.isEmpty ? nil : avg(ms.map { $0.died ? 1 : 0 }),
                robustness: Double(pits.first { $0.team == team }?.robustness ?? 0),
                opr: info?.opr[String(team)] ?? 0, epa: info?.epa[String(team)] ?? 0, rank: info?.rank[String(team)] ?? 0, name: info?.names[String(team)] ?? "", h2h: h2h[team] ?? 0, tier: prescouts.first { $0.team == team }?.tier ?? 0,
                liveEPA: live[team] ?? 0)
        }.sorted { $0.pointsKey > $1.pointsKey }
    }

    /// Reads data from any app version. Keys an older version didn't have get their defaults,
    /// so adding a field in an update never makes saved data or an old scout's QR code unreadable.
    static func decode(_ data: Data) throws -> Snapshot {
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var obj = json(Snapshot()).merging(raw) { $1 }
        obj["matches"] = (raw["matches"] as? [[String: Any]] ?? []).map { json(MatchRecord()).merging($0) { $1 } }
        obj["pits"] = (raw["pits"] as? [[String: Any]] ?? []).map { json(PitRecord()).merging($0) { $1 } }
        obj["rankings"] = (raw["rankings"] as? [[String: Any]] ?? []).map { json(Comparison()).merging($0) { $1 } }
        obj["prescouts"] = (raw["prescouts"] as? [[String: Any]] ?? []).map { json(PreScout()).merging($0) { $1 } }
        obj["info"] = nil
        var snapshot = try JSONDecoder().decode(Snapshot.self, from: JSONSerialization.data(withJSONObject: obj))
        // Event data is only a download cache: if it can't be read, it's dropped and fetched again.
        if let info = raw["info"] as? [String: Any] {
            snapshot.info = try? JSONDecoder().decode(EventData.self, from: JSONSerialization.data(withJSONObject: json(EventData()).merging(info) { $1 }))
        }
        return snapshot
    }

    func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }
}

private func avg(_ xs: [Int]) -> Double { xs.isEmpty ? 0 : Double(xs.reduce(0, +)) / Double(xs.count) }

private func json<T: Encodable>(_ value: T) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(value))) as? [String: Any] ?? [:]
}

/// One row per record with a column per field, for Google Sheets / Excel.
func csv<T>(_ rows: [T]) -> String {
    guard let first = rows.first else { return "" }
    let header = Mirror(reflecting: first).children.map { $0.label ?? "" }.joined(separator: ",")
    let lines = rows.map { row in
        Mirror(reflecting: row).children.map { child -> String in
            // Blank (nil) cells stay empty instead of printing "nil" or "Optional(5)".
            let unwrapped = Mirror(reflecting: child.value).displayStyle == .optional
                ? Mirror(reflecting: child.value).children.first?.value ?? "" : child.value
            let value = (unwrapped as? any RawRepresentable)?.rawValue ?? unwrapped
            return "\"" + "\(value)".replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }.joined(separator: ",")
    }
    return ([header] + lines).joined(separator: "\n")
}

@Observable
final class Store {
    var db = Snapshot() { didSet { save() } }
    var syncStatus = ""          // how the last team sync went, for the Data tab
    @ObservationIgnored let url: URL

    init(url: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("scout.json")) {
        self.url = url
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            db = try Snapshot.decode(data)
        } catch {
            // Never overwrite data we couldn't read: set it aside so it can be recovered by hand.
            let aside = url.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
        }
    }

    func save() { try? db.encoded().write(to: url, options: .atomic) }

    func save(_ m: MatchRecord) {
        var m = m
        m.date = Date()
        db.merge(Snapshot(matches: [m]))
    }

    func save(_ p: PitRecord) {
        var p = p
        p.updated = Date()
        db.merge(Snapshot(pits: [p]))
    }

    func pit(_ team: Int) -> PitRecord? { db.pits.first { $0.team == team } }

    /// Takes a team off this event's lists and deletes its match and pit data on this iPad.
    func remove(team: Int, event: String) {
        var d = db   // one save instead of one per change
        d.matches.removeAll { $0.team == team && $0.event == event }
        d.pits.removeAll { $0.team == team }
        d.picklist.removeAll { $0 == team }
        d.dnp.removeAll { $0 == team }
        d.picked.removeAll { $0 == team }
        d.removed[event, default: []].append(team)
        db = d
    }

    /// Shares this event's scouting with the team server: uploads what changed here (everything the
    /// first time, or after a QR scan or import), then merges what other devices saved. Never deletes.
    /// Returns how many records arrived or changed.
    @discardableResult
    func sync(server: String, code: String, event: String) async throws -> Int {
        let defaults = UserDefaults.standard
        let sameEvent = defaults.string(forKey: "syncEvent") == event
        let lastPush = defaults.double(forKey: "syncLastPush")
        let everything = !sameEvent || lastPush == 0 || defaults.bool(forKey: "syncPushAll")
        let cutoff = lastPush - 120   // a little overlap; the server ignores anything it already has
        let started = Date().timeIntervalSinceReferenceDate
        var upload = Snapshot()
        upload.matches = db.matches.filter { $0.event == event && (everything || $0.date.timeIntervalSinceReferenceDate > cutoff) }
        upload.pits = db.pits.filter { everything || $0.updated.timeIntervalSinceReferenceDate > cutoff }
        upload.rankings = db.rankings.filter { $0.event == event && (everything || $0.date.timeIntervalSinceReferenceDate > cutoff) }
        upload.prescouts = db.prescouts.filter { everything || $0.updated.timeIntervalSinceReferenceDate > cutoff }
        let (incoming, next) = try await Fetch.sync(server: server, code: code, event: event,
                                                    since: sameEvent ? defaults.double(forKey: "syncSince") : 0, upload: upload)
        var merged = db
        let changed = merged.merge(incoming)
        if changed > 0 { db = merged }   // only save when something actually arrived
        defaults.set(started, forKey: "syncLastPush")
        defaults.set(next, forKey: "syncSince")
        defaults.set(event, forKey: "syncEvent")
        defaults.set(false, forKey: "syncPushAll")
        return changed
    }

    /// Syncs and records how it went; never throws, so the background loop keeps going.
    func runSync(server: String, code: String, event: String) async {
        do {
            let changed = try await sync(server: server, code: code, event: event)
            syncStatus = "Synced at \(Date().formatted(date: .omitted, time: .shortened))\(changed > 0 ? " · \(changed) new or updated" : "")"
        } catch {
            syncStatus = "Sync failed: \(error.localizedDescription) Everything is still saved on this iPad."
        }
    }

    func save(_ p: PreScout) {
        var p = p
        p.updated = Date()
        db.merge(Snapshot(prescouts: [p]))
    }

    func save(_ c: Comparison) {
        var c = c
        c.date = Date()
        db.merge(Snapshot(rankings: [c]))
    }
}
