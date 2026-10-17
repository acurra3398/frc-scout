import Foundation

/// Posts for Slack, shared through the share sheet (pick Slack, then the channel or thread).
/// Uses Slack's markup: *bold*, _italic_, ~strike~. Shaped like the 1678 readme's #comp_strategy
/// threads: one per match with each team's numbers and scout notes, plus the picklist.
enum Slack {
    static func match(_ title: String, red: [Int], blue: [Int], db: Snapshot, event: String) -> String {
        let stats = Dictionary(uniqueKeysWithValues: db.stats(event: event).map { ($0.team, $0) })
        var lines = ["*\(title)*\(event.isEmpty ? "" : " · \(event)")"]
        for (name, emoji, teams) in [("Red", ":red_circle:", red), ("Blue", ":large_blue_circle:", blue)] {
            let total = teams.map { predicted(stats[$0]) }.reduce(0, +)
            lines.append("")
            lines.append("\(emoji) *\(name)* · predicted \(Int(total.rounded()))")
            for team in teams where team > 0 {
                lines += teamLines(team, stats[team], db: db, event: event, notes: 2)
            }
        }
        return lines.joined(separator: "\n")
    }

    static func team(_ team: Int, db: Snapshot, event: String) -> String {
        teamLines(team, db.stats(event: event).first { $0.team == team }, db: db, event: event, notes: 6)
            .joined(separator: "\n")
    }

    static func picklist(db: Snapshot, event: String, taken: Set<Int>) -> String {
        let stats = Dictionary(uniqueKeysWithValues: db.stats(event: event).map { ($0.team, $0) })
        let lines = db.picklist.enumerated().map { rank, team -> String in
            var line = "\(rank + 1). *\(team)*"
            if let s = stats[team] {
                if !s.name.isEmpty { line += " \(s.name)" }
                let numbers = [s.points.map { "\(one($0)) pts" }, s.epa > 0 ? "EPA \(one(s.epa))" : nil].compactMap { $0 }
                if !numbers.isEmpty { line += " (\(numbers.joined(separator: ", ")))" }
            }
            if taken.contains(team) { line = "~\(line)~ taken" }
            if db.dnp.contains(team) { line += " :no_entry: DNP" }
            return line
        }
        return (["*Picklist*\(event.isEmpty ? "" : " · \(event)")"] + lines).joined(separator: "\n")
    }

    /// The whole event at a glance: coverage, top scorers, climbers, defenders, red flags, our
    /// schedule, and DNPs. For posting in #comp_strategy before a strategy meeting.
    static func overview(db: Snapshot, event: String, eventName: String, ourTeam: Int) -> String {
        let stats = db.stats(event: event)
        let scouted = db.matches.filter { event.isEmpty || $0.event == event }
        let pitDone = stats.filter { s in db.pits.contains { $0.team == s.team } }.count
        var lines = ["*\(eventName.isEmpty ? "Scouting" : eventName) overview*\(event.isEmpty ? "" : " · \(event)")",
                     "\(scouted.count) robot-matches scouted · \(pitDone) of \(stats.count) teams pit scouted"]

        let top = stats.filter { predicted($0) > 0 }.sorted { predicted($0) > predicted($1) }.prefix(8)
        if !top.isEmpty {
            lines += ["", "*Top scorers* (live EPA, else scouted average, else season EPA)"]
            lines += top.enumerated().map { i, s in
                var line = "\(i + 1). *\(s.team)*\(s.name.isEmpty ? "" : " \(s.name)") — \(one(predicted(s))) \(s.liveEPA > 0 ? "live EPA" : s.points != nil ? "pts" : "EPA")"
                if let tower = s.tower, tower > 0 { line += " · tower \(one(tower))" }
                if s.robustness > 0 { line += " · robust \(Int(s.robustness))/5" }
                return line
            }
        }
        let h2h = stats.filter { $0.h2h > 0 }.sorted { $0.h2h > $1.h2h }.prefix(5)
        if !h2h.isEmpty {
            lines += ["", "*Head-to-head leaders*: " + h2h.map { "\($0.team) (\(Int($0.h2h.rounded())))" }.joined(separator: ", ")]
        }
        let climbers = stats.filter { $0.towerKey > 0 }.sorted { $0.towerKey > $1.towerKey }.prefix(5)
        if !climbers.isEmpty {
            lines += ["", "*Best climbers*: " + climbers.map { "\($0.team) (\(one($0.towerKey)))" }.joined(separator: ", ")]
        }
        let defenders = stats.filter { $0.defenseKey > 0 }.sorted { $0.defenseKey > $1.defenseKey }.prefix(3)
        if !defenders.isEmpty {
            lines.append("*Best defense*: " + defenders.map { "\($0.team) (\(one($0.defenseKey))/5)" }.joined(separator: ", "))
        }
        let risky = stats.filter { ($0.died ?? 0) > 0 || (1...2).contains(Int($0.robustness)) }
        if !risky.isEmpty {
            lines.append(":warning: *Reliability*: " + risky.map { s in
                var why: [String] = []
                if let died = s.died, died > 0 { why.append("died \(Int(died * 100))%") }
                if (1...2).contains(Int(s.robustness)) { why.append("robust \(Int(s.robustness))/5") }
                return "\(s.team) (\(why.joined(separator: ", ")))"
            }.joined(separator: ", "))
        }
        if ourTeam > 0, let schedule = db.info?.schedule.filter({ ($0.red + $0.blue).contains(ourTeam) }), !schedule.isEmpty {
            lines += ["", "*Our matches*"]
            lines += schedule.map { m in
                let ours = m.red.contains(ourTeam) ? m.red : m.blue
                let theirs = m.red.contains(ourTeam) ? m.blue : m.red
                return "• \(m.label) (\(m.red.contains(ourTeam) ? "red" : "blue")): with "
                    + ours.filter { $0 != ourTeam }.map(String.init).joined(separator: ", ")
                    + " vs " + theirs.map(String.init).joined(separator: ", ")
            }
        }
        if !db.dnp.isEmpty {
            lines += ["", ":no_entry: *DNP*: " + db.dnp.map(String.init).joined(separator: ", ")]
        }
        return lines.joined(separator: "\n")
    }

    /// Best guess at a robot's points: live EPA (real scores at this event), else the scouted
    /// average, else season EPA.
    static func predicted(_ s: TeamStats?) -> Double {
        guard let s else { return 0 }
        return s.liveEPA > 0 ? s.liveEPA : s.points ?? s.epa
    }

    private static func teamLines(_ team: Int, _ s: TeamStats?, db: Snapshot, event: String, notes: Int) -> [String] {
        var head = "• *\(team)*"
        var parts: [String] = []
        if let s {
            if !s.name.isEmpty { head += " \(s.name)" }
            if let points = s.points { parts.append("\(one(points)) pts in \(s.matches)") }
            if s.liveEPA > 0 { parts.append("live EPA \(one(s.liveEPA))") }
            if s.epa > 0 { parts.append("season EPA \(one(s.epa))") }
            if let tower = s.tower, tower > 0 { parts.append("tower \(one(tower))") }
            if s.robustness > 0 { parts.append("robust \(Int(s.robustness))/5") }
            if let died = s.died, died > 0 { parts.append(":warning: died \(Int(died * 100))%") }
        }
        if let pit = db.pits.first(where: { $0.team == team }), pit.maxClimb > 0 { parts.append("climbs L\(pit.maxClimb)") }
        var lines = [parts.isEmpty ? head : "\(head) — \(parts.joined(separator: " · "))"]
        let recent = db.matches
            .filter { $0.team == team && (event.isEmpty || $0.event == event) && !($0.notes + $0.weaknesses + $0.breaks).isEmpty }
            .sorted { Fetch.order($0.type, $0.match) > Fetch.order($1.type, $1.match) }
            .prefix(notes)
        lines += recent.map { m in
            let said = [m.weaknesses.isEmpty ? nil : "weakness: \(m.weaknesses)", m.breaks.isEmpty ? nil : "broke: \(m.breaks)",
                        m.notes.isEmpty ? nil : m.notes].compactMap { $0 }.joined(separator: " · ")
            return "    _\(m.type == .qual ? "Q" : m.type == .playoff ? "P" : "Practice ")\(m.match): \(said)_"
        }
        return lines
    }

    private static func one(_ x: Double) -> String { String(format: "%.1f", x) }
}
