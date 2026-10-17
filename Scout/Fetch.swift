import Foundation

/// Downloaded event info: The Blue Alliance (schedule, names, OPR, rankings, alliances), Statbotics
/// (EPA), and Nexus (live queue, practice schedule, pit addresses, alliances). A cache: refetch any time.
struct EventData: Codable, Equatable {
    var key = ""
    var fetched = Date.distantPast
    var schedule: [ScheduledMatch] = []
    var names: [String: String] = [:]     // team number → nickname
    var opr: [String: Double] = [:]
    var rank: [String: Int] = [:]
    var pits: [String: String] = [:]      // team number → pit address
    var nowQueuing = ""
    var epa: [String: Double] = [:]
    var alliances: [[Int]] = []           // captain, picks; teams here are taken during selection
    var results: [PlayedMatch] = []       // played matches with scores, for live EPA
}

/// A played match's alliance scores with foul points taken out (fouls aren't the robots' doing).
struct PlayedMatch: Codable, Hashable {
    var type = MatchType.qual
    var match = 0
    var red: [Int] = []
    var blue: [Int] = []
    var redScore = 0
    var blueScore = 0
}

/// An event to choose from, with ISO dates ("2026-03-05") so they compare as strings.
struct EventSummary: Codable, Hashable, Identifiable {
    var key = ""
    var name = ""
    var place = ""
    var start = ""
    var end = ""
    var id: String { key }
}

struct ScheduledMatch: Codable, Hashable {
    var type = MatchType.qual
    var match = 0
    var red: [Int] = []
    var blue: [Int] = []
    var label: String { "\(type == .qual ? "Q" : type == .playoff ? "Playoff " : "Practice ")\(match)" }
}

struct FetchError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

enum Fetch {
    /// Downloads whatever the keys allow and folds it into `info`. Returns a line per source.
    static func event(_ event: String, tbaKey: String, nexusKey: String, statbotics: Bool = true, into old: EventData?) async -> (EventData, [String]) {
        var info = old?.key == event ? old! : EventData(key: event)
        var log: [String] = []
        var ok = false
        if let tbaAPI = source("tba", key: tbaKey) {
            do {
                let tba = { (path: String) async throws -> Data in try await tbaAPI("/event/\(event)\(path)") }
                let teams = try JSONDecoder().decode([TBATeam].self, from: await tba("/teams/simple"))
                info.names = Dictionary(teams.map { (String($0.team_number), $0.nickname ?? "") }) { a, _ in a }
                let matches = try await tba("/matches")
                info.schedule = merge(info.schedule, try schedule(tba: matches))
                info.results = try results(tba: matches)
                // Both are null until matches have been played.
                if let oprs = try? JSONDecoder().decode(TBAOPRs.self, from: await tba("/oprs")).oprs {
                    info.opr = Dictionary(oprs.map { (String(number($0.key)), $0.value) }) { a, _ in a }
                }
                if let ranks = try? JSONDecoder().decode(TBARankings.self, from: await tba("/rankings")).rankings {
                    info.rank = Dictionary(ranks.map { (String(number($0.team_key)), $0.rank) }) { a, _ in a }
                }
                if let alliances = try? JSONDecoder().decode([TBAAlliancePicks]?.self, from: await tba("/alliances")), !alliances.isEmpty {
                    info.alliances = alliances.map { $0.picks.map(number) }
                }
                ok = true
                log.append("The Blue Alliance: \(teams.count) teams, \(info.schedule.count) matches\(info.opr.isEmpty ? "" : ", OPRs")\(info.rank.isEmpty ? "" : ", rankings").")
            } catch {
                log.append("The Blue Alliance: \(error.localizedDescription)")
            }
        }
        if let nexusAPI = source("nexus", key: nexusKey) {
            do {
                let nexus = { (path: String) async throws -> Data in try await nexusAPI("/event/\(event)\(path)") }
                let status = try JSONDecoder().decode(NexusStatus.self, from: await nexus(""))
                info.nowQueuing = status.nowQueuing ?? ""
                info.schedule = merge(info.schedule, schedule(nexus: status))
                if let pits = try? JSONDecoder().decode([String: String].self, from: await nexus("/pits")) { info.pits = pits }
                if let alliances = try? JSONDecoder().decode([[String?]].self, from: await nexus("/alliances")), !alliances.isEmpty {
                    info.alliances = alliances.map { $0.compactMap { Int($0 ?? "") } }
                }
                ok = true
                log.append("Nexus: \(status.matches.count) matches\(info.pits.isEmpty ? "" : ", pit addresses")\(info.nowQueuing.isEmpty ? "" : ", now queuing \(info.nowQueuing)").")
            } catch {
                log.append("Nexus: \(error.localizedDescription)")
            }
        }
        if statbotics {
            do {
                // No key needed. Statbotics also has team names, which helps when there's no TBA key.
                let data = try await get("https://api.statbotics.io/v3/team_events?event=\(event)&limit=1000")
                let teams = try JSONDecoder().decode([SBTeamEvent].self, from: data)
                for t in teams {
                    info.epa[String(t.team)] = t.epa.total_points
                    if info.names[String(t.team)] == nil, let name = t.team_name { info.names[String(t.team)] = name }
                }
                ok = ok || !teams.isEmpty
                if !teams.isEmpty { log.append("Statbotics: event EPA for \(teams.count) teams.") }
            } catch {
                log.append("Statbotics (event): \(error.localizedDescription)")
            }
            // Before matches, or at offseason events Statbotics doesn't track: each team's season EPA.
            // Fetched once per team; the event EPA replaces it once there is one.
            let missing = info.names.keys.filter { info.epa[$0] == nil }.compactMap { Int($0) }
            if !missing.isEmpty, let year = Int(event.prefix(4)) {
                // The website's backup copy first (one download, works when the API is down),
                // then the API team by team for anyone still missing.
                var season = await seasonEPAs(year: year).filter { missing.contains($0.key) }
                let rest = missing.filter { season[$0] == nil }
                if !rest.isEmpty {
                    await withTaskGroup(of: (Int, Double)?.self) { group in
                        for team in rest { group.addTask { await seasonEPA(team, year: year) } }
                        for await result in group { if let (team, epa) = result { season[team] = epa } }
                    }
                }
                for (team, epa) in season { info.epa[String(team)] = epa }
                ok = ok || !season.isEmpty
                log.append(season.isEmpty ? "Statbotics: no season EPA right now (its servers may be down)."
                                          : "Statbotics: \(year) season EPA for \(season.count) of \(missing.count) teams.")
            }
        }
        // Only a successful download counts as newer, so an offline refresh never wins a merge.
        if ok { info.fetched = Date() }
        return (info, log)
    }

    /// Events to pick from: this year's on TBA, the ones Nexus is running now, and your team's own.
    static func events(team: Int, tbaKey: String, nexusKey: String) async -> (mine: [EventSummary], all: [EventSummary], errors: [String]) {
        let year = Calendar.current.component(.year, from: Date())
        var mine: [EventSummary] = [], all: [EventSummary] = [], errors: [String] = []
        if let tbaAPI = source("tba", key: tbaKey) {
            let tba = { (path: String) async throws -> [EventSummary] in
                try JSONDecoder().decode([TBAEvent].self, from: await tbaAPI(path)).map(\.summary)
            }
            do { all = try await tba("/events/\(year)/simple") } catch { errors.append("The Blue Alliance: \(error.localizedDescription)") }
            if team > 0 { mine = (try? await tba("/team/frc\(team)/events/\(year)/simple")) ?? [] }
        }
        if let nexusAPI = source("nexus", key: nexusKey) {
            do {
                let live = try JSONDecoder().decode([String: NexusEvent].self, from: await nexusAPI("/events"))
                let known = Set(all.map(\.key))
                all += live.filter { !known.contains($0.key) }.map { key, e in
                    EventSummary(key: key, name: e.name, place: "on Nexus", start: day(e.start), end: day(e.end))
                }
            } catch {
                errors.append("Nexus: \(error.localizedDescription)")
            }
        }
        return (mine.sorted { $0.start < $1.start }, all.sorted { ($0.start, $0.name) < ($1.start, $1.name) }, errors)
    }

    /// Statbotics' website keeps a zlib-compressed copy of every team's season stats in a public
    /// bucket, and it still answers when the API is down. Undocumented, so the API stays as backup.
    static func seasonEPAs(year: Int) async -> [Int: Double] {
        guard let data = try? await get("https://storage.googleapis.com/site_v1/team_years/\(year)") else { return [:] }
        return seasonEPAs(bucket: data)
    }

    static func seasonEPAs(bucket data: Data) -> [Int: Double] {
        // zlib = 2-byte header + raw deflate (what Apple's .zlib reads) + 4-byte checksum.
        guard data.count > 6,
              let json = try? (data.subdata(in: 2..<(data.count - 4)) as NSData).decompressed(using: .zlib) as Data,
              let site = try? JSONDecoder().decode(SBSite.self, from: json) else { return [:] }
        return Dictionary(site.team_years.map { ($0.team, $0.epa.total_points) }) { a, _ in a }
    }

    private static func seasonEPA(_ team: Int, year: Int) async -> (Int, Double)? {
        guard let data = try? await get("https://api.statbotics.io/v3/team_year/\(team)/\(year)"),
              let t = try? JSONDecoder().decode(SBTeamYear.self, from: data) else { return nil }
        return (t.team, t.epa.total_points)
    }

    /// Any team's nickname, for teams that aren't on the current event's list.
    static func teamName(_ team: Int, tbaKey: String) async -> String? {
        guard team > 0, let tba = source("tba", key: tbaKey), let data = try? await tba("/team/frc\(team)/simple") else { return nil }
        return try? JSONDecoder().decode(TBATeam.self, from: data).nickname
    }

    /// The event happening today, else the next one, else the most recent.
    static func current(_ events: [EventSummary], today: String = day(Date())) -> EventSummary? {
        let sorted = events.sorted { $0.start < $1.start }
        return sorted.first { $0.start <= today && today <= $0.end }
            ?? sorted.first { $0.start > today }
            ?? sorted.last
    }

    /// Local calendar day as "yyyy-MM-dd".
    static func day(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func day(_ unixMillis: Double) -> String { day(Date(timeIntervalSince1970: unixMillis / 1000)) }

    /// The team server (web app, sync, and TBA/Nexus with the team's keys).
    static let defaultServer = "https://frc-scout-one.vercel.app"

    /// TBA or Nexus: with this iPad's own key if it has one, otherwise through the team server (which
    /// holds the keys), once team sync is set up in Data. Nil when neither is available.
    static func source(_ service: String, key: String) -> ((String) async throws -> Data)? {
        let tba = service == "tba"
        if !key.isEmpty {
            let base = tba ? "https://www.thebluealliance.com/api/v3" : "https://frc.nexus/api/v1"
            return { path in try await get(base + path, header: tba ? "X-TBA-Auth-Key" : "Nexus-Api-Key", key: key) }
        }
        let defaults = UserDefaults.standard
        let server = defaults.string(forKey: "syncURL") ?? defaultServer
        guard !server.isEmpty, let code = defaults.string(forKey: "syncCode"), !code.isEmpty else { return nil }
        return { path in
            var url = URLComponents(string: server + "/api/" + service)
            url?.queryItems = [URLQueryItem(name: "path", value: path)]
            return try await get(url?.url?.absoluteString ?? "", header: "x-team-code", key: code)
        }
    }

    /// Team sync: sends records, gets back what other devices saved since `since`, plus where to
    /// start next time. Records are the same JSON the web app uses.
    static func sync(server: String, code: String, event: String, since: Double, upload: Snapshot) async throws -> (Snapshot, Double) {
        guard let url = URL(string: server + "/api/sync") else { throw FetchError("That server address doesn't look right.") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(code, forHTTPHeaderField: "x-team-code")
        request.httpBody = try JSONEncoder().encode(SyncRequest(event: event, since: since, matches: upload.matches, pits: upload.pits,
                                                                rankings: upload.rankings, prescouts: upload.prescouts))
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401: throw FetchError("the team code is wrong.")
        case let status:
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw FetchError(message ?? "server said \(status).")
        }
        let next = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["next"] as? Double ?? since
        return (try Snapshot.decode(data), next)
    }

    private static func get(_ url: String, header: String? = nil, key: String = "") async throws -> Data {
        guard let url = URL(string: url) else { throw FetchError("That event code doesn't look right.") }
        var request = URLRequest(url: url)
        if let header { request.setValue(key, forHTTPHeaderField: header) }
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: return data
        case 401, 403: throw FetchError(header == "x-team-code" ? "the team code is wrong." : "the API key was rejected.")
        case 404: throw FetchError("not found there (yet). Check the event code.")
        case let code: throw FetchError("server said \(code).")
        }
    }

    // MARK: Parsing (pure, covered by Checks)

    static func schedule(tba data: Data) throws -> [ScheduledMatch] {
        try JSONDecoder().decode([TBAMatch].self, from: data).compactMap { m in
            guard let (type, match) = m.number else { return nil }
            return ScheduledMatch(type: type, match: match,
                                  red: (m.alliances["red"]?.team_keys ?? []).map(number),
                                  blue: (m.alliances["blue"]?.team_keys ?? []).map(number))
        }
    }

    /// Played matches only (TBA marks unplayed scores as -1), fouls subtracted.
    static func results(tba data: Data) throws -> [PlayedMatch] {
        try JSONDecoder().decode([TBAMatch].self, from: data).compactMap { m in
            guard let (type, match) = m.number,
                  let red = m.alliances["red"], let blue = m.alliances["blue"],
                  let redScore = red.score, let blueScore = blue.score, redScore >= 0, blueScore >= 0 else { return nil }
            return PlayedMatch(type: type, match: match, red: red.team_keys.map(number), blue: blue.team_keys.map(number),
                               redScore: redScore - (m.score_breakdown?["red"]?.foulPoints ?? 0),
                               blueScore: blueScore - (m.score_breakdown?["blue"]?.foulPoints ?? 0))
        }
        .sorted { order($0.type, $0.match) < order($1.type, $1.match) }
    }

    static func schedule(nexus status: NexusStatus) -> [ScheduledMatch] {
        status.matches.compactMap { m in
            guard let (type, match) = parse(label: m.label) else { return nil }
            return ScheduledMatch(type: type, match: match,
                                  red: (m.redTeams ?? []).map { Int($0 ?? "") ?? 0 },
                                  blue: (m.blueTeams ?? []).map { Int($0 ?? "") ?? 0 })
        }
    }

    /// Nexus labels: "Qualification 24" → (.qual, 24); finals become playoffs 14-16; replays are skipped.
    static func parse(label: String) -> (MatchType, Int)? {
        let words = label.split(separator: " ")
        guard words.count == 2, let n = Int(words[1]) else { return nil }
        switch words[0] {
        case "Practice": return (.practice, n)
        case "Qualification": return (.qual, n)
        case "Playoff": return (.playoff, n)
        case "Final": return (.playoff, 13 + n)
        default: return nil
        }
    }

    /// Play order: practice, then quals, then playoffs.
    static func order(_ type: MatchType, _ match: Int) -> Int { (MatchType.allCases.firstIndex(of: type) ?? 0) * 1000 + match }

    /// Newer source wins per match.
    static func merge(_ old: [ScheduledMatch], _ new: [ScheduledMatch]) -> [ScheduledMatch] {
        var byMatch = Dictionary(old.map { (order($0.type, $0.match), $0) }) { a, _ in a }
        for m in new { byMatch[order(m.type, m.match)] = m }
        return byMatch.values.sorted { order($0.type, $0.match) < order($1.type, $1.match) }
    }

    /// Our next match: the one queuing now or later (Nexus), else the first after the latest
    /// scouted match, else our first.
    static func nextMatch(for team: Int, in schedule: [ScheduledMatch], queuing: String, lastScouted: Int?) -> ScheduledMatch? {
        let ours = schedule.filter { ($0.red + $0.blue).contains(team) }.sorted { order($0.type, $0.match) < order($1.type, $1.match) }
        if let (type, n) = parse(label: queuing) { return ours.first { order($0.type, $0.match) >= order(type, n) } }
        if let last = lastScouted { return ours.first { order($0.type, $0.match) > last } }
        return ours.first
    }

    /// "frc1678" → 1678, "frc1678B" → 1678.
    static func number(_ teamKey: String) -> Int { Int(teamKey.filter(\.isNumber)) ?? 0 }
}

struct TBAMatch: Decodable {
    let comp_level: String
    let set_number: Int
    let match_number: Int
    let alliances: [String: TBAAlliance]
    let score_breakdown: [String: TBABreakdown]?

    /// Quals keep their number; double-elimination playoffs are 1-13 and finals become 14-16.
    var number: (MatchType, Int)? {
        switch comp_level {
        case "qm": return (.qual, match_number)
        case "sf": return (.playoff, set_number)
        case "f": return (.playoff, 13 + match_number)
        default: return nil
        }
    }
}
struct TBAAlliance: Decodable { let team_keys: [String]; let score: Int? }
struct TBABreakdown: Decodable { let foulPoints: Int? }
struct SyncRequest: Encodable {
    let event: String
    let since: Double
    let matches: [MatchRecord]
    let pits: [PitRecord]
    let rankings: [Comparison]
    let prescouts: [PreScout]
}
struct TBAAlliancePicks: Decodable { let picks: [String] }
struct TBAEvent: Decodable {
    let key: String
    let name: String
    let city: String?
    let state_prov: String?
    let start_date: String?
    let end_date: String?
    var summary: EventSummary {
        EventSummary(key: key, name: name, place: [city, state_prov].compactMap { $0 }.joined(separator: ", "),
                     start: start_date ?? "", end: end_date ?? "")
    }
}
struct NexusEvent: Decodable { let name: String; let start: Double; let end: Double }
struct SBTeamEvent: Decodable {
    let team: Int
    let team_name: String?
    let epa: SBEPA
}
/// Statbotics sends total_points as a number (API) or as {mean, sd} (website data); read either.
struct SBEPA: Decodable {
    let total_points: Double
    private enum Keys: String, CodingKey { case total_points }
    private struct Mean: Decodable { let mean: Double }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        total_points = try (try? c.decode(Double.self, forKey: .total_points)) ?? c.decode(Mean.self, forKey: .total_points).mean
    }
}
struct SBSite: Decodable { let team_years: [SBTeamYear] }
struct SBTeamYear: Decodable { let team: Int; let name: String?; let epa: SBEPA }
struct TBATeam: Decodable { let team_number: Int; let nickname: String? }
struct TBAOPRs: Decodable { let oprs: [String: Double]? }
struct TBARankings: Decodable { let rankings: [TBARank]? }
struct TBARank: Decodable { let team_key: String; let rank: Int }
struct NexusStatus: Decodable {
    let nowQueuing: String?
    let matches: [NexusMatch]
}
struct NexusMatch: Decodable {
    let label: String
    let redTeams: [String?]?
    let blueTeams: [String?]?
}
