package com.haru.official

import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.*
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private const val BASE = "/data/adb/rootmodule"
private val Cyan = Color(0xFF22D3EE)
private val Violet = Color(0xFFC084FC)
private val CardBg = Color(0xFF151C27)
private val Muted = Color(0xFF9AA7B8)

data class Mode(val key: String, val emoji: String, val title: String, val desc: String, val color: Color)

val MODES = listOf(
    Mode("powersave", "🔋", "Power Save", "Longer battery, lower speed", Color(0xFF4ADE80)),
    Mode("balanced", "⚖️", "Balanced", "Everyday balance of speed and battery", Color(0xFF60A5FA)),
    Mode("performance", "🚀", "Performance", "Maximum speed, more battery use", Color(0xFFFB923C)),
    Mode("gaming", "🎮", "Gaming Pro", "Performance + clear background apps", Color(0xFFF472B6)),
    Mode("cooldown", "❄️", "Cool Down", "Limit the CPU for 2 minutes", Color(0xFF22D3EE)),
    Mode("clear", "🧹", "Clear", "Free RAM by closing background apps", Color(0xFFFACC15)),
)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(primary = Cyan, background = Color(0xFF0B0F14), surface = CardBg)) {
                HaruApp()
            }
        }
    }
}

@Composable
fun HaruApp() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val prefs = remember { ctx.getSharedPreferences("haru", 0) }
    var tab by remember { mutableIntStateOf(0) }
    var root by remember { mutableStateOf<Boolean?>(null) }
    var current by remember { mutableStateOf(prefs.getString("mode", "manual") ?: "manual") }
    var busy by remember { mutableStateOf<String?>(null) }
    var cool by remember { mutableIntStateOf(0) }

    fun toast(s: String) = Toast.makeText(ctx, s, Toast.LENGTH_SHORT).show()

    var moduleOk by remember { mutableStateOf<Boolean?>(null) }
    var checking by remember { mutableStateOf(true) }

    fun check() {
        scope.launch {
            checking = true
            withContext(Dispatchers.IO) {
                Shell.install(ctx)
                val r = Shell.hasRoot()
                root = r
                moduleOk = r && Shell.su(
                    "M=/data/adb/modules/rootmodule; test -f \$M/module.prop && ! test -e \$M/disable && ! test -e \$M/remove && echo yes"
                ).second.contains("yes")
            }
            checking = false
        }
    }

    LaunchedEffect(Unit) { check() }

    fun apply(m: Mode) {
        if (root != true) { toast("Root access is required"); return }
        if (busy != null) return
        scope.launch {
            busy = m.key
            val r = withContext(Dispatchers.IO) { Shell.run(m.key) }
            busy = null
            if (r.first != 0) { toast("Failed: " + r.second.take(80)); return@launch }
            if (m.key == "clear") { toast("Background apps cleared"); return@launch }
            current = m.key
            prefs.edit().putString("mode", m.key).apply()
            toast(m.title + " applied")
            if (m.key == "cooldown") {
                cool = 120
                while (cool > 0) { delay(1000); cool-- }
                current = "balanced"
                prefs.edit().putString("mode", "balanced").apply()
            }
        }
    }

    Box(
        Modifier.fillMaxSize().background(
            Brush.verticalGradient(listOf(Color(0xFF0B0F14), Color(0xFF111A2B)))
        )
    ) {
      if (checking || root != true || moduleOk != true) {
        GateScreen(checking, root, moduleOk, ::check)
      } else {
        Scaffold(
            containerColor = Color.Transparent,
            contentColor = Color.White,
            bottomBar = {
                NavigationBar(containerColor = Color(0xFF0E141D), contentColor = Color.White) {
                    listOf("🏠" to "Home", "🛠️" to "Tools").forEachIndexed { i, (e, l) ->
                        NavigationBarItem(
                            selected = tab == i,
                            onClick = { tab = i },
                            icon = { Text(e, fontSize = 20.sp) },
                            label = { Text(l) },
                            colors = NavigationBarItemDefaults.colors(
                                selectedTextColor = Cyan,
                                unselectedTextColor = Muted,
                                indicatorColor = Color(0x3322D3EE),
                            ),
                        )
                    }
                }
            },
        ) { pad ->
            Box(Modifier.padding(pad)) {
                if (tab == 0) HomeScreen(root, current, busy, cool, ::apply)
                else ToolsScreen(root, ::toast)
            }
        }
      }
    }
}

@Composable
fun GateScreen(checking: Boolean, root: Boolean?, moduleOk: Boolean?, onRetry: () -> Unit) {
    val needRoot = root != true
    Column(
        Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            "HARU OFFICIAL",
            style = TextStyle(
                brush = Brush.horizontalGradient(listOf(Cyan, Violet)),
                fontSize = 30.sp, fontWeight = FontWeight.ExtraBold,
            ),
        )
        Spacer(Modifier.height(28.dp))
        if (checking) {
            CircularProgressIndicator(color = Cyan)
            Spacer(Modifier.height(16.dp))
            Text("Checking root and module…", color = Muted)
        } else {
            Text(if (needRoot) "🔒" else "📦", fontSize = 56.sp)
            Spacer(Modifier.height(12.dp))
            Text(
                if (needRoot) "Root access required" else "Module not installed",
                fontSize = 22.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                if (needRoot) "Tap Allow / Grant when your root manager (Magisk or KernelSU) asks, then try again."
                else "HARU OFFICIAL MODULE must be installed and enabled before this app can be used.",
                color = Muted, fontSize = 14.sp, textAlign = TextAlign.Center,
            )
            if (!needRoot) {
                Spacer(Modifier.height(16.dp))
                Column(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(CardBg).padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text("1. Open Magisk or KernelSU, then Modules", fontSize = 14.sp)
                    Text("2. Install HARU-OFFICIAL-MODULE zip", fontSize = 14.sp)
                    Text("3. Reboot your phone", fontSize = 14.sp)
                    Text("4. Open this app again", fontSize = 14.sp)
                }
            }
            Spacer(Modifier.height(24.dp))
            ActionButton(if (needRoot) "Grant root / Try again" else "Check again", Cyan, true, onRetry)
        }
    }
}

@Composable
fun HomeScreen(root: Boolean?, current: String, busy: String?, cool: Int, onMode: (Mode) -> Unit) {
    val currentTitle = MODES.firstOrNull { it.key == current }?.title ?: "Manual"
    LazyColumn(
        Modifier.fillMaxSize().statusBarsPadding(),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Column {
                Text(
                    "HARU OFFICIAL",
                    style = TextStyle(
                        brush = Brush.horizontalGradient(listOf(Cyan, Violet)),
                        fontSize = 30.sp, fontWeight = FontWeight.ExtraBold,
                    ),
                )
                Text("Performance & Game Module", color = Muted, fontSize = 14.sp)
            }
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                StatCard(
                    Modifier.weight(1f), "🛡️", "Root Access",
                    when (root) { true -> "Yes"; false -> "No"; null -> "Checking…" },
                    when (root) { true -> Color(0xFF4ADE80); false -> Color(0xFFF87171); null -> Muted },
                )
                StatCard(Modifier.weight(1f), "🎚️", "Mode", currentTitle, Cyan)
            }
        }
        items(MODES) { m ->
            ModeCard(
                m,
                active = current == m.key,
                loading = busy == m.key,
                sub = if (m.key == "cooldown" && cool > 0) "Resting… ${cool}s left" else null,
            ) { onMode(m) }
        }
        item { Spacer(Modifier.height(8.dp)) }
    }
}

@Composable
fun StatCard(modifier: Modifier, emoji: String, label: String, value: String, valueColor: Color) {
    Column(
        modifier.clip(RoundedCornerShape(20.dp)).background(CardBg).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(emoji, fontSize = 22.sp)
        Text(label, color = Muted, fontSize = 13.sp)
        Text(value, color = valueColor, fontSize = 20.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun ModeCard(m: Mode, active: Boolean, loading: Boolean, sub: String?, onClick: () -> Unit) {
    val shape = RoundedCornerShape(22.dp)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(CardBg)
            .border(if (active) 1.5.dp else 1.dp, if (active) m.color else Color(0x22FFFFFF), shape)
            .clickable(onClick = onClick).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(52.dp).clip(CircleShape).background(m.color.copy(alpha = 0.18f)),
            contentAlignment = Alignment.Center,
        ) { Text(m.emoji, fontSize = 24.sp) }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(m.title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Text(sub ?: m.desc, fontSize = 13.sp, color = Muted)
        }
        if (loading) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp, color = m.color)
        else if (active) Text("ACTIVE", color = m.color, fontSize = 12.sp, fontWeight = FontWeight.Bold)
    }
}

private fun cfg(text: String, key: String): String? =
    text.lines().firstOrNull { it.startsWith("$key=") }?.substringAfter("=")?.trim()

@Composable
fun ToolsScreen(root: Boolean?, toast: (String) -> Unit) {
    val scope = rememberCoroutineScope()
    var installed by remember { mutableStateOf(false) }
    var preset by remember { mutableStateOf("off") }
    var downscale by remember { mutableStateOf(true) }
    var scale by remember { mutableFloatStateOf(75f) }

    LaunchedEffect(root) {
        if (root == true) {
            val (sp, dc) = withContext(Dispatchers.IO) {
                Pair(Shell.su("cat $BASE/spoof.conf").second, Shell.su("cat $BASE/downscale.conf").second)
            }
            installed = sp.contains("PRESET=")
            cfg(sp, "PRESET")?.let { preset = it }
            cfg(dc, "DOWNSCALE")?.let { downscale = it == "1" }
            cfg(dc, "SCALE")?.toFloatOrNull()?.let { scale = it.coerceIn(50f, 100f) }
        }
    }

    fun setKey(file: String, key: String, value: String) {
        scope.launch(Dispatchers.IO) { Shell.su("sed -i 's/^$key=.*/$key=$value/' $BASE/$file") }
    }

    LazyColumn(
        Modifier.fillMaxSize().statusBarsPadding(),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { Text("Game Tools", fontSize = 26.sp, fontWeight = FontWeight.ExtraBold) }

        if (root != true || !installed) item {
            Text(
                if (root != true) "Root access is required for these tools."
                else "HARU OFFICIAL MODULE is not installed. Flash the module in your root manager first.",
                color = Color(0xFFFBBF24), fontSize = 14.sp,
            )
        }

        item {
            Section("📱", "120 FPS Device Profile") {
                Text("Choose the device the games will see. Reboot to apply.", color = Muted, fontSize = 13.sp)
                Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("off" to "Off", "s23ultra" to "S23 Ultra", "s24ultra" to "S24 Ultra").forEach { (k, l) ->
                        FilterChip(
                            selected = preset == k,
                            enabled = installed,
                            onClick = { preset = k; setKey("spoof.conf", "PRESET", k); toast("Reboot to apply") },
                            label = { Text(l) },
                        )
                    }
                }
            }
        }

        item {
            Section("🔍", "Resolution Downscale") {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Lower resolution in games", fontWeight = FontWeight.SemiBold)
                        Text("Only while CODM / ML is open. Reboot to apply.", color = Muted, fontSize = 13.sp)
                    }
                    Switch(
                        checked = downscale, enabled = installed,
                        onCheckedChange = { downscale = it; setKey("downscale.conf", "DOWNSCALE", if (it) "1" else "0") },
                    )
                }
                Spacer(Modifier.height(8.dp))
                Text("Scale: ${scale.toInt()}%", color = Cyan, fontWeight = FontWeight.Bold)
                Slider(
                    value = scale, enabled = installed && downscale,
                    onValueChange = { scale = it },
                    onValueChangeFinished = { setKey("downscale.conf", "SCALE", scale.toInt().toString()) },
                    valueRange = 50f..100f, steps = 9,
                )
                Text("Lower % = blurrier but smoother", color = Muted, fontSize = 12.sp)
            }
        }

        item {
            Section("🧰", "Quick Actions") {
                ActionButton("Reset resolution", Color(0xFFF87171), root == true) {
                    scope.launch {
                        withContext(Dispatchers.IO) { Shell.su("wm size reset; wm density reset") }
                        toast("Resolution reset")
                    }
                }
                Spacer(Modifier.height(8.dp))
                ActionButton("Install APKs from /sdcard/AutoInstall", Cyan, root == true && installed) {
                    scope.launch {
                        toast("Installing…")
                        val r = withContext(Dispatchers.IO) { Shell.su("sh /data/adb/modules/rootmodule/autoinstall.sh") }
                        toast(if (r.first == 0) "Done. See autoinstall.log" else "Failed")
                    }
                }
            }
        }
        item { Spacer(Modifier.height(8.dp)) }
    }
}

@Composable
fun Section(emoji: String, title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(CardBg).padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(emoji, fontSize = 20.sp)
            Spacer(Modifier.width(8.dp))
            Text(title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        }
        Spacer(Modifier.height(10.dp))
        content()
    }
}

@Composable
fun ActionButton(text: String, color: Color, enabled: Boolean, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        colors = ButtonDefaults.buttonColors(containerColor = color.copy(alpha = 0.2f), contentColor = color),
    ) { Text(text, fontWeight = FontWeight.SemiBold) }
}
