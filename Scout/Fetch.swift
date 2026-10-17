import Foundation

/// Downloaded event info: The Blue Alliance (schedule, names, OPR, rankings) and Nexus (live queue,
/// schedule including practice matches, pit addresses). A cache: refetch any time there's internet.
struct EventData: Codable, Equatable {
    var key = ""
    var fetched = Date.distantPast
    var schedule: [ScheduledMatch] = []
    var names: [String: String] = [:]     // team number → nickname
    var opr: [String: Double] = [:]
    var rank: [String: Int] = [:]
    var pits: [String: String] = [:]      // team number → pit address
    var nowQueuing = ""
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
    static func event(_ event: String, tbaKey: String, nexusKey: String, into old: EventData?) async -> (EventData, [String]) {
        var info = old?.key == event ? old! : EventData(key: event)
        var log: [String] = []
        var ok = false
        if !tbaKey.isEmpty {
            do {
                let tba = { (path: String) async throws -> Data in try await get("https://www.thebluealliance.com/api/v3/event/\(event)\(path)", header: "X-TBA-Auth-Key", key: tbaKey) }
                let teams = try JSONDecoder().decode([TBATeam].self, from: await tba("/teams/simple"))
                info.names = Dictionary(teams.map { (String($0.team_number), $0.nickname ?? "") }) { a, _ in a }
                info.schedule = merge(info.schedule, try schedule(tba: await tba("/matches/simple")))
                // Both are null until matches have been played.
                if let oprs = try? JSONDecoder().decode(TBAOPRs.self, from: await tba("/oprs")).oprs {
                    info.opr = Dictionary(oprs.map { (String(number($0.key)), $0.value) }) { a, _ in a }
                }
                if let ranks = try? JSONDecoder().decode(TBARankings.self, from: await tba("/rankings")).rankings {
                    info.rank = Dictionary(ranks.map { (String(number($0.team_key)), $0.rank) }) { a, _ in a }
                }
                ok = true
                log.append("The Blue Alliance: \(teams.count) teams, \(info.schedule.count) matches\(info.opr.isEmpty ? "" : ", OPRs")\(info.rank.isEmpty ? "" : ", rankings").")
            } catch {
                log.append("The Blue Alliance: \(error.localizedDescription)")
            }
        }
        if !nexusKey.isEmpty {
            do {
                let nexus = { (path: String) async throws -> Data in try await get("https://frc.nexus/api/v1/event/\(event)\(path)", header: "Nexus-Api-Key", key: nexusKey) }
                let status = try JSONDecoder().decode(NexusStatus.self, from: await nexus(""))
                info.nowQueuing = status.nowQueuing ?? ""
                info.schedule = merge(info.schedule, schedule(nexus: status))
                if let pits = try? JSONDecoder().decode([String: String].self, from: await nexus("/pits")) { info.pits = pits }
                ok = true
                log.append("Nexus: \(status.matches.count) matches\(info.pits.isEmpty ? "" : ", pit addresses")\(info.nowQueuing.isEmpty ? "" : ", now queuing \(info.nowQueuing)").")
            } catch {
                log.append("Nexus: \(error.localizedDescription)")
            }
        }
        // Only a successful download counts as newer, so an offline refresh never wins a merge.
        if ok { info.fetched = Date() }
        return (info, log)
    }

    private static func get(_ url: String, header: String, key: String) async throws -> Data {
        guard let url = URL(string: url) else { throw FetchError("That event code doesn't look right.") }
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: header)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: return data
        case 401, 403: throw FetchError("the API key was rejected.")
        case 404: throw FetchError("no event \(url.pathComponents.dropFirst(4).first ?? "") there yet.")
        case let code: throw FetchError("server said \(code).")
        }
    }

    // MARK: Parsing (pure, covered by Checks)

    static func schedule(tba data: Data) throws -> [ScheduledMatch] {
        try JSONDecoder().decode([TBAMatch].self, from: data).compactMap { m in
            let (type, match): (MatchType, Int)
            switch m.comp_level {
            case "qm": (type, match) = (.qual, m.match_number)
            case "sf": (type, match) = (.playoff, m.set_number)        // double elimination, 1-13
            case "f": (type, match) = (.playoff, 13 + m.match_number)  // finals become 14-16
            default: return nil
            }
            return ScheduledMatch(type: type, match: match,
                                  red: (m.alliances["red"]?.team_keys ?? []).map(number),
                                  blue: (m.alliances["blue"]?.team_keys ?? []).map(number))
        }
    }

    static func schedule(nexus status: NexusStatus) -> [ScheduledMatch] {
        status.matches.compactMap { m in
            let words = m.label.split(separator: " ")
            guard words.count == 2, let n = Int(words[1]) else { return nil }   // skips "... Replay"
            let (type, match): (MatchType, Int)
            switch words[0] {
            case "Practice": (type, match) = (.practice, n)
            case "Qualification": (type, match) = (.qual, n)
            case "Playoff": (type, match) = (.playoff, n)
            case "Final": (type, match) = (.playoff, 13 + n)
            default: return nil
            }
            return ScheduledMatch(type: type, match: match,
                                  red: (m.redTeams ?? []).map { Int($0 ?? "") ?? 0 },
                                  blue: (m.blueTeams ?? []).map { Int($0 ?? "") ?? 0 })
        }
    }

    /// Newer source wins per match; play order: practice, quals, playoffs.
    static func merge(_ old: [ScheduledMatch], _ new: [ScheduledMatch]) -> [ScheduledMatch] {
        let order = { (m: ScheduledMatch) in (MatchType.allCases.firstIndex(of: m.type) ?? 0, m.match) }
        var byMatch = Dictionary(old.map { (order($0).0 * 1000 + $0.match, $0) }) { a, _ in a }
        for m in new { byMatch[order(m).0 * 1000 + m.match] = m }
        return byMatch.values.sorted { order($0) < order($1) }
    }

    /// "frc1678" → 1678, "frc1678B" → 1678.
    static func number(_ teamKey: String) -> Int { Int(teamKey.filter(\.isNumber)) ?? 0 }
}

struct TBAMatch: Decodable {
    let comp_level: String
    let set_number: Int
    let match_number: Int
    let alliances: [String: TBAAlliance]
}
struct TBAAlliance: Decodable { let team_keys: [String] }
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
