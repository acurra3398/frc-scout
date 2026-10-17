package com.alexcurrano.frcscout

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

const val SERVER = "https://frc-scout-one.vercel.app"

/** Everything the app knows, saved to the phone on every change. Settings live in SharedPreferences. */
class AppState(context: Context) {
    private val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
    private val file = File(context.filesDir, "scout.json")

    var name by pref("name"); var code by pref("code"); var event by pref("event"); var eventName by pref("eventName")
    var ourTeam by mutableStateOf(prefs.getInt("ourTeam", 0)); private set
    var tab by mutableStateOf("match")
    var syncStatus by mutableStateOf("not yet")
    var db by mutableStateOf(load()); private set

    fun changeOurTeam(v: Int) { ourTeam = v; prefs.edit().putInt("ourTeam", v).apply() }

    private fun pref(key: String) = object {
        private var state = mutableStateOf(prefs.getString(key, "") ?: "")
        operator fun getValue(owner: Any?, p: Any?): String = state.value
        operator fun setValue(owner: Any?, p: Any?, v: String) { state.value = v; prefs.edit().putString(key, v).apply() }
    }

    private fun load(): Db = try {
        if (file.exists()) json.decodeFromString(Db.serializer(), file.readText()) else Db()
    } catch (e: Exception) {
        // Never overwrite data we couldn't read: set it aside so it can be recovered.
        file.renameTo(File(file.parentFile, "scout.unreadable-${System.currentTimeMillis()}.json"))
        Db()
    }

    fun update(change: (Db) -> Db) {
        db = change(db)
        val tmp = File(file.parentFile, "scout.json.tmp")
        tmp.writeText(json.encodeToString(Db.serializer(), db))
        tmp.renameTo(file)   // atomic replace, so a crash mid-write can't corrupt the save
    }

    val info get() = db.info?.takeIf { it.key == event }

    fun saveMatches(list: List<MatchRecord>) = update { d ->
        d.copy(matches = mergeList(d.matches, list, { it.id }, { it.date }), dirtyMatches = d.dirtyMatches + list.map { it.id })
    }
    fun savePit(p: PitRecord) = update { d ->
        d.copy(pits = mergeList(d.pits, listOf(p.copy(updated = now())), { it.team }, { it.updated }), dirtyPits = d.dirtyPits + p.team)
    }
    fun savePre(p: PreScout) = update { d ->
        d.copy(prescouts = mergeList(d.prescouts, listOf(p.copy(updated = now())), { it.team }, { it.updated }), dirtyPre = d.dirtyPre + p.team)
    }

    // ---------- network (team server holds the TBA/Nexus keys; the team code unlocks it) ----------

    private suspend fun http(path: String, body: String? = null): String = withContext(Dispatchers.IO) {
        val conn = URL(SERVER + path).openConnection() as HttpURLConnection
        conn.connectTimeout = 15000; conn.readTimeout = 20000
        conn.setRequestProperty("x-team-code", code)
        conn.setRequestProperty("Content-Type", "application/json")
        if (body != null) { conn.requestMethod = "POST"; conn.doOutput = true; conn.outputStream.use { it.write(body.toByteArray()) } }
        val status = conn.responseCode
        val text = (if (status in 200..299) conn.inputStream else conn.errorStream)?.bufferedReader()?.readText() ?: ""
        if (status !in 200..299) {
            val message = runCatching { json.parseToJsonElement(text).jsonObject["error"]?.jsonPrimitive?.contentOrNull }.getOrNull()
            throw Exception(message ?: "server said $status")
        }
        text
    }
    private suspend fun tba(path: String) = json.parseToJsonElement(http("/api/tba?path=" + URLEncoder.encode(path, "UTF-8")))
    private suspend fun nexus(path: String) = json.parseToJsonElement(http("/api/nexus?path=" + URLEncoder.encode(path, "UTF-8")))
    private fun num(key: String) = key.filter { it.isDigit() }

    /** Names, schedule, rankings, OPR, season EPA, pits and the live queue for the event. */
    suspend fun refreshEvent(): String {
        val key = event
        if (key.isEmpty() || code.isEmpty()) return "Set the team code and event first."
        var i = info ?: EventInfo(key = key)
        val notes = mutableListOf<String>()
        try {
            val teams = tba("/event/$key/teams/simple").jsonArray.map { it.jsonObject }
            val schedule = tba("/event/$key/matches/simple").jsonArray.mapNotNull { fromTBA(it.jsonObject) }
            i = i.copy(names = teams.associate { it["team_number"]!!.jsonPrimitive.content to (it["nickname"]?.jsonPrimitive?.contentOrNull ?: "") },
                schedule = schedule)
            runCatching { tba("/event/$key/rankings").jsonObject["rankings"]!!.jsonArray }.getOrNull()?.let { ranks ->
                i = i.copy(rank = ranks.associate { num(it.jsonObject["team_key"]!!.jsonPrimitive.content) to it.jsonObject["rank"]!!.jsonPrimitive.intOrNull!! })
            }
            runCatching { tba("/event/$key/oprs").jsonObject["oprs"]!!.jsonObject }.getOrNull()?.let { oprs ->
                i = i.copy(opr = oprs.mapKeys { num(it.key) }.mapValues { it.value.jsonPrimitive.doubleOrNull ?: 0.0 })
            }
            notes += "${teams.size} teams, ${schedule.size} matches"
        } catch (e: Exception) { notes += "TBA: ${e.message}" }
        runCatching {
            val live = nexus("/event/$key").jsonObject
            val byMatch = i.schedule.associateBy { order(it.type, it.match) }.toMutableMap()
            live["matches"]!!.jsonArray.mapNotNull { fromNexus(it.jsonObject) }.forEach { byMatch[order(it.type, it.match)] = it }
            i = i.copy(nowQueuing = live["nowQueuing"]?.jsonPrimitive?.contentOrNull ?: "",
                schedule = byMatch.values.sortedBy { order(it.type, it.match) })
            runCatching { nexus("/event/$key/pits").jsonObject }.getOrNull()?.let { pits -> i = i.copy(pits = pits.mapValues { it.value.jsonPrimitive.content }) }
        }   // events that don't queue with Nexus just skip this
        runCatching {
            val epa = json.parseToJsonElement(http("/api/epa?year=${key.take(4)}")).jsonObject
            i = i.copy(epa = i.names.keys.mapNotNull { t -> epa[t]?.jsonPrimitive?.doubleOrNull?.let { t to it } }.toMap())
        }
        update { it.copy(info = i) }
        return notes.joinToString(" · ")
    }

    private fun fromTBA(m: JsonObject): Scheduled? {
        val n = m["match_number"]!!.jsonPrimitive.intOrNull ?: 0
        val set = m["set_number"]!!.jsonPrimitive.intOrNull ?: 0
        val (type, match) = when (m["comp_level"]!!.jsonPrimitive.content) {
            "qm" -> "Qual" to n; "sf" -> "Playoff" to set; "f" -> "Playoff" to 13 + n; else -> return null
        }
        val teams = { color: String -> m["alliances"]!!.jsonObject[color]!!.jsonObject["team_keys"]!!.jsonArray.map { num(it.jsonPrimitive.content).toIntOrNull() ?: 0 } }
        return Scheduled(type, match, teams("red"), teams("blue"))
    }

    private fun fromNexus(m: JsonObject): Scheduled? {
        val words = m["label"]!!.jsonPrimitive.content.split(" ")
        val n = words.getOrNull(1)?.toIntOrNull()
        if (words.size != 2 || n == null) return null   // replays and odd labels
        val type = mapOf("Practice" to "Practice", "Qualification" to "Qual", "Playoff" to "Playoff", "Final" to "Playoff")[words[0]] ?: return null
        val teams = { k: String -> (m[k] as? JsonArray)?.map { it.jsonPrimitive.contentOrNull?.toIntOrNull() ?: 0 } ?: emptyList() }
        return Scheduled(type, if (words[0] == "Final") 13 + n else n, teams("redTeams"), teams("blueTeams"))
    }

    /** Uploads what changed here and pulls what changed on other devices. Never deletes anything. */
    suspend fun sync(): Boolean {
        if (code.isEmpty() || event.isEmpty()) return false
        return try {
            val d = db
            val sent = Triple(d.dirtyMatches, d.dirtyPits, d.dirtyPre)
            val body = buildJsonObject {
                put("event", event); put("since", d.since)
                put("matches", json.encodeToJsonElement(ListSerializer(MatchRecord.serializer()), d.matches.filter { it.id in sent.first }))
                put("pits", json.encodeToJsonElement(ListSerializer(PitRecord.serializer()), d.pits.filter { it.team in sent.second }))
                put("prescouts", json.encodeToJsonElement(ListSerializer(PreScout.serializer()), d.prescouts.filter { it.team in sent.third }))
            }
            val out = json.parseToJsonElement(http("/api/sync", body.toString())).jsonObject
            val matches = json.decodeFromJsonElement(ListSerializer(MatchRecord.serializer()), out["matches"] ?: JsonArray(emptyList()))
            val pits = json.decodeFromJsonElement(ListSerializer(PitRecord.serializer()), out["pits"] ?: JsonArray(emptyList()))
            val pres = json.decodeFromJsonElement(ListSerializer(PreScout.serializer()), out["prescouts"] ?: JsonArray(emptyList()))
            update { cur ->
                cur.copy(
                    matches = mergeList(cur.matches, matches, { it.id }, { it.date }),
                    pits = mergeList(cur.pits, pits, { it.team }, { it.updated }),
                    prescouts = mergeList(cur.prescouts, pres, { it.team }, { it.updated }),
                    since = out["next"]?.jsonPrimitive?.doubleOrNull ?: cur.since,
                    // keep anything saved while this sync was in flight
                    dirtyMatches = cur.dirtyMatches - sent.first, dirtyPits = cur.dirtyPits - sent.second, dirtyPre = cur.dirtyPre - sent.third,
                )
            }
            syncStatus = "synced at " + LocalTime.now().format(DateTimeFormatter.ofPattern("h:mm a"))
            true
        } catch (e: Exception) {
            syncStatus = "failed (${e.message}). Everything is still saved on this phone."
            false
        }
    }

    /** This year's events: our team's own, and all of them for searching. */
    suspend fun events(): Pair<List<JsonObject>, List<JsonObject>> {
        val year = LocalDate.now().year
        val all = tba("/events/$year/simple").jsonArray.map { it.jsonObject }.sortedBy { it["start_date"]?.jsonPrimitive?.contentOrNull ?: "" }
        val mine = if (ourTeam > 0) runCatching { tba("/team/frc$ourTeam/events/$year/simple").jsonArray.map { it.jsonObject } }.getOrDefault(emptyList()) else emptyList()
        return mine.sortedBy { it["start_date"]?.jsonPrimitive?.contentOrNull ?: "" } to all
    }

    fun chooseEvent(key: String, name: String) {
        event = key
        eventName = name.ifEmpty { db.eventNames[key] ?: "" }
        update { it.copy(since = 0.0, eventNames = if (eventName.isEmpty()) it.eventNames else it.eventNames + (key to eventName)) }
    }
}
