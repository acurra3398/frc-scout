package com.alexcurrano.frcscout

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// The icon's fuel yellow and navy, light only, a color per match phase (same as iPad and web).
object C {
    val fuel = Color(0xFFF5B731); val navy = Color(0xFF0F1729); val page = Color(0xFFF2F2F7); val card = Color.White
    val well = Color(0xFFE9E9EE); val muted = Color(0xFF6B6B72); val accent = Color(0xFFC2410C)
    val auto = Color(0xFFEA580C); val tele = Color(0xFF0D9488); val end = Color(0xFF4F46E5)
    val red = Color(0xFFD92121); val blue = Color(0xFF1F54DB); val green = Color(0xFF16A34A); val amber = Color(0xFFF59E0B)
    val seats = listOf(Color(0xFFD92121), Color(0xFFF97316), Color(0xFFEC4899), Color(0xFF1F54DB), Color(0xFF06B6D4), Color(0xFF6366F1))
    val tiers = listOf(Color(0xFF999999), green, tele, amber, red)
    fun robust(v: Int) = if (v == 0) Color(0xFFBBBBBB) else if (v <= 2) red else if (v == 3) amber else green
}

val scoutColors = lightColorScheme(primary = C.accent, background = C.page, surface = C.card, onSurface = Color(0xFF111111))

@Composable
fun Card(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().padding(vertical = 6.dp).clip(RoundedCornerShape(20.dp)).background(C.card).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp), content = content)
}

/** A card with a colored icon, a title, and (optionally) a Clear button for just this section. */
@Composable
fun Section(title: String, icon: String, color: Color, onClear: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    Card {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(30.dp).clip(RoundedCornerShape(8.dp)).background(color), contentAlignment = Alignment.Center) { Text(icon, fontSize = 15.sp) }
            Text(title, fontSize = 19.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            if (onClear != null) SmallButton("Clear", onClick = onClear)
        }
        content()
    }
}

@Composable
fun SmallButton(text: String, enabled: Boolean = true, onClick: () -> Unit) {
    Text(text, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = if (enabled) C.muted else C.muted.copy(alpha = .4f),
        modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(C.well).clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp))
}

/** Big segmented choice: every option is a full-size button. */
@Composable
fun <T> Choice(options: List<Pair<T, String>>, selected: T, color: Color = C.accent, base: Color = C.well, onSelect: (T) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        options.forEach { (value, label) ->
            val on = value == selected
            Box(Modifier.weight(1f).heightIn(min = 44.dp).clip(RoundedCornerShape(12.dp)).background(if (on) color else base)
                .clickable(role = Role.Tab) { onSelect(value) }.semantics { this.selected = on }, contentAlignment = Alignment.Center) {
                Text(label, color = if (on) Color.White else Color(0xFF111111), fontWeight = FontWeight.SemiBold, fontSize = 15.sp,
                    maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(horizontal = 4.dp))
            }
        }
    }
}

@Composable
fun Toggle(text: String, on: Boolean, color: Color = C.accent, modifier: Modifier = Modifier, onToggle: () -> Unit) {
    Box(modifier.fillMaxWidth().heightIn(min = 46.dp).clip(RoundedCornerShape(23.dp)).background(if (on) color else C.well)
        .clickable(role = Role.Checkbox, onClick = onToggle).semantics { selected = on }.padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center) {
        Text((if (on) "✓ " else "") + text, color = if (on) Color.White else Color(0xFF111111), fontWeight = FontWeight.SemiBold, fontSize = 15.sp, maxLines = 1)
    }
}

/** Counts while watching: starts blank ("not scored"); the first button reads 0 until something is recorded. */
@Composable
fun Counter(title: String, value: Int?, steps: List<Int>, color: Color, onChange: (Int?) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, fontWeight = FontWeight.Bold, fontSize = 17.sp)
            if (value != null) Text("  ✕", color = C.muted, fontSize = 18.sp, modifier = Modifier.clickable { onChange(null) }.semantics { contentDescription = "Clear $title" })
            Spacer(Modifier.weight(1f))
            if (value != null) Text("$value", fontSize = 40.sp, fontWeight = FontWeight.ExtraBold)
            else Text("not scored", color = C.muted, fontWeight = FontWeight.SemiBold)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.weight(1f).heightIn(min = 52.dp).clip(RoundedCornerShape(14.dp)).background(C.well)
                .clickable(role = Role.Button) { onChange(maxOf(0, (value ?: 1) - 1)) }, contentAlignment = Alignment.Center) {
                Text(if (value == null) "0" else "−", fontSize = 20.sp, fontWeight = FontWeight.ExtraBold)
            }
            steps.forEach { n ->
                Box(Modifier.weight(1f).heightIn(min = 52.dp).clip(RoundedCornerShape(14.dp)).background(color)
                    .clickable(role = Role.Button) { onChange((value ?: 0) + n) }.semantics { contentDescription = "Add $n $title" }, contentAlignment = Alignment.Center) {
                    Text("+$n", fontSize = 20.sp, fontWeight = FontWeight.ExtraBold, color = Color.White)
                }
            }
        }
    }
}

/** 1-5, tap the same number again to clear it. */
@Composable
fun Rating(title: String, value: Int, color: Color = C.accent, onChange: (Int) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, fontWeight = FontWeight.Bold)
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            (1..5).forEach { n ->
                Box(Modifier.weight(1f).heightIn(min = 42.dp).clip(RoundedCornerShape(12.dp))
                    .background(if (value >= n) color.copy(alpha = if (n == value) 1f else .55f) else C.well)
                    .clickable(role = Role.Button) { onChange(if (value == n) 0 else n) }.semantics { contentDescription = "$title $n" },
                    contentAlignment = Alignment.Center) {
                    Text("$n", fontWeight = FontWeight.Bold, color = if (value >= n) Color.White else Color(0xFF111111))
                }
            }
        }
    }
}

@Composable
fun Pill(text: String, color: Color) {
    Text(text, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.ExtraBold,
        modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(color).padding(horizontal = 8.dp, vertical = 2.dp))
}

@Composable
fun Badge(value: Int) {
    Box(Modifier.size(width = 28.dp, height = 24.dp).clip(RoundedCornerShape(7.dp)).background(C.robust(value)), contentAlignment = Alignment.Center) {
        Text(if (value == 0) "–" else "$value", color = Color.White, fontWeight = FontWeight.ExtraBold, fontSize = 14.sp)
    }
}

data class ShotSeries(val shots: List<List<Double>>, val color: Color, val label: String = "")

/** The 2026 field; tap to add a shooting spot. Each robot's spots show in its own color and tag. */
@Composable
fun ShotField(series: List<ShotSeries>, onTap: ((Double, Double) -> Unit)?) {
    BoxWithConstraints(Modifier.fillMaxWidth().aspectRatio(16.541f / 8.069f).clip(RoundedCornerShape(12.dp))
        .semantics { contentDescription = "Field: tap where the robot shoots from" }
        .pointerInput(onTap) { if (onTap != null) detectTapGestures { p -> onTap(p.x / size.width.toDouble(), p.y / size.height.toDouble()) } }) {
        Image(painterResource(R.drawable.field), contentDescription = null, contentScale = ContentScale.FillBounds, modifier = Modifier.matchParentSize())
        series.forEach { s ->
            s.shots.forEach { (x, y) ->
                Box(Modifier.offset(maxWidth * x.toFloat() - 9.dp, maxHeight * y.toFloat() - 9.dp).size(18.dp).clip(CircleShape)
                    .background(s.color).border(2.dp, Color.White, CircleShape), contentAlignment = Alignment.Center) {
                    Text(s.label, color = Color.White, fontSize = 7.sp, fontWeight = FontWeight.ExtraBold)
                }
            }
        }
    }
}

@Composable
fun Tile(label: String, value: String, modifier: Modifier = Modifier) {
    Column(modifier.clip(RoundedCornerShape(14.dp)).background(C.well).padding(10.dp)) {
        Text(value, fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, maxLines = 1)
        Text(label, fontSize = 12.sp, color = C.muted)
    }
}

@Composable
fun Muted(text: String, modifier: Modifier = Modifier) = Text(text, color = C.muted, fontSize = 13.sp, modifier = modifier)

@Composable
fun H1(text: String) = Text(text, fontSize = 28.sp, fontWeight = FontWeight.ExtraBold, modifier = Modifier.padding(top = 6.dp, bottom = 6.dp))

