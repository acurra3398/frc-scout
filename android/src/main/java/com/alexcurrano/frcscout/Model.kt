package com.alexcurrano.frcscout

import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

// Same JSON as the iPad and web apps, so all three sync through one server. Dates are seconds since
// 2001-01-01 (Swift's format), so every device agrees on which edit is newer. A null number means
// "not scored", which is different from a real 0.

val json = Json { ignoreUnknownKeys = true; explicitNulls = false; encodeDefaults = true; coerceInputValues = true }
fun now(): Double = System.currentTimeMillis() / 1000.0 - 978307200
fun newId(): String = UUID.randomUUID().toString().uppercase()

val TYPES = listOf("Practice", "Qual", "Playoff")
val STARTS = listOf("Depot", "Center", "Outpost")
val ROLES = listOf("Scorer", "Passer", "Defense", "Mixed")
val TOWER = listOf(0, 10, 20, 30)
val TIERS = listOf("–", "Tier 1 · elite", "Tier 2 · strong", "Tier 3 · solid", "Tier 4 · weak")
fun seatName(i: Int) = "${if (i < 3) "R" else "B"}${i % 3 + 1}"

@Serializable
data class MatchRecord(
    val id: String = newId(),
    val event: String = "",
    val scout: String = "",
    val type: String = "Qual",
    val match: Int = 0,
    val team: Int = 0,
    val alliance: String = "Red",
    val startPos: String? = null,
    val autoFuel: Int? = null,
    val autoClimb: Boolean = false,
    val autoNeutral: Boolean = false,
    val teleFuel: Int? = null,
    val passes: Int? = null,
    val shootsOnMove: Boolean = false,
    val role: String? = null,
    val shots: List<List<Double>> = emptyList(),
    val climb: Int? = null,
    val accuracy: Int = 0,
    val driver: Int = 0,
    val defense: Int = 0,
    val died: Boolean = false,
    val tipped: Boolean = false,
    val eStopped: Boolean = false,
    val aStopped: Boolean = false,
    val noShoot: Boolean = false,
    val weaknesses: String = "",
    val breaks: String = "",
    val notes: String = "",
    val date: Double = now(),
) {
    val towerPoints get() = (if (autoClimb) 15 else 0) + TOWER[(climb ?: 0).coerceIn(0, 3)]
    val points get() = (autoFuel ?: 0) + (teleFuel ?: 0) + towerPoints
    val hasData get() = listOf(autoFuel, teleFuel, passes, climb, startPos, role).any { it != null } ||
        autoClimb || autoNeutral || shootsOnMove || died || tipped || eStopped || aStopped || noShoot ||
        accuracy > 0 || driver > 0 || defense > 0 || shots.isNotEmpty() || notes.isNotEmpty() || weaknesses.isNotEmpty() || breaks.isNotEmpty()
    val label get() = "${when (type) { "Qual" -> "Q"; "Playoff" -> "P"; else -> "Pr" }}$match"
}

@Serializable
data class PitRecord(
    val team: Int = 0,
    val robustness: Int = 0,
    val drivetrain: String = "Swerve",
    val hopper: Int = 0,
    val trench: Boolean = false,
    val bump: Boolean = false,
    val maxClimb: Int = 0,
    val autoClimb: Boolean = false,
    val shootsOnMove: Boolean = false,
    val floorIntake: Boolean = false,
    val outpostIntake: Boolean = false,
    val depotIntake: Boolean = false,
    val turret: Boolean = false,
    val range: Int = 0,
    val shotRate: Int = 0,
    val canPass: Boolean = false,
    val climbSeconds: Int = 0,
    val sideClimb: Boolean = false,
    val autoCount: Int = 0,
    val autoFuelClaim: Int = 0,
    val autoNeutral: Boolean = false,
    val autoConsistency: Int = 0,
    val role: String = "Scorer",
    val driverYears: Int = 0,
    val worries: String = "",
    val notes: String = "",
    val updated: Double = now(),
)

@Serializable
data class PreScout(val team: Int = 0, val tier: Int = 0, val notes: String = "", val updated: Double = now())

@Serializable
data class Scheduled(val type: String = "Qual", val match: Int = 0, val red: List<Int> = emptyList(), val blue: List<Int> = emptyList()) {
    val label get() = "${when (type) { "Qual" -> "Q"; "Playoff" -> "P"; else -> "Pr" }}$match"
}

@Serializable
data class EventInfo(
    val key: String = "",
    val names: Map<String, String> = emptyMap(),
    val schedule: List<Scheduled> = emptyList(),
    val epa: Map<String, Double> = emptyMap(),
    val opr: Map<String, Double> = emptyMap(),
    val rank: Map<String, Int> = emptyMap(),
    val pits: Map<String, String> = emptyMap(),
    val nowQueuing: String = "",
)

/** Everything saved on this phone. `dirty*` = changed here and not uploaded yet. */
@Serializable
data class Db(
    val matches: List<MatchRecord> = emptyList(),
    val pits: List<PitRecord> = emptyList(),
    val prescouts: List<PreScout> = emptyList(),
    val info: EventInfo? = null,
    val since: Double = 0.0,
    val eventNames: Map<String, String> = emptyMap(),
    val dirtyMatches: Set<String> = emptySet(),
    val dirtyPits: Set<Int> = emptySet(),
    val dirtyPre: Set<Int> = emptySet(),
)

/** Newer edit wins; new records are added. */
fun <T> mergeList(list: List<T>, incoming: List<T>, key: (T) -> Any, date: (T) -> Double): List<T> {
    val out = list.toMutableList()
    for (r in incoming) {
        val i = out.indexOfFirst { key(it) == key(r) }
        if (i < 0) out.add(r) else if (date(r) > date(out[i])) out[i] = r
    }
    return out
}

fun order(type: String, match: Int) = TYPES.indexOf(type) * 1000 + match

data class TeamStats(
    val team: Int, val name: String, val matches: Int,
    val auto: Double?, val tele: Double?, val tower: Double?, val points: Double?, val passes: Double?,
    val died: Double?, val epa: Double, val opr: Double, val rank: Int, val robust: Int, val tier: Int,
)

private fun avg(xs: List<Int>): Double? = if (xs.isEmpty()) null else xs.sum().toDouble() / xs.size

/** Per-team averages; blanks stay out of each part's average, and unscouted teams have no numbers. */
fun stats(db: Db, event: String): List<TeamStats> {
    val info = db.info?.takeIf { it.key == event }
    val here = db.matches.filter { it.event == event }
    val teams = (here.map { it.team } + (info?.names?.keys?.mapNotNull { it.toIntOrNull() } ?: emptyList())).filter { it > 0 }.toSet()
    return teams.map { team ->
        val ms = here.filter { it.team == team }
        val auto = avg(ms.mapNotNull { it.autoFuel })
        val tele = avg(ms.mapNotNull { it.teleFuel })
        val tower = if (ms.isEmpty()) null else (avg(ms.map { if (it.autoClimb) 15 else 0 }) ?: 0.0) +
            (avg(ms.mapNotNull { m -> m.climb?.let { TOWER[it.coerceIn(0, 3)] } }) ?: 0.0)
        TeamStats(
            team = team, name = info?.names?.get(team.toString()) ?: "", matches = ms.size,
            auto = auto, tele = tele, tower = tower,
            points = if (ms.isEmpty()) null else (auto ?: 0.0) + (tele ?: 0.0) + (tower ?: 0.0),
            passes = avg(ms.mapNotNull { it.passes }),
            died = avg(ms.map { if (it.died) 1 else 0 }),
            epa = info?.epa?.get(team.toString()) ?: 0.0, opr = info?.opr?.get(team.toString()) ?: 0.0,
            rank = info?.rank?.get(team.toString()) ?: 0,
            robust = db.pits.firstOrNull { it.team == team }?.robustness ?: 0,
            tier = db.prescouts.firstOrNull { it.team == team }?.tier ?: 0,
        )
    }.sortedByDescending { it.points ?: -1.0 }
}

/** Scouted numbers: a dash only when never scouted; a real 0 shows as 0. */
fun f1(x: Double?) = if (x == null) "–" else String.format("%.1f", x)
