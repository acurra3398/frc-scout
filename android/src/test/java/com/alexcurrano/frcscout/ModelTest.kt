package com.alexcurrano.frcscout

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// ./gradlew test — the Android app must read and write exactly what the iPad and web apps do.
class ModelTest {
    // Shaped like a record the iPad wrote (Swift leaves out blank numbers; dates are seconds since 2001).
    private val fromIPad = """{"eStopped":false,"alliance":"Blue","tipped":false,"autoNeutral":false,"aStopped":false,"scout":"Bovine Intervention",
        "died":false,"autoFuel":0,"notes":"","noShoot":false,"type":"Qual","defense":1,"driver":2,"event":"2026mdbob","team":3748,"role":"Defense",
        "date":813935316.998032,"teleFuel":32,"match":1,"autoClimb":false,"accuracy":2,"id":"62F9F78A-8691-4718-AC2E-8A1AA5E031EE",
        "shootsOnMove":false,"startPos":"Center","breaks":"","climb":0,"weaknesses":"","shots":[[0.783,0.605]],"someFutureField":1}"""

    @Test fun readsIPadRecords() {
        val m = json.decodeFromString(MatchRecord.serializer(), fromIPad)
        assertEquals(3748, m.team); assertEquals(0, m.autoFuel); assertEquals(32, m.teleFuel); assertNull(m.passes)
        assertEquals("Defense", m.role); assertEquals(813935316.998032, m.date, 0.0001); assertEquals(32, m.points)
    }

    @Test fun writesBlanksTheWayTheIPadDoes() {
        val out = json.encodeToString(MatchRecord.serializer(), MatchRecord(team = 1, autoFuel = 0))
        assertTrue(out.contains("\"autoFuel\":0")); assertFalse(out.contains("teleFuel")); assertFalse(out.contains("null"))
        assertEquals(MatchRecord(id = "X", team = 1, autoFuel = 0, date = 5.0),
            json.decodeFromString(MatchRecord.serializer(), json.encodeToString(MatchRecord.serializer(), MatchRecord(id = "X", team = 1, autoFuel = 0, date = 5.0))))
    }

    @Test fun newerEditWins() {
        val a = MatchRecord(id = "A", teleFuel = 10, date = 10.0)
        val merged = mergeList(listOf(a), listOf(a.copy(teleFuel = 1, date = 5.0), MatchRecord(id = "B", date = 1.0)), { it.id }, { it.date })
        assertEquals(10, merged.first { it.id == "A" }.teleFuel); assertEquals(2, merged.size)
        assertEquals(20, mergeList(merged, listOf(a.copy(teleFuel = 20, date = 11.0)), { it.id }, { it.date }).first { it.id == "A" }.teleFuel)
    }

    @Test fun zeroIsNotBlank() {
        val db = Db(matches = listOf(MatchRecord(event = "e", team = 5, autoFuel = 0, teleFuel = 0, climb = 0)),
            info = EventInfo(key = "e", names = mapOf("5" to "Zero", "6" to "Unscouted")))
        val s = stats(db, "e")
        assertEquals(0.0, s.first { it.team == 5 }.points!!, 0.0); assertNull(s.first { it.team == 6 }.points)
        assertEquals("0.0", f1(0.0)); assertEquals("–", f1(null))
    }
}
