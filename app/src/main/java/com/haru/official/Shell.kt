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
