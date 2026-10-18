package com.alexcurrano.frcscout

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch

/** The robot(s) being scouted right now: one, or all six in the match, each its own record. */
class MatchSession(private val app: AppState) {
    var whole by mutableStateOf(false)
    var station by mutableIntStateOf(0)
    var type by mutableStateOf("Qual")
    val crew = mutableStateListOf<MatchRecord>()
    var current by mutableIntStateOf(0)
    private val seats = mutableMapOf<Int, MatchRecord>()   // one-robot mode: each seat keeps its own record

    val r: MatchRecord get() = crew[current.coerceIn(0, crew.size - 1)]
    fun set(change: (MatchRecord) -> MatchRecord) { crew[current.coerceIn(0, crew.size - 1)] = change(r).copy(date = now()) }
    fun schedule(): List<Scheduled> = app.info?.schedule?.filter { it.type == type }?.sortedBy { it.match } ?: emptyList()

    fun fresh(match: Int = 0) {
        crew.clear()
        repeat(if (whole) 6 else 1) { i -> crew.add(MatchRecord(type = type, match = match, alliance = if ((if (whole) i else station) < 3) "Red" else "Blue")) }
        current = if (whole) station else 0
        seats.clear()
        snap(); autofill()
    }
    fun setMatch(v: Int) { for (i in crew.indices) crew[i] = crew[i].copy(match = v); seats.clear(); autofill() }
    fun changeType(t: String) { type = t; for (i in crew.indices) crew[i] = crew[i].copy(type = t); snap(); autofill() }

    /** With a schedule, only real matches: the next one after what's been scouted, by default. */
    fun snap() {
        val list = schedule()
        if (list.isEmpty() || crew.isEmpty() || list.any { it.match == r.match }) return
        val scouted = app.db.matches.filter { it.event == app.event && it.type == type }.maxOfOrNull { it.match } ?: 0
        val target = if (r.match > 0) r.match else scouted + 1
        setMatch((list.firstOrNull { it.match >= target } ?: list.last()).match)
    }
    fun autofill() {
        if (crew.isEmpty()) return
        val m = app.info?.schedule?.firstOrNull { it.type == type && it.match == r.match } ?: return
        val teams = m.red + m.blue
        if (whole) crew.indices.forEach { i -> teams.getOrNull(i)?.takeIf { it > 0 }?.let { crew[i] = crew[i].copy(team = it) } }
        else teams.getOrNull(station)?.takeIf { it > 0 }?.let { crew[current] = r.copy(team = it) }
    }
    fun switchSeat(i: Int) {
        seats[station] = r
        station = i
        crew[0] = seats[i] ?: MatchRecord(type = type, match = r.match, alliance = if (i < 3) "Red" else "Blue")
        autofill()
    }
    fun save(): List<MatchRecord> {
        val list = crew.filter { it.team > 0 && (!whole || it.hasData) }.map {
            it.copy(event = app.event, scout = app.name, date = now(), alliance = if (whole) it.alliance else if (station < 3) "Red" else "Blue")
        }
        app.saveMatches(list)
        fresh(r.match + 1)   // then snaps to the next real match when there's a schedule
        return list
    }
    /** What we know about a team: pit data yet, and how often it's been match scouted here. */
    fun status(team: Int): List<Pair<String, Color?>> {
        if (team == 0) return emptyList()
        val n = app.db.matches.count { it.event == app.event && it.team == team }
        return listOfNotNull(
            if (app.db.pits.none { it.team == team }) "No pit data" to C.amber else null,
            if (n == 0) "First match" to C.tele else "$n match${if (n == 1) "" else "es"}" to null,
        )
    }
}

@Composable
fun MatchScreen(app: AppState, s: MatchSession, toast: (String) -> Unit) {
    if (s.crew.isEmpty()) s.fresh()
    val m = s.r
    val multi = s.whole
    val seat = seatName(if (multi) s.current else s.station)
    val scroll = rememberScrollState()
    val scope = rememberCoroutineScope()
    Column(Modifier.verticalScroll(scroll).padding(horizontal = 16.dp, vertical = 12.dp)) {
        H1("Match scouting")
        Header(app, s, m, seat)
        if (multi) RobotGrid(s)
        if (m.type == "Playoff") PlayoffForm(s, m) else ScoutingForm(s, m, multi)
        val toSave = s.crew.filter { it.team > 0 && (!multi || it.hasData) }
        val can = m.match > 0 && toSave.isNotEmpty()
        Box(Modifier.fillMaxWidth().padding(top = 8.dp).heightIn(min = 60.dp).clip(RoundedCornerShape(18.dp)).background(if (can) C.fuel else C.fuel.copy(alpha = .45f))
            .clickable(enabled = can) {
                val saved = s.save()
                toast("Saved ${saved.joinToString { it.team.toString() }}")
                scope.launch { scroll.animateScrollTo(0) }   // the next match starts at the top
            }, contentAlignment = Alignment.Center) {
            Text(if (multi) "Save ${toSave.size} robot${if (toSave.size == 1) "" else "s"}" else "Save match", fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, color = C.navy)
        }
        var confirm by remember { mutableStateOf(false) }
        Text(if (confirm) "Tap again to clear $seat's answers" else "Clear $seat's answers", color = C.red, fontWeight = FontWeight.SemiBold,
            modifier = Modifier.fillMaxWidth().padding(vertical = 14.dp).clickable {
                if (confirm) { s.set { MatchRecord(id = it.id, type = it.type, match = it.match, team = it.team, alliance = it.alliance) }; confirm = false } else confirm = true
            })
        Spacer(Modifier.height(80.dp))
    }
}

@Composable
private fun Header(app: AppState, s: MatchSession, m: MatchRecord, seat: String) {
    val info = app.info
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp))
        .background(Brush.linearGradient(listOf(C.fuel.copy(alpha = .38f), C.fuel.copy(alpha = .12f)))).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Column {
                Label("MATCH")
                val list = s.schedule()
                if (list.isEmpty()) NumberBox(m.match, 96) { s.setMatch(it) } else MatchPicker(s, list, m.match)
            }
            Column(Modifier.weight(1f)) {
                Label("TEAM · $seat")
                NumberBox(m.team, null) { v -> s.set { it.copy(team = v) } }
            }
            Column(horizontalAlignment = Alignment.End) {
                Text("${m.points}", fontSize = 40.sp, fontWeight = FontWeight.ExtraBold, color = C.navy)
                Label("PTS")
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(if (m.team == 0) (if (s.schedule().isEmpty()) "Type the match number" else "Pick the match") else info?.names?.get(m.team.toString()) ?: "Not on this event's list",
                fontWeight = FontWeight.Bold, fontSize = 15.sp)
            s.status(m.team).filter { it.second != null }.forEach { (t, c) -> Pill(t, c!!) }
        }
        Choice(TYPES.map { it to it }, m.type, base = Color.White) { s.changeType(it) }
        Choice(listOf(false to "One robot", true to "Whole match"), s.whole, C.navy, Color.White) { s.whole = it; s.fresh(m.match) }
        if (!s.whole) Choice((0..5).map { it to seatName(it) }, s.station, if (s.station < 3) C.red else C.blue, Color.White) { s.switchSeat(it) }
        if (!info?.nowQueuing.isNullOrEmpty()) Text("🕒 Now queuing: ${info!!.nowQueuing}", fontWeight = FontWeight.Bold, color = C.navy, fontSize = 13.sp)
    }
}

@Composable
private fun Label(text: String) = Text(text, fontSize = 11.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = 1.sp, color = C.muted)

@Composable
fun NumberBox(value: Int, width: Int?, onChange: (Int) -> Unit) {
    BasicTextField(value = if (value == 0) "" else value.toString(), onValueChange = { onChange(it.filter(Char::isDigit).take(5).toIntOrNull() ?: 0) },
        singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        textStyle = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.ExtraBold),
        modifier = (if (width != null) Modifier.width(width.dp) else Modifier.fillMaxWidth()).height(56.dp).clip(RoundedCornerShape(12.dp))
            .background(Color.White).padding(horizontal = 12.dp, vertical = 10.dp),
        decorationBox = { inner -> Box(contentAlignment = Alignment.CenterStart) { if (value == 0) Text("–", fontSize = 28.sp, color = C.muted); inner() } })
}

/** Only scheduled matches: arrows, or tap the number for the full list with each match's teams. */
@Composable
private fun MatchPicker(s: MatchSession, list: List<Scheduled>, match: Int) {
    val at = list.indexOfFirst { it.match == match }
    var open by remember { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text("‹", fontSize = 32.sp, fontWeight = FontWeight.ExtraBold, color = if (at > 0) C.navy else C.navy.copy(alpha = .25f),
            modifier = Modifier.clickable(enabled = at > 0) { s.setMatch(list[at - 1].match) }.padding(horizontal = 6.dp).semantics { contentDescription = "Previous match" })
        Box {
            Box(Modifier.width(72.dp).height(56.dp).clip(RoundedCornerShape(12.dp)).background(Color.White).clickable { open = true }, contentAlignment = Alignment.Center) {
                Text(if (match == 0) "–" else "$match", fontSize = 28.sp, fontWeight = FontWeight.ExtraBold)
            }
            DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                list.forEach { m -> DropdownMenuItem(text = { Text("${m.label}: ${m.red.joinToString(" ")} vs ${m.blue.joinToString(" ")}") }, onClick = { s.setMatch(m.match); open = false }) }
            }
        }
        Text("›", fontSize = 32.sp, fontWeight = FontWeight.ExtraBold, color = if (at in 0 until list.size - 1) C.navy else C.navy.copy(alpha = .25f),
            modifier = Modifier.clickable(enabled = at in 0 until list.size - 1) { s.setMatch(list[at + 1].match) }.padding(horizontal = 6.dp).semantics { contentDescription = "Next match" })
    }
}

@Composable
private fun RobotGrid(s: MatchSession) {
    Column(Modifier.padding(vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf(0, 3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                (row until row + 3).forEach { i ->
                    val c = s.crew[i]
                    val on = i == s.current
                    Column(Modifier.weight(1f).clip(RoundedCornerShape(14.dp)).background(Color.White)
                        .border(2.dp, if (on) C.seats[i] else Color.Transparent, RoundedCornerShape(14.dp)).clickable { s.current = i }.padding(8.dp)) {
                        Box(Modifier.size(26.dp).clip(CircleShape).background(C.seats[i]), contentAlignment = Alignment.Center) {
                            Text(seatName(i), color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.ExtraBold)
                        }
                        Text(if (c.team == 0) "–" else "${c.team}", fontSize = 17.sp, fontWeight = FontWeight.Bold)
                        Text(if (c.hasData) "${c.points} pts entered" else s.status(c.team).joinToString(" · ") { it.first }.ifEmpty { "–" },
                            fontSize = 11.sp, color = C.muted, maxLines = 1)
                    }
                }
            }
        }
    }
}

@Composable
private fun Problems(s: MatchSession, m: MatchRecord) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Toggle("Died / no-show", m.died, C.red, Modifier.weight(1f)) { s.set { it.copy(died = !it.died) } }
            Toggle("Tipped over", m.tipped, C.red, Modifier.weight(1f)) { s.set { it.copy(tipped = !it.tipped) } }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Toggle("E-stopped", m.eStopped, C.red, Modifier.weight(1f)) { s.set { it.copy(eStopped = !it.eStopped) } }
            Toggle("A-stopped", m.aStopped, C.auto, Modifier.weight(1f)) { s.set { it.copy(aStopped = !it.aStopped) } }
        }
        Toggle("Didn't shoot / drive only", m.noShoot, C.red) { s.set { it.copy(noShoot = !it.noShoot) } }
    }
}

private val towerOptions = listOf<Pair<Int?, String>>(null to "–", 0 to "None", 1 to "L1", 2 to "L2", 3 to "L3")
private val roleOptions = listOf<Pair<String?, String>>(null to "–") + ROLES.map { it to it }

@Composable
private fun ScoutingForm(s: MatchSession, m: MatchRecord, multi: Boolean) {
    Section("Auto", "⏱", C.auto, { s.set { it.copy(startPos = null, autoFuel = null, autoClimb = false, autoNeutral = false) } }) {
        Text("Where they started", fontWeight = FontWeight.Bold)
        Choice(listOf<Pair<String?, String>>(null to "–") + STARTS.map { it to it }, m.startPos, C.auto) { v -> s.set { it.copy(startPos = v) } }
        Counter("Fuel scored", m.autoFuel, listOf(1, 5), C.auto) { v -> s.set { it.copy(autoFuel = v) } }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Toggle("Climbed L1 · 15", m.autoClimb, C.auto, Modifier.weight(1f)) { s.set { it.copy(autoClimb = !it.autoClimb) } }
            Toggle("Neutral zone", m.autoNeutral, C.auto, Modifier.weight(1f)) { s.set { it.copy(autoNeutral = !it.autoNeutral) } }
        }
    }
    Section("Teleop", "🎮", C.tele, { s.set { it.copy(teleFuel = null, passes = null, role = null, shootsOnMove = false, shots = emptyList()) } }) {
        Muted("Count fuel into the ACTIVE hub only.")
        Counter("Fuel scored", m.teleFuel, listOf(1, 5, 10), C.tele) { v -> s.set { it.copy(teleFuel = v) } }
        Counter("Passes (volleys)", m.passes, listOf(1), C.tele) { v -> s.set { it.copy(passes = v) } }
        Text("Main role this match", fontWeight = FontWeight.Bold)
        Choice(roleOptions, m.role, C.tele) { v -> s.set { it.copy(role = v) } }
        Toggle("Shoots while moving", m.shootsOnMove, C.tele) { s.set { it.copy(shootsOnMove = !it.shootsOnMove) } }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Where they shoot from", fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            Muted("${m.shots.size} spots")
            SmallButton("Undo", m.shots.isNotEmpty()) { s.set { it.copy(shots = it.shots.dropLast(1)) } }
            SmallButton("Clear", m.shots.isNotEmpty()) { s.set { it.copy(shots = emptyList()) } }
        }
        if (multi) Choice(s.crew.indices.map { it to seatName(it) }, s.current, C.seats[s.current]) { s.current = it }
        ShotField(s.crew.mapIndexedNotNull { i, c ->
            if (multi || i == s.current) ShotSeries(c.shots, if (multi) C.seats[i] else C.fuel, if (multi) seatName(i) else "") else null
        }) { x, y -> s.set { it.copy(shots = it.shots + listOf(listOf((x * 1000).toInt() / 1000.0, (y * 1000).toInt() / 1000.0))) } }
    }
    Section("End game", "🏁", C.end, { s.set { it.copy(climb = null) } }) {
        Text("Tower at the end", fontWeight = FontWeight.Bold)
        Choice(towerOptions, m.climb, C.end) { v -> s.set { it.copy(climb = v) } }
    }
    Section("Problems", "⚠️", C.red, { s.set { it.copy(died = false, tipped = false, eStopped = false, aStopped = false, noShoot = false) } }) { Problems(s, m) }
    Section("Ratings", "⭐", C.accent, { s.set { it.copy(accuracy = 0, driver = 0, defense = 0) } }) {
        Rating("Accuracy", m.accuracy) { v -> s.set { it.copy(accuracy = v) } }
        Rating("Driver", m.driver) { v -> s.set { it.copy(driver = v) } }
        Rating("Defense (blank if they didn't)", m.defense) { v -> s.set { it.copy(defense = v) } }
    }
    Section("Notes", "💬", Color(0xFF8E8E93), { s.set { it.copy(notes = "") } }) {
        OutlinedTextField(m.notes, { v -> s.set { it.copy(notes = v) } }, Modifier.fillMaxWidth(), placeholder = { Text("Playstyle, weaknesses, breaks…") }, minLines = 3)
    }
}

@Composable
private fun PlayoffForm(s: MatchSession, m: MatchRecord) {
    Section("Playoff quick form", "🏆", C.end, {
        s.set { it.copy(role = null, climb = null, died = false, tipped = false, eStopped = false, aStopped = false, noShoot = false, defense = 0, teleFuel = null) }
    }) {
        Text("Role they played", fontWeight = FontWeight.Bold)
        Choice(roleOptions, m.role, C.end) { v -> s.set { it.copy(role = v) } }
        Text("Tower", fontWeight = FontWeight.Bold)
        Choice(towerOptions, m.climb, C.end) { v -> s.set { it.copy(climb = v) } }
        Problems(s, m)
        Rating("Defense", m.defense, C.end) { v -> s.set { it.copy(defense = v) } }
        Counter("Fuel scored (optional)", m.teleFuel, listOf(1, 5, 10), C.end) { v -> s.set { it.copy(teleFuel = v) } }
    }
    Section("For the strategists", "💬", Color(0xFF8E8E93), { s.set { it.copy(weaknesses = "", breaks = "", notes = "") } }) {
        OutlinedTextField(m.weaknesses, { v -> s.set { it.copy(weaknesses = v) } }, Modifier.fillMaxWidth(), label = { Text("Weaknesses we can use") }, minLines = 2)
        OutlinedTextField(m.breaks, { v -> s.set { it.copy(breaks = v) } }, Modifier.fillMaxWidth(), label = { Text("Breaks or surprises") }, minLines = 2)
        OutlinedTextField(m.notes, { v -> s.set { it.copy(notes = v) } }, Modifier.fillMaxWidth(), label = { Text("Defense and strategy notes") }, minLines = 2)
    }
}
