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
    var startPos = StartPos.center
    var autoFuel = 0
    var autoClimb = false        // LEVEL 1 in AUTO
    var autoNeutral = false      // drove out to the neutral zone
    // TELEOP: only FUEL into an active HUB scores
    var teleFuel = 0
    var passes = 0               // volleys shuttled toward its own alliance zone
    var shootsOnMove = false
    var role = Role.scorer
    var climb = 0                // TOWER level at the end, 0-3
    // Ratings, 0 = not rated / didn't happen
    var accuracy = 0
    var driver = 0
    var defense = 0
    var died = false
    var tipped = false
    var notes = ""
    var date = Date()

    var towerPoints: Int { (autoClimb ? Points.autoTower : 0) + Points.tower[min(max(climb, 0), 3)] }
    var points: Int { autoFuel + teleFuel + towerPoints }
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
    var notes = ""
    var updated = Date()
    var id: Int { team }
}

struct TeamStats: Identifiable {
    let team: Int
    let matches: Int
    let points, autoFuel, teleFuel, tower, passes, accuracy, driver, defense, died: Double
    let robustness: Double       // 0 = not pit scouted
    var opr = 0.0, rank = 0, name = ""
    var id: Int { team }
}

/// Everything the app saves, and also what goes into a QR code or an export file.
struct Snapshot: Codable {
    var matches: [MatchRecord] = []
    var pits: [PitRecord] = []
    var picklist: [Int] = []
    var dnp: [Int] = []
    var picked: [Int] = []
    var info: EventData?         // downloaded TBA / Nexus data; left out of QR codes

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
        if let i = other.info, i.fetched > (info?.fetched ?? .distantPast) { info = i; changed += 1 }
        return changed
    }

    func stats(event: String) -> [TeamStats] {
        let all = matches.filter { event.isEmpty || $0.event == event }
        let info = self.info?.key == event ? self.info : nil
        let teams = Set(all.map(\.team)).union(pits.map(\.team)).union(info?.names.keys.compactMap { Int($0) } ?? [])
        return teams.map { team in
            let ms = all.filter { $0.team == team }
            return TeamStats(
                team: team, matches: ms.count,
                points: avg(ms.map(\.points)),
                autoFuel: avg(ms.map(\.autoFuel)),
                teleFuel: avg(ms.map(\.teleFuel)),
                tower: avg(ms.map(\.towerPoints)),
                passes: avg(ms.map(\.passes)),
                accuracy: avg(ms.map(\.accuracy).filter { $0 > 0 }),
                driver: avg(ms.map(\.driver).filter { $0 > 0 }),
                defense: avg(ms.map(\.defense).filter { $0 > 0 }),
                died: avg(ms.map { $0.died ? 1 : 0 }),
                robustness: Double(pits.first { $0.team == team }?.robustness ?? 0),
                opr: info?.opr[String(team)] ?? 0, rank: info?.rank[String(team)] ?? 0, name: info?.names[String(team)] ?? "")
        }.sorted { $0.points > $1.points }
    }

    /// Reads data from any app version. Keys an older version didn't have get their defaults,
    /// so adding a field in an update never makes saved data or an old scout's QR code unreadable.
    static func decode(_ data: Data) throws -> Snapshot {
        let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var obj = json(Snapshot()).merging(raw) { $1 }
        obj["matches"] = (raw["matches"] as? [[String: Any]] ?? []).map { json(MatchRecord()).merging($0) { $1 } }
        obj["pits"] = (raw["pits"] as? [[String: Any]] ?? []).map { json(PitRecord()).merging($0) { $1 } }
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
            let value = (child.value as? any RawRepresentable)?.rawValue ?? child.value
            return "\"" + "\(value)".replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }.joined(separator: ",")
    }
    return ([header] + lines).joined(separator: "\n")
}

@Observable
final class Store {
    var db = Snapshot() { didSet { save() } }
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
}
