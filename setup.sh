#!/bin/bash
# Recreates the whole HARU OFFICIAL app project from this one file.
set -e
mkdir -p "app"
cat > "app/build.gradle.kts" <<'HARU_EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.haru.official"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.haru.official"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
    buildTypes {
        release { isMinifyEnabled = false }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.09.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}
HARU_EOF
mkdir -p "app/src/main"
cat > "app/src/main/AndroidManifest.xml" <<'HARU_EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:allowBackup="false"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher"
        android:label="HARU OFFICIAL"
        android:theme="@style/Theme.Haru">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
HARU_EOF
mkdir -p "app/src/main/assets"
cat > "app/src/main/assets/haru.sh" <<'HARU_EOF'
#!/system/bin/sh
P=/sys/devices/system/cpu/cpufreq

gov() {
  for p in $P/policy*; do
    av=" $(cat $p/scaling_available_governors 2>/dev/null) "
    for g in "$@"; do
      case "$av" in *" $g "*) echo "$g" > $p/scaling_governor 2>/dev/null; break ;; esac
    done
  done
}
restore() {
  for p in $P/policy*; do
    cat $p/cpuinfo_max_freq > $p/scaling_max_freq 2>/dev/null
    cat $p/cpuinfo_min_freq > $p/scaling_min_freq 2>/dev/null
  done
}
cap() {
  for p in $P/policy*; do
    mn=$(cat $p/cpuinfo_min_freq 2>/dev/null)
    mx=$(cat $p/cpuinfo_max_freq 2>/dev/null)
    [ -n "$mx" ] || continue
    echo "$mn" > $p/scaling_min_freq 2>/dev/null
    echo $((mx * $1 / 100)) > $p/scaling_max_freq 2>/dev/null
  done
}
clean() {
  am kill-all >/dev/null 2>&1
  sync
  echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
}

case "$1" in
  powersave)   restore; gov schedutil walt interactive ondemand; cap 60 ;;
  balanced)    restore; gov schedutil walt interactive ondemand ;;
  performance) restore; gov performance schedutil walt ;;
  gaming)      restore; gov performance schedutil walt; clean ;;
  cooldown)
    restore; gov schedutil walt interactive ondemand; cap 50
    nohup sh "$0" cooldown_end >/dev/null 2>&1 &
    ;;
  cooldown_end) sleep 120; restore; gov schedutil walt interactive ondemand ;;
  clear)       clean ;;
esac
exit 0
HARU_EOF
mkdir -p "app/src/main/java/com/haru/official"
cat > "app/src/main/java/com/haru/official/MainActivity.kt" <<'HARU_EOF'
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
HARU_EOF
mkdir -p "app/src/main/java/com/haru/official"
cat > "app/src/main/java/com/haru/official/Shell.kt" <<'HARU_EOF'
package com.haru.official

import android.content.Context
import java.io.File

object Shell {
    private var script = ""

    fun su(cmd: String): Pair<Int, String> = try {
        val p = ProcessBuilder("su", "-c", cmd).redirectErrorStream(true).start()
        val out = p.inputStream.bufferedReader().readText().trim()
        Pair(p.waitFor(), out)
    } catch (e: Exception) {
        Pair(-1, e.message ?: "error")
    }

    fun hasRoot(): Boolean = su("id").second.contains("uid=0")

    fun install(ctx: Context) {
        val f = File(ctx.filesDir, "haru.sh")
        ctx.assets.open("haru.sh").use { i -> f.outputStream().use { o -> i.copyTo(o) } }
        script = f.absolutePath
    }

    fun run(mode: String): Pair<Int, String> = su("sh '$script' $mode")
}
HARU_EOF
mkdir -p "app/src/main/res/drawable"
cat > "app/src/main/res/drawable/ic_fg.xml" <<'HARU_EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:fillColor="#FF22D3EE" android:pathData="M34,34h10v40h-10z" />
    <path android:fillColor="#FF22D3EE" android:pathData="M64,34h10v40h-10z" />
    <path android:fillColor="#FFC084FC" android:pathData="M44,49h20v10h-20z" />
</vector>
HARU_EOF
mkdir -p "app/src/main/res/mipmap-anydpi-v26"
cat > "app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml" <<'HARU_EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_bg" />
    <foreground android:drawable="@drawable/ic_fg" />
</adaptive-icon>
HARU_EOF
mkdir -p "app/src/main/res/values"
cat > "app/src/main/res/values/colors.xml" <<'HARU_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_bg">#FF0B0F14</color>
</resources>
HARU_EOF
mkdir -p "app/src/main/res/values"
cat > "app/src/main/res/values/themes.xml" <<'HARU_EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.Haru" parent="android:Theme.Material.NoActionBar">
        <item name="android:windowBackground">#FF0B0F14</item>
        <item name="android:statusBarColor">@android:color/transparent</item>
        <item name="android:navigationBarColor">@android:color/transparent</item>
    </style>
</resources>
HARU_EOF
cat > "build.gradle.kts" <<'HARU_EOF'
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "2.0.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.20" apply false
}
HARU_EOF
cat > "gradle.properties" <<'HARU_EOF'
org.gradle.jvmargs=-Xmx2g -Dfile.encoding=UTF-8
android.useAndroidX=true
android.nonTransitiveRClass=true
kotlin.code.style=official
HARU_EOF
cat > "settings.gradle.kts" <<'HARU_EOF'
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "HaruOfficial"
include(":app")
HARU_EOF
echo "project generated"
