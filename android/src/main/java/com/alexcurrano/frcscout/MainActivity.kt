package com.alexcurrano.frcscout

import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = AppState(applicationContext)
        if (app.code.isEmpty() || app.event.isEmpty()) app.tab = "setup"
        setContent {
            MaterialTheme(colorScheme = scoutColors) {
                val session = remember { MatchSession(app) }
                val scope = rememberCoroutineScope()
                val toast = { text: String -> Toast.makeText(this, text, Toast.LENGTH_SHORT).show() }
                // Other devices' scouting every 20 s; schedule, rankings, and EPA every 5 minutes and at launch.
                LaunchedEffect(Unit) {
                    var tick = 0
                    while (true) {
                        app.sync()   // first, so picking "the next match" knows what teammates already scouted
                        if (tick % 15 == 0) { app.refreshEvent(); if (session.crew.none { it.hasData }) session.snap(); session.autofill() }
                        tick++
                        delay(20_000)
                    }
                }
                Scaffold(containerColor = C.page, bottomBar = {
                    NavigationBar(containerColor = Color.White) {
                        listOf("match" to "🔭  Match", "pit" to "🔧  Pit", "teams" to "📋  Teams", "setup" to "⚙️  Setup").forEach { (key, label) ->
                            NavigationBarItem(selected = app.tab == key, onClick = { app.tab = key },
                                icon = { Text(label.substringBefore(" ")) }, label = { Text(label.substringAfter("  ")) },
                                colors = NavigationBarItemDefaults.colors(selectedTextColor = C.accent, indicatorColor = C.accent.copy(alpha = .12f)))
                        }
                    }
                }) { pad ->
                    Box(Modifier.fillMaxSize().background(C.page).padding(pad)) {
                        val saved = { text: String -> toast(text); scope.launch { app.sync() }; Unit }
                        when (app.tab) {
                            "match" -> MatchScreen(app, session, saved)
                            "pit" -> PitScreen(app, saved)
                            "teams" -> TeamsScreen(app)
                            else -> SetupScreen(app, toast) { session.fresh() }
                        }
                    }
                }
            }
        }
    }
}
