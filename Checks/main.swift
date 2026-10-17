import Foundation

// Run with ./build.sh --check. Covers the logic that loses or bends data if it breaks.

// Points follow the REBUILT manual: 1 per FUEL, 15 for an AUTO climb, 10/20/30 for TOWER levels.
var m = MatchRecord(team: 1678, autoFuel: 8, autoClimb: true, teleFuel: 40, climb: 3)
assert(m.points == 8 + 15 + 40 + 30)
assert(MatchRecord(climb: 2).towerPoints == 20)

// Data from an older version (missing fields) still decodes, with defaults filled in.
let old = #"{"matches":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","team":254,"match":3,"teleFuel":12}]}"#
let decoded = try! Snapshot.decode(Data(old.utf8))
assert(decoded.matches.count == 1 && decoded.matches[0].team == 254 && decoded.matches[0].climb == 0)
assert(decoded.picklist.isEmpty)

// Round trip through the QR / export encoding.
let roundTrip = try! Snapshot.decode(Snapshot(matches: [m]).encoded())
assert(roundTrip.matches[0] == m)

// Merging: new records are added, the newer edit of a record wins, an older one doesn't.
var db = Snapshot(matches: [m])
var edited = m
edited.teleFuel = 50
edited.date = m.date.addingTimeInterval(60)
assert(db.merge(Snapshot(matches: [edited, MatchRecord(team: 971)])) == 2)
assert(db.matches.count == 2 && db.matches[0].teleFuel == 50)
assert(db.merge(Snapshot(matches: [m])) == 0)
assert(db.matches[0].teleFuel == 50)
db.merge(Snapshot(pits: [PitRecord(team: 1678, robustness: 5)]))
db.merge(Snapshot(pits: [PitRecord(team: 1678, robustness: 2, updated: .distantPast)]))
assert(db.pits.count == 1 && db.pits[0].robustness == 5)

// Stats: ratings of 0 mean "not rated" and stay out of the average; pit-only teams still show up.
db = Snapshot(matches: [
    MatchRecord(event: "camb", team: 1678, teleFuel: 10, driver: 4),
    MatchRecord(event: "camb", team: 1678, teleFuel: 30, driver: 0, died: true),
    MatchRecord(event: "other", team: 1678, teleFuel: 999),
], pits: [PitRecord(team: 8033, robustness: 3)])
let stats = db.stats(event: "camb")
let s1678 = stats.first { $0.team == 1678 }!
assert(s1678.matches == 2 && s1678.teleFuel == 20 && s1678.driver == 4 && s1678.died == 0.5)
assert(stats.contains { $0.team == 8033 && $0.robustness == 3 })

// CSV quotes values and writes enum raw values.
let sheet = csv([MatchRecord(team: 1, alliance: .blue, notes: #"fast "swerve", good"#)])
assert(sheet.contains(#""Blue""#) && sheet.contains(#""fast ""swerve"", good""#))

// TBA schedule: quals keep their number, double-elim playoffs are 1-13, finals become 14-16.
let tbaMatches = #"""
[{"comp_level":"qm","set_number":1,"match_number":7,"alliances":{"red":{"team_keys":["frc1678","frc254","frc971"]},"blue":{"team_keys":["frc8033","frc5940","frc649B"]}}},
 {"comp_level":"sf","set_number":4,"match_number":1,"alliances":{"red":{"team_keys":["frc1","frc2","frc3"]},"blue":{"team_keys":["frc4","frc5","frc6"]}}},
 {"comp_level":"f","set_number":1,"match_number":2,"alliances":{"red":{"team_keys":[]},"blue":{"team_keys":[]}}}]
"""#
let tbaSchedule = try! Fetch.schedule(tba: Data(tbaMatches.utf8))
assert(tbaSchedule.map(\.match) == [7, 4, 15] && tbaSchedule[0].type == .qual && tbaSchedule[1].type == .playoff)
assert(tbaSchedule[0].red == [1678, 254, 971] && tbaSchedule[0].blue[2] == 649)

// Nexus labels, including practice matches TBA doesn't have; replays and unknown teams are handled.
let nexus = try! JSONDecoder().decode(NexusStatus.self, from: Data(#"""
{"nowQueuing":"Qualification 8","matches":[
 {"label":"Practice 3","redTeams":["1678","254",null],"blueTeams":["1","2","3"]},
 {"label":"Qualification 7","redTeams":["1678","254","9999"],"blueTeams":["8033","5940","649"]},
 {"label":"Qualification 7 Replay","redTeams":["1678","254","971"],"blueTeams":["8033","5940","649"]},
 {"label":"Final 1","redTeams":null,"blueTeams":null}]}
"""#.utf8))
let nexusSchedule = Fetch.schedule(nexus: nexus)
assert(nexusSchedule.count == 3 && nexusSchedule[0].type == .practice && nexusSchedule[0].red == [1678, 254, 0])
assert(nexusSchedule[2].match == 14)

// Merged: practice first, then quals, then playoffs; the newer source wins for the same match.
let merged = Fetch.merge(tbaSchedule, nexusSchedule)
assert(merged.map(\.label) == ["Practice 3", "Q7", "Playoff 4", "Playoff 14", "Playoff 15"])
assert(merged[1].red[2] == 9999)

// Event data travels in exports but never in QR codes, and newer downloads replace older ones.
assert(!String(decoding: Snapshot(matches: [m]).encoded(), as: UTF8.self).contains("info"))
var withInfo = Snapshot(info: EventData(key: "2026camb", fetched: Date(), names: ["1678": "Citrus Circuits"], opr: ["1678": 61.5]))
let reread = try! Snapshot.decode(withInfo.encoded())
assert(reread.info == withInfo.info)
assert(reread.stats(event: "2026camb").first { $0.team == 1678 }?.opr == 61.5)
assert(withInfo.merge(Snapshot(info: EventData(key: "2026camb", fetched: .distantPast))) == 0)

print("All checks passed.")
