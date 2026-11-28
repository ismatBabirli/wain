package com.wainhq.wain.store

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.wainhq.wain.BuildConfig
import com.wainhq.wain.net.http
import com.wainhq.wain.wire.str
import com.wainhq.wain.wire.toJson
import com.wainhq.wain.wire.wireJson
import java.io.IOException
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response

/**
 * Anonymous usage counts and crash reports, sent to PostHog the way the desktop's `analytics.rs`
 * sends them: one POST per event under a random install id, and nothing the reader wrote — no
 * prompt, path, title or error message. Settings › Privacy has a switch for each, both on by
 * default. A build with no `POSTHOG_KEY` (every local one) sends nothing.
 *
 * Sessions, bots and messages started here are counted by the server that runs them, so the
 * phone reports only that it was opened, and how it crashed.
 */
object Analytics {
    private const val TAG = "analytics"
    private const val ENDPOINT = "https://us.i.posthog.com/i/v0/e/"
    private const val EXCEPTION = "\$exception"
    private lateinit var prefs: SharedPreferences
    private var day = ""

    var usage by mutableStateOf(true)
        private set
    var crashes by mutableStateOf(true)
        private set

    /** At launch: the last run's crash, which build is in the wild, and the day; then catch this run's crash. */
    fun start(context: Context) {
        prefs = context.getSharedPreferences("privacy", Context.MODE_PRIVATE)
        usage = prefs.getBoolean(USAGE, true)
        crashes = prefs.getBoolean(CRASHES, true)
        prefs.getString(PENDING, null)?.let { saved ->
            prefs.edit().remove(PENDING).apply()
            runCatching { wireJson.parseToJsonElement(saved).jsonObject }.getOrNull()?.let { send(EXCEPTION, it, it["timestamp"].str) }
        }
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, e ->
            // Kept for the next launch: this process is on its way out. `commit`, since `apply` writes later.
            if (crashes) runCatching { prefs.edit().putString(PENDING, crash(e, Instant.now().toString()).toString()).commit() }
            previous?.uncaughtException(thread, e)
        }
        send("app_started")
        activeDay()
    }

    /** At most once per local day per run, at launch and on every return to the front. */
    fun activeDay() {
        val today = LocalDate.now().toString()
        if (day != today && send("active_day")) day = today
    }

    fun turnUsage(on: Boolean) { usage = on; saved() }
    fun turnCrashes(on: Boolean) { crashes = on; saved() }

    /** Both off, the id goes too, and switching one back on makes a new one. */
    private fun saved() {
        val edit = prefs.edit().putBoolean(USAGE, usage).putBoolean(CRASHES, crashes)
        if (!usage && !crashes) edit.remove(ID)
        edit.apply()
    }

    /** Whether the event went, so a day is claimed only once its event did. */
    private fun send(event: String, props: JsonObject = JsonObject(emptyMap()), timestamp: String? = null): Boolean {
        if (!(if (event == EXCEPTION) crashes else usage)) return false
        val all = JsonObject(base + props.filterKeys { it != "timestamp" })
        val key = BuildConfig.POSTHOG_KEY
        if (key.isEmpty()) {
            if (BuildConfig.DEBUG) Log.d(TAG, "would send $event $all")
            return false
        }
        val body = toJson(listOfNotNull("api_key" to key, "event" to event, "distinct_id" to installId(), "properties" to all,
            timestamp?.let { "timestamp" to it }).toMap())
        http.newCall(Request.Builder().url(ENDPOINT).post(body.toString().toRequestBody("application/json".toMediaType())).build())
            .enqueue(object : Callback {
                // A wrong key or region is a 4xx and nothing else, so say so.
                override fun onFailure(call: Call, e: IOException) { Log.w(TAG, "send failed: ${e.message}") }
                override fun onResponse(call: Call, response: Response) {
                    response.close()
                    if (!response.isSuccessful) Log.w(TAG, "PostHog answered ${response.code}")
                }
            })
        return true
    }

    private fun installId(): String = prefs.getString(ID, null) ?: UUID.randomUUID().toString().also { prefs.edit().putString(ID, it).apply() }

    private val base by lazy {
        JsonObject(mapOf(
            "app_version" to BuildConfig.VERSION_NAME,
            "build" to BuildConfig.VERSION_CODE.toString(),
            "os" to "android",
            "os_version" to Build.VERSION.RELEASE,
            "is_debug" to BuildConfig.DEBUG,
            // Not the desktop's "app": a phone is an install of its own, so a person of its own.
            "source" to "phone",
            // PostHog reads a missing one as automation, and bot-filtered insights drop the event.
            "\$raw_user_agent" to "Wain/${BuildConfig.VERSION_NAME} (android)",
        ).mapValues { toJson(it.value) })
    }

    /**
     * [e] as an `$exception`: its class name, and the frames in this app's own code, outermost first,
     * from the first throwable in its cause chain that has any. Never the message, which is free text.
     * Readable without a mapping file because proguard-rules.pro keeps these names.
     */
    fun crash(e: Throwable, at: String): JsonObject {
        val ours = generateSequence(e) { it.cause }.take(5)
            .map { t -> t.stackTrace.filter { it.className.startsWith("com.wainhq.wain") }.take(20) }
            .firstOrNull { it.isNotEmpty() }.orEmpty()
        val frames = ours.reversed().map { f ->
            mapOf("platform" to "custom", "lang" to "kotlin", "function" to "${f.className}.${f.methodName}", "filename" to f.fileName,
                "lineno" to f.lineNumber.takeIf { it > 0 }, "colno" to null, "resolved" to true, "in_app" to true)
        }
        val where = ours.firstOrNull()?.let { f -> f.fileName?.let { "crash at $it:${f.lineNumber}" } } ?: "crash"
        return toJson(mapOf(
            "timestamp" to at,
            "kind" to "crash",
            "\$exception_list" to listOf(mapOf(
                "type" to e.javaClass.name,
                "value" to where,
                "mechanism" to mapOf("handled" to false, "synthetic" to false),
                "stacktrace" to mapOf("type" to "raw", "frames" to frames),
            )),
        )) as JsonObject
    }

    private const val USAGE = "usage"
    private const val CRASHES = "crashReports"
    private const val ID = "installId"
    private const val PENDING = "pendingCrash"
}
