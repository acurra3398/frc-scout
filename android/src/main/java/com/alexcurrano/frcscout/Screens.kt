package com.alexcurrano.frcscout

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.time.LocalDate
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

private val gray = Color(0xFF8E8E93)

@Composable
private fun ListRow(onClick: () -> Unit, content: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp).clip(RoundedCornerShape(16.dp)).background(C.card).clickable(onClick = onClick)
        .padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) { content() }
}

@Composable
private fun Num(label: String, value: Int, onChange: (Int) -> Unit) {
    OutlinedTextField(if (value == 0) "" else "$value", { onChange(it.filter(Char::isDigit).take(4).toIntOrNull() ?: 0) }, Modifier.fillMaxWidth(),
        label = { Text(label) }, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
}

// ---------- pit ----------

@Composable
fun PitScreen(app: AppState, toast: (String) -> Unit) {
    var open by remember { mutableStateOf<PitRecord?>(null) }
    var todoOnly by remember { mutableStateOf(false) }
    open?.let { draft ->
        BackHandler { open = null }
        PitForm(app, draft, { open = it }) { app.savePit(it); toast("Saved pit · ${it.team}"); open = null }
        return
    }
    val info = app.info
    val teams = ((info?.names?.keys?.mapNotNull { it.toIntOrNull() } ?: emptyList()) + app.db.pits.map { it.team }).toSortedSet().toList()
    val done = teams.count { t -> app.db.pits.any { it.team == t } }
    var typed by remember { mutableStateOf(0) }
    Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 12.dp)) {
        H1("Pit scouting")
        Card {
            Text("$done of ${teams.size} pit scouted", fontWeight = FontWeight.Bold)
            LinearProgressIndicator(progress = { if (teams.isEmpty()) 0f else done / teams.size.toFloat() }, Modifier.fillMaxWidth(), color = C.green)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.weight(1f)) { Num("Team number", typed) { typed = it } }
                SmallButton("Open", typed > 0) { open = app.db.pits.firstOrNull { it.team == typed } ?: PitRecord(team = typed) }
            }
            Toggle("To do only", todoOnly, C.navy) { todoOnly = !todoOnly }
        }
        if (teams.isEmpty()) Muted("Pick your event in Setup to list every team.")
        teams.filter { t -> !todoOnly || app.db.pits.none { it.team == t } }.forEach { t ->
            val p = app.db.pits.firstOrNull { it.team == t }
            ListRow({ open = p ?: PitRecord(team = t) }) {
                Text("$t", fontSize = 22.sp, fontWeight = FontWeight.ExtraBold)
                Text(info?.names?.get("$t") ?: "", color = C.muted, maxLines = 1, modifier = Modifier.weight(1f))
                if (p != null) Badge(p.robustness) else Muted("To do")
            }
        }
        Spacer(Modifier.height(80.dp))
    }
}

@Composable
private fun PitForm(app: AppState, p: PitRecord, edit: (PitRecord) -> Unit, save: (PitRecord) -> Unit) {
    val rubric = listOf("–", "1 · Expect it to fail; likely DNP", "2 · Looks unreliable, maybe fixable", "3 · Normal robot, fine for elims",
        "4 · Sturdy and well built", "5 · Looks indestructible")
    Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 12.dp)) {
        H1("${p.team}${app.info?.names?.get("${p.team}")?.let { " · $it" } ?: ""}")
        Section("Robustness (1678 rubric)", "🛠", gray) {
            Choice((0..5).map { it to if (it == 0) "–" else "$it" }, p.robustness, C.robust(p.robustness)) { edit(p.copy(robustness = it)) }
            Muted(rubric[p.robustness])
        }
        Section("Drivetrain", "🚗", gray) {
            Choice(listOf("Swerve", "Tank", "Mecanum", "Other").map { it to it }, p.drivetrain) { edit(p.copy(drivetrain = it)) }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Toggle("Under trench", p.trench, modifier = Modifier.weight(1f)) { edit(p.copy(trench = !p.trench)) }
                Toggle("Over the bump", p.bump, modifier = Modifier.weight(1f)) { edit(p.copy(bump = !p.bump)) }
            }
        }
        Section("Intake", "🟡", C.auto) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Toggle("Floor", p.floorIntake, modifier = Modifier.weight(1f)) { edit(p.copy(floorIntake = !p.floorIntake)) }
                Toggle("Outpost", p.outpostIntake, modifier = Modifier.weight(1f)) { edit(p.copy(outpostIntake = !p.outpostIntake)) }
                Toggle("Depot", p.depotIntake, modifier = Modifier.weight(1f)) { edit(p.copy(depotIntake = !p.depotIntake)) }
            }
            Num("Fuel it holds (count it yourself)", p.hopper) { edit(p.copy(hopper = it)) }
        }
        Section("Shooting", "🎯", C.tele) {
            Muted("Range")
            Choice(listOf(0 to "?", 1 to "At hub", 2 to "Our zone", 3 to "Neutral"), p.range, C.tele) { edit(p.copy(range = it)) }
            Num("Shot rate (fuel / second, claimed)", p.shotRate) { edit(p.copy(shotRate = it)) }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Toggle("Turret", p.turret, modifier = Modifier.weight(1f)) { edit(p.copy(turret = !p.turret)) }
                Toggle("Shoots moving", p.shootsOnMove, modifier = Modifier.weight(1f)) { edit(p.copy(shootsOnMove = !p.shootsOnMove)) }
            }
            Toggle("Passes fuel from midfield to its side", p.canPass) { edit(p.copy(canPass = !p.canPass)) }
        }
        Section("Tower", "🏁", C.end) {
            Choice((0..3).map { it to if (it == 0) "None" else "L$it" }, p.maxClimb, C.end) { edit(p.copy(maxClimb = it)) }
            Num("Seconds to climb", p.climbSeconds) { edit(p.copy(climbSeconds = it)) }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Toggle("Climbs on side", p.sideClimb, modifier = Modifier.weight(1f)) { edit(p.copy(sideClimb = !p.sideClimb)) }
                Toggle("L1 in auto", p.autoClimb, modifier = Modifier.weight(1f)) { edit(p.copy(autoClimb = !p.autoClimb)) }
            }
        }
        Section("Auto", "⏱", C.auto) {
            Num("Autos they can run", p.autoCount) { edit(p.copy(autoCount = it)) }
            Num("Fuel in their best auto", p.autoFuelClaim) { edit(p.copy(autoFuelClaim = it)) }
            Toggle("Goes to the neutral zone", p.autoNeutral) { edit(p.copy(autoNeutral = !p.autoNeutral)) }
            Muted("How often their auto works")
            Choice(listOf(0 to "?", 1 to "Rarely", 2 to "Half", 3 to "Most", 4 to "Every"), p.autoConsistency) { edit(p.copy(autoConsistency = it)) }
        }
        Section("Team", "👥", gray) {
            Muted("Role they want")
            Choice(ROLES.map { it to it }, p.role) { edit(p.copy(role = it)) }
            Muted("Driver experience")
            Choice(listOf(0 to "?", 1 to "1st yr", 2 to "2nd yr", 3 to "3+ yrs"), p.driverYears) { edit(p.copy(driverYears = it)) }
        }
        Section("Notes", "💬", gray) {
            OutlinedTextField(p.worries, { edit(p.copy(worries = it)) }, Modifier.fillMaxWidth(), label = { Text("What's broken or worrying them?") }, minLines = 2)
            OutlinedTextField(p.notes, { edit(p.copy(notes = it)) }, Modifier.fillMaxWidth(), label = { Text("Architecture, autos, anything odd") }, minLines = 2)
        }
        Box(Modifier.fillMaxWidth().padding(top = 8.dp).height(60.dp).clip(RoundedCornerShape(18.dp)).background(C.fuel).clickable { save(p) },
            contentAlignment = Alignment.Center) { Text("Save pit record", fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, color = C.navy) }
        Spacer(Modifier.height(80.dp))
    }
}

// ---------- teams ----------

@Composable
fun TeamsScreen(app: AppState) {
    var open by remember { mutableStateOf<Int?>(null) }
    var sort by remember { mutableStateOf("points") }
    var unscouted by remember { mutableStateOf(false) }
    open?.let { team ->
        BackHandler { open = null }
        TeamDetail(app, team)
        return
    }
    val key = { t: TeamStats -> when (sort) { "epa" -> t.epa; "tower" -> t.tower ?: -1.0; "rank" -> -(if (t.rank == 0) 999 else t.rank).toDouble(); "team" -> -t.team.toDouble(); else -> t.points ?: -1.0 } }
    val rows = stats(app.db, app.event).filter { !unscouted || it.matches == 0 }.sortedByDescending(key)
    Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 12.dp)) {
        H1("Teams")
        Choice(listOf("points" to "Points", "epa" to "EPA", "tower" to "Tower", "rank" to "Rank", "team" to "Team #"), sort, C.navy) { sort = it }
        Spacer(Modifier.height(8.dp))
        Toggle("Not scouted yet", unscouted, C.navy) { unscouted = !unscouted }
        if (rows.isEmpty()) Muted(if (unscouted) "Every team has been scouted at least once." else "Pick your event in Setup, or scout a match.")
        rows.forEach { s ->
            ListRow({ open = s.team }) {
                Column {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("${s.team}", fontSize = 22.sp, fontWeight = FontWeight.ExtraBold)
                        if (s.tier > 0) Text("  T${s.tier}", color = C.tiers[s.tier], fontWeight = FontWeight.ExtraBold, fontSize = 13.sp)
                    }
                    Text("${s.name}${if (s.matches > 0) " · ${s.matches}m" else " · not scouted"}", color = C.muted, fontSize = 13.sp, maxLines = 1)
                }
                Spacer(Modifier.weight(1f))
                Column(horizontalAlignment = Alignment.End) {
                    Text(when (sort) { "epa" -> f1(s.epa.takeIf { it > 0 }); "tower" -> f1(s.tower); "rank" -> if (s.rank == 0) "–" else "${s.rank}"; else -> f1(s.points) },
                        fontWeight = FontWeight.ExtraBold, fontSize = 17.sp)
                    Muted(when (sort) { "epa" -> "EPA"; "tower" -> "tower"; "rank" -> "rank"; else -> "pts" })
                }
                Badge(s.robust)
            }
        }
        Spacer(Modifier.height(80.dp))
    }
}

@Composable
private fun TeamDetail(app: AppState, team: Int) {
    val s = stats(app.db, app.event).firstOrNull { it.team == team }
    val all = app.db.matches.filter { it.team == team }.sortedByDescending { order(it.type, it.match) }
    val here = all.filter { it.event == app.event }
    val pit = app.db.pits.firstOrNull { it.team == team }
    val saved = app.db.prescouts.firstOrNull { it.team == team }
    var pre by remember(team) { mutableStateOf(saved ?: PreScout(team = team)) }
    val said = { m: MatchRecord -> listOf(m.weaknesses.takeIf { it.isNotEmpty() }?.let { "weakness: $it" }, m.breaks.takeIf { it.isNotEmpty() }?.let { "broke: $it" }, m.notes.takeIf { it.isNotEmpty() }).filterNotNull() }
    Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 12.dp)) {
        H1("$team${s?.name?.takeIf { it.isNotEmpty() }?.let { " · $it" } ?: ""}")
        Card {
            listOf(listOf("Avg points" to f1(s?.points), "Season EPA" to f1(s?.epa?.takeIf { it > 0 }), "OPR" to f1(s?.opr?.takeIf { it != 0.0 })),
                listOf("Auto fuel" to f1(s?.auto), "Tele fuel" to f1(s?.tele), "Tower" to f1(s?.tower)),
                listOf("Rank" to (s?.rank?.takeIf { it > 0 }?.toString() ?: "–"), "Died" to (s?.died?.let { "${(it * 100).toInt()}%" } ?: "–"), "Robust" to (pit?.robustness?.takeIf { it > 0 }?.toString() ?: "–")))
                .forEach { row -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { row.forEach { (l, v) -> Tile(l, v, Modifier.weight(1f)) } } }
        }
        Section("Pre-scout", "🔭", C.tiers[pre.tier]) {
            Choice(TIERS.indices.map { it to if (it == 0) "–" else "T$it" }, pre.tier, C.tiers[pre.tier]) { pre = pre.copy(tier = it) }
            Muted(TIERS[pre.tier])
            OutlinedTextField(pre.notes, { pre = pre.copy(notes = it) }, Modifier.fillMaxWidth(), placeholder = { Text("What did you see in videos, TBA, or past events?") }, minLines = 2)
            if (pre.tier != (saved?.tier ?: 0) || pre.notes != (saved?.notes ?: "")) SmallButton("Save pre-scout") { app.savePre(pre) }
        }
        if (pit != null) Section("Pit", "🔧", gray) {
            Muted(listOfNotNull(pit.drivetrain, pit.hopper.takeIf { it > 0 }?.let { "holds $it" }, pit.maxClimb.takeIf { it > 0 }?.let { "climbs L$it" },
                "turret".takeIf { pit.turret }, "passes".takeIf { pit.canPass }).joinToString(" · "))
            if (pit.worries.isNotEmpty()) Text("⚠️ ${pit.worries}")
            if (pit.notes.isNotEmpty()) Text(pit.notes)
        }
        Section("Matches", "📋", gray) {
            if (here.isEmpty()) Muted("Not scouted yet at this event.")
            here.forEach { m ->
                Column {
                    Text("${m.type} ${m.match} · ${m.alliance} · ${m.points} pts", fontWeight = FontWeight.Bold)
                    Muted("auto ${m.autoFuel ?: "–"} · tele ${m.teleFuel ?: "–"} · ${m.climb?.let { if (it == 0) "no climb" else "L$it" } ?: "climb –"}" +
                        (if (m.died) " · DIED" else "") + (if (m.eStopped) " · E-STOP" else "") + (if (m.noShoot) " · NO SHOTS" else ""))
                    said(m).forEach { Text(it) }
                    Muted(m.scout)
                }
            }
        }
        val elsewhere = all.filter { it.event != app.event }.groupBy { it.event }
        if (elsewhere.isNotEmpty()) Section("Other events", "🕘", gray) {
            elsewhere.forEach { (key, list) ->
                Text(app.db.eventNames[key]?.let { "$it ($key)" } ?: key, fontWeight = FontWeight.Bold)
                val scored = list.filter { it.hasData }
                Muted("${list.size} matches scouted · ${f1(if (scored.isEmpty()) null else scored.sumOf { it.points }.toDouble() / scored.size)} avg pts")
                list.forEach { m -> said(m).forEach { Text("${m.label}: $it") } }
            }
        }
        Spacer(Modifier.height(80.dp))
    }
}

// ---------- setup ----------

@Composable
fun SetupScreen(app: AppState, toast: (String) -> Unit, onEventChosen: () -> Unit) {
    val scope = rememberCoroutineScope()
    var events by remember { mutableStateOf<List<JsonObject>?>(null) }
    var search by remember { mutableStateOf("") }
    val str = { o: JsonObject, k: String -> o[k]?.jsonPrimitive?.contentOrNull ?: "" }
    fun choose(key: String, name: String) {
        app.chooseEvent(key, name); events = null; onEventChosen()
        toast("Event: ${name.ifEmpty { key }}")
        scope.launch { app.refreshEvent(); app.sync() }
    }
    Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 12.dp)) {
        H1("Setup")
        Card {
            OutlinedTextField(app.name, { app.name = it }, Modifier.fillMaxWidth(), label = { Text("Your name") }, singleLine = true)
            OutlinedTextField(app.code, { app.code = it.trim() }, Modifier.fillMaxWidth(), label = { Text("Team code (ask your lead scout)") }, singleLine = true,
                visualTransformation = PasswordVisualTransformation())
            Num("Our team number", app.ourTeam) { app.changeOurTeam(it) }
            Muted(if (app.event.isEmpty()) "No event picked yet." else "Event: ${app.eventName.ifEmpty { app.event }} (${app.event})")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.weight(1f)) {
                    SmallButton("Find our event") {
                        if (app.code.isEmpty() || app.ourTeam == 0) toast("Enter the team code and your team number first.") else scope.launch {
                            runCatching { app.events() }.onSuccess { (mine, _) ->
                                val today = LocalDate.now().toString()
                                val e = mine.firstOrNull { str(it, "start_date") <= today && today <= str(it, "end_date") }
                                    ?: mine.firstOrNull { str(it, "start_date") > today } ?: mine.lastOrNull()
                                if (e != null) choose(str(e, "key"), str(e, "name")) else toast("No events this year for team ${app.ourTeam}.")
                            }.onFailure { toast(it.message ?: "Couldn't reach the server") }
                        }
                    }
                }
                Box(Modifier.weight(1f)) {
                    SmallButton("Pick an event") {
                        if (app.code.isEmpty()) toast("Enter the team code first.") else scope.launch {
                            runCatching { app.events().second }.onSuccess { events = it }.onFailure { toast(it.message ?: "Couldn't reach the server") }
                        }
                    }
                }
            }
        }
        events?.let { list ->
            Card {
                OutlinedTextField(search, { search = it }, Modifier.fillMaxWidth(), placeholder = { Text("Search events") }, singleLine = true)
                list.filter { search.isEmpty() || "${str(it, "name")} ${str(it, "key")} ${str(it, "city")}".contains(search, ignoreCase = true) }.take(40).forEach { e ->
                    Column(Modifier.fillMaxWidth().clickable { choose(str(e, "key"), str(e, "name")) }.padding(vertical = 8.dp)) {
                        Text(str(e, "name"), fontWeight = FontWeight.Bold)
                        Muted("${str(e, "key")} · ${str(e, "start_date")}")
                    }
                }
            }
        }
        val mine = app.db.matches.map { it.event }.filter { it.isNotEmpty() }.toSortedSet()
        if (mine.isNotEmpty()) Card {
            Text("Events on this phone", fontSize = 19.sp, fontWeight = FontWeight.Bold)
            Muted("Scouting from every competition stays here. Tap one to look at it again.")
            mine.forEach { key ->
                Row(Modifier.fillMaxWidth().clickable(enabled = key != app.event) { choose(key, app.db.eventNames[key] ?: "") }.padding(vertical = 8.dp)) {
                    Column(Modifier.weight(1f)) { Text(app.db.eventNames[key] ?: key, fontWeight = FontWeight.Bold); Muted(key) }
                    Muted(if (key == app.event) "current" else "${app.db.matches.count { it.event == key }} matches")
                }
            }
        }
        Card {
            Text("Sync", fontSize = 19.sp, fontWeight = FontWeight.Bold)
            Muted("Last sync: ${app.syncStatus}. Every save syncs right away, and the app checks for other devices' scouting every 20 seconds.")
            Muted("${app.db.matches.count { it.event == app.event }} match records · ${app.db.pits.size} pit records · " +
                "${app.db.dirtyMatches.size + app.db.dirtyPits.size + app.db.dirtyPre.size} waiting to upload")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.weight(1f)) { SmallButton("Sync now") { scope.launch { toast(if (app.sync()) "Synced" else "Sync failed: ${app.syncStatus}") } } }
                Box(Modifier.weight(1f)) { SmallButton("Refresh event data") { scope.launch { toast(app.refreshEvent()) } } }
            }
        }
        Spacer(Modifier.height(80.dp))
    }
}
