import Foundation

// Run with ./build.sh --check. Covers the logic that loses or bends data if it breaks.

// Points follow the REBUILT manual: 1 per FUEL, 15 for an AUTO climb, 10/20/30 for TOWER levels.
var m = MatchRecord(team: 1678, autoFuel: 8, autoClimb: true, teleFuel: 40, climb: 3)
assert(m.points == 8 + 15 + 40 + 30)
assert(MatchRecord(climb: 2).towerPoints == 20)

// Data from an older version (missing fields) still decodes, with defaults filled in.
let old = #"{"matches":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","team":254,"match":3,"teleFuel":12}]}"#
let decoded = try! Snapshot.decode(Data(old.utf8))
assert(decoded.matches.count == 1 && decoded.matches[0].team == 254 && decoded.matches[0].climb == nil)
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

// Finding "my event": today's, else the next one, else the latest.
let events = [EventSummary(key: "a", start: "2026-03-05", end: "2026-03-08"),
              EventSummary(key: "b", start: "2026-10-16", end: "2026-10-18"),
              EventSummary(key: "c", start: "2026-11-07", end: "2026-11-08")]
assert(Fetch.current(events, today: "2026-10-17")?.key == "b")
assert(Fetch.current(events, today: "2026-10-20")?.key == "c")
assert(Fetch.current(events, today: "2026-12-01")?.key == "c")
assert(Fetch.current([], today: "2026-12-01") == nil)

// Statbotics team_events shape (from its source: epa.total_points is a number).
let sb = try! JSONDecoder().decode([SBTeamEvent].self, from: Data(#"[{"team":1678,"team_name":"Citrus Circuits","epa":{"total_points":58.4,"unitless":1900,"breakdown":{}}}]"#.utf8))
assert(sb[0].team == 1678 && sb[0].epa.total_points == 58.4)

// Slack posts: per-match thread with predicted scores and notes; picklist strikes taken teams.
var slackDB = Snapshot(matches: [MatchRecord(event: "e", match: 4, team: 1678, teleFuel: 40, notes: "fast cycles")],
                       info: EventData(key: "e", names: ["1678": "Citrus Circuits"], epa: ["254": 30]))
slackDB.picklist = [1678, 254]
let post = Slack.match("Q12", red: [1678, 0, 0], blue: [254, 0, 0], db: slackDB, event: "e")
assert(post.hasPrefix("*Q12* · e") && post.contains(":red_circle: *Red* · predicted 40") && post.contains("predicted 30"))
assert(post.contains("• *1678* Citrus Circuits — 40.0 pts in 1") && post.contains("_Q4: fast cycles_"))
assert(Slack.picklist(db: slackDB, event: "e", taken: [254]).contains("~2. *254* (EPA 30.0)~ taken"))

// Overview: coverage line, top scorers ranked, our schedule with partners and opponents.
slackDB.info?.schedule = [ScheduledMatch(type: .qual, match: 3, red: [1678, 111, 222], blue: [254, 333, 444])]
let overview = Slack.overview(db: slackDB, event: "e", eventName: "Battle o' Baltimore", ourTeam: 1678)
assert(overview.hasPrefix("*Battle o' Baltimore overview* · e\n1 robot-matches scouted · 0 of 2 teams pit scouted"))
assert(overview.contains("1. *1678* Citrus Circuits — 40.0 pts") && overview.contains("2. *254* — 30.0 EPA"))
assert(overview.contains("• Q3 (red): with 111, 222 vs 254, 333, 444"))

// Head-to-head: winners rise, ratings stay zero-sum, and comparisons survive QR/merge.
let c1 = Comparison(event: "e", match: 1, order: [1678, 254, 971], date: Date(timeIntervalSince1970: 1))
let c2 = Comparison(event: "e", match: 2, order: [1678, 971, 0], date: Date(timeIntervalSince1970: 2))
let ratings = elo([c2, c1])
assert(ratings[1678]! > ratings[254]! && ratings[254]! > 1450 && ratings[971]! < 1500)
assert(abs(ratings.values.reduce(0, +) - 4500) < 0.001)
var rankDB = Snapshot()
assert(rankDB.merge(try! Snapshot.decode(Snapshot(rankings: [c1]).encoded())) == 1)
assert(rankDB.stats(event: "e").first { $0.team == 1678 }!.h2h > 1500)

// Our next match: from Nexus "now queuing", else after the latest scouted match.
let ourSchedule = [ScheduledMatch(type: .qual, match: 3, red: [686, 1, 2], blue: [3, 4, 5]),
                   ScheduledMatch(type: .qual, match: 9, red: [6, 7, 8], blue: [686, 9, 10]),
                   ScheduledMatch(type: .playoff, match: 2, red: [686, 11, 12], blue: [13, 14, 15])]
assert(Fetch.nextMatch(for: 686, in: ourSchedule, queuing: "Qualification 4", lastScouted: nil)?.match == 9)
assert(Fetch.nextMatch(for: 686, in: ourSchedule, queuing: "Qualification 9", lastScouted: nil)?.match == 9)
assert(Fetch.nextMatch(for: 686, in: ourSchedule, queuing: "", lastScouted: Fetch.order(.qual, 9))?.type == .playoff)
assert(Fetch.nextMatch(for: 686, in: ourSchedule, queuing: "", lastScouted: nil)?.match == 3)

// Removing a team: gone from stats and its data deleted, but only for that event; survives a save.
let removeURL = FileManager.default.temporaryDirectory.appendingPathComponent("remove-check.json")
try? FileManager.default.removeItem(at: removeURL)
let removeStore = Store(url: removeURL)
removeStore.db = Snapshot(matches: [MatchRecord(event: "e", team: 9999), MatchRecord(event: "other", team: 9999)],
                          pits: [PitRecord(team: 9999)], info: EventData(key: "e", names: ["9999": "Gone", "1": "Stays"]))
removeStore.db.picklist = [9999, 1]
removeStore.remove(team: 9999, event: "e")
let reloaded = Store(url: removeURL).db
assert(!reloaded.stats(event: "e").contains { $0.team == 9999 } && reloaded.stats(event: "e").contains { $0.team == 1 })
assert(reloaded.matches.count == 1 && reloaded.matches[0].event == "other" && reloaded.pits.isEmpty && reloaded.picklist == [1])
assert(reloaded.stats(event: "other").contains { $0.team == 9999 })

// Statbotics season EPA shape (team_year: "name", not "team_name").
let season = try! JSONDecoder().decode(SBTeamYear.self, from: Data(#"{"team":686,"name":"Bovine Intervention","epa":{"total_points":41.7,"unitless":1650}}"#.utf8))
assert(season.team == 686 && season.epa.total_points == 41.7)

// Older pit records with since-removed questions (vision, batteries...) still load.
let oldPit = try! Snapshot.decode(Data(#"{"pits":[{"team":686,"robustness":4,"vision":true,"batteries":6,"autoAim":true}]}"#.utf8))
assert(oldPit.pits[0].team == 686 && oldPit.pits[0].robustness == 4)

// EPA arrives as a number (API) or {mean, sd} (Statbotics' website copy); both read the same.
let siteShape = try! JSONDecoder().decode(SBTeamYear.self, from: Data(#"{"team":686,"name":"Bovine Intervention","epa":{"total_points":{"mean":144.56,"sd":25.79}}}"#.utf8))
assert(siteShape.epa.total_points == 144.56)

// Live EPA: fouls come off the score, the over-performer rises, the under-performer falls,
// and unplayed matches (score -1) are ignored.
let tbaFull = #"""
[{"comp_level":"qm","set_number":1,"match_number":1,
  "alliances":{"red":{"team_keys":["frc1","frc2","frc3"],"score":110},"blue":{"team_keys":["frc4","frc5","frc6"],"score":60}},
  "score_breakdown":{"red":{"foulPoints":20},"blue":{"foulPoints":0}}},
 {"comp_level":"qm","set_number":1,"match_number":2,
  "alliances":{"red":{"team_keys":["frc1","frc2","frc3"],"score":-1},"blue":{"team_keys":["frc4","frc5","frc6"],"score":-1}},
  "score_breakdown":null}]
"""#
let played = try! Fetch.results(tba: Data(tbaFull.utf8))
assert(played.count == 1 && played[0].redScore == 90 && played[0].blueScore == 60)
let live = liveEPA(start: [1: 30, 2: 30, 3: 30, 4: 30, 5: 30, 6: 30], results: played)
assert(abs(live[1]! - 30) < 0.001 && abs(live[4]! - (30 + 0.5 * (60 - 90) / 3)) < 0.001)
let live2 = liveEPA(start: [1: 30, 2: 30, 3: 30, 4: 30, 5: 30, 6: 30], results: [PlayedMatch(red: [1, 2, 3], blue: [4, 5, 6], redScore: 150, blueScore: 30)])
assert(live2[1]! > 30 && live2[4]! < 30)
assert(liveEPA(start: [:], results: []).isEmpty)

// Not scored vs zero: blanks stay out of averages, zeros count, CSV leaves blanks empty.
var blanks = Snapshot(matches: [MatchRecord(event: "b", team: 7, autoFuel: 10, climb: 3),
                                MatchRecord(event: "b", team: 7, autoFuel: nil, climb: 0),
                                MatchRecord(event: "b", team: 7, autoFuel: 0)])
let s7 = blanks.stats(event: "b").first { $0.team == 7 }!
assert(s7.autoFuel == 5 && s7.tower == 15 && s7.points == 20)
let blankCSV = csv([MatchRecord(team: 7, autoFuel: nil, teleFuel: 5)])
assert(!blankCSV.contains("Optional") && !blankCSV.contains("nil") && blankCSV.contains(#","5","#))

// A robot with only a team and match isn't "scouted"; one tap of anything makes it so.
assert(!MatchRecord(match: 4, team: 686).hasData)
assert(MatchRecord(match: 4, team: 686, autoFuel: 0).hasData && MatchRecord(team: 686, noShoot: true).hasData)

// Never scouted shows as no data; a scouted 0 is a real 0.
let zeroDB = Snapshot(matches: [MatchRecord(event: "z", team: 5, autoFuel: 0, teleFuel: 0, climb: 0)], info: EventData(key: "z", names: ["5": "Zero", "6": "Unscouted"]))
let zeroStats = zeroDB.stats(event: "z")
assert(zeroStats.first { $0.team == 5 }!.points == 0 && zeroStats.first { $0.team == 5 }!.autoFuel == 0)
assert(zeroStats.first { $0.team == 6 }!.points == nil && zeroStats.first { $0.team == 6 }!.pointsKey < 0)

// Weighted picklist: higher on weighted factors ranks higher; missing data sits in the middle.
let pickDB = Snapshot(matches: [MatchRecord(event: "w", team: 1, teleFuel: 50), MatchRecord(event: "w", team: 2, teleFuel: 10)],
                      info: EventData(key: "w", names: ["1": "", "2": "", "3": ""], epa: ["1": 10, "2": 40, "3": 25]))
let byPoints = Pick.scores(pickDB.stats(event: "w"), weights: ["points": 1])
assert(byPoints[1]! == 1 && byPoints[2]! == 0 && byPoints[3]! == 0.5)
let byEPA = Pick.scores(pickDB.stats(event: "w"), weights: ["epa": 1])
assert(byEPA[2]! > byEPA[3]! && byEPA[3]! > byEPA[1]!)
let mixed = Pick.scores(pickDB.stats(event: "w"), weights: ["points": 1, "epa": 3])
assert(mixed[2]! > mixed[1]!)
assert(Pick.scores(pickDB.stats(event: "w"), weights: [:]).isEmpty)

// Pre-scouts: newest wins, survive the QR/sync encoding, and feed stats and the weighted picklist.
var pre = Snapshot(prescouts: [PreScout(team: 1, tier: 1, notes: "fast", updated: Date(timeIntervalSince1970: 10))])
assert(pre.merge(Snapshot(prescouts: [PreScout(team: 1, tier: 4, updated: Date(timeIntervalSince1970: 5))])) == 0)
assert(pre.merge(try! Snapshot.decode(Snapshot(prescouts: [PreScout(team: 1, tier: 2, updated: Date(timeIntervalSince1970: 20))]).encoded())) == 1)
assert(pre.prescouts.count == 1 && pre.prescouts[0].tier == 2)
pre.info = EventData(key: "t", names: ["1": "", "2": ""])
pre.prescouts.append(PreScout(team: 2, tier: 4))
let tierScores = Pick.scores(pre.stats(event: "t"), weights: ["tier": 1])
assert(pre.stats(event: "t").first { $0.team == 1 }!.tier == 2 && tierScores[1]! > tierScores[2]!)

print("All checks passed.")
