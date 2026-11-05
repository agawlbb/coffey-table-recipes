package com.coffeytable.coffey_table_recipes

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.firebase.auth.FirebaseAuth
import okhttp3.*
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.TimeUnit

/** Native notification actions remain durable when no Flutter engine is running. */
object TimerActions {
    private val handler = Handler(Looper.getMainLooper())
    private val client = OkHttpClient.Builder().connectTimeout(5, TimeUnit.SECONDS).build()
    private var sending = false
    private fun prefs(c: Context) = c.getSharedPreferences("timer_sync", Context.MODE_PRIVATE)
    @Synchronized fun pending(c: Context): JSONArray = JSONArray(prefs(c).getString("actions", "[]")!!)
    @Synchronized fun acknowledge(c: Context, uid: String, operation: String) {
        val all = pending(c); val kept = JSONArray()
        for (i in 0 until all.length()) {
            val row = all.getJSONObject(i)
            if (row.optString("account_uid") != uid || row.optString("operation_id") != operation) kept.put(row)
        }
        check(prefs(c).edit().putString("actions", kept.toString()).commit())
    }
    @Synchronized fun configure(c: Context, uid: String) {
        val all = pending(c); val kept = JSONArray()
        for (i in 0 until all.length()) if (all.getJSONObject(i).optString("account_uid") == uid) kept.put(all.getJSONObject(i))
        check(prefs(c).edit().putString("actions", kept.toString()).commit())
    }
    @Synchronized fun sent(c: Context, uid: String, operation: String) {
        val all = pending(c)
        for (i in 0 until all.length()) { val row=all.getJSONObject(i); if(row.optString("account_uid")==uid && row.optString("operation_id")==operation) row.put("sent",true) }
        check(prefs(c).edit().putString("actions",all.toString()).commit())
    }
    fun rows(c: Context): List<Map<String, Any?>> {
        val all=pending(c)
        return (0 until all.length()).map { i -> val row=all.getJSONObject(i); row.keys().asSequence().associateWith { key ->
            if(key=="body") { val body=row.getJSONObject(key); body.keys().asSequence().associateWith { body.get(it) } } else row.get(key)
        } }
    }
    fun label(seconds: Int): String {
        val parts = mutableListOf<String>()
        if (seconds / 3600 > 0) parts.add("${seconds / 3600} hr")
        if (seconds / 60 % 60 > 0) parts.add("${seconds / 60 % 60} min")
        if (seconds % 60 > 0) parts.add("${seconds % 60} sec")
        return "Add " + parts.joinToString(" ")
    }
    fun action(c: Context, key: String, expected: Long, extend: Boolean) {
        synchronized(TimerSyncNative) {
            val row = RecipeTimers.rows(c).optJSONObject(key) ?: return
            if (row.getLong("deadline") != expected) return
            val extra = row.optInt("extension_seconds", 0)
            if (extend && (expected > System.currentTimeMillis() || extra <= 0)) return
            val deadline = if (extend) System.currentTimeMillis() + extra * 1000L else expected
            if (extend) {
                val all = RecipeTimers.rows(c); val replacement = JSONObject(row.toString())
                replacement.put("deadline", deadline).put("extension_seconds", 0)
                all.put(key, replacement); RecipeTimers.save(c, all)
                try { RecipeTimers.schedule(c, key, deadline) } catch (error: Exception) {
                    all.put(key, row); RecipeTimers.save(c, all); throw error
                }
                RecipeTimerService.stopTimer(c, key)
            } else RecipeTimers.cancel(c, key)
            enqueue(c, key, expected, deadline, extend)
            TimerSyncNative.changed()
        }
    }
    @Synchronized private fun enqueue(c: Context, key: String, expected: Long, deadline: Long, extend: Boolean) {
        val match = Regex("^remote:session:([a-f0-9]{32}):(.+)$").matchEntire(key) ?: return
        val p = prefs(c); val uid = p.getString("uid", "")!!; if (uid.isEmpty()) return
        val all = pending(c); val id = key.removePrefix("remote:")
        var revision = TimerSyncNative.revision(c, id)
        for (i in 0 until all.length()) {
            val old = all.getJSONObject(i)
            if (old.optString("session_id") == match.groupValues[1] && old.getJSONObject("body").optString("action_id") == match.groupValues[2]) revision = maxOf(revision, old.getJSONObject("body").getLong("revision") + 1)
        }
        val body = JSONObject().put("action_id", match.groupValues[2]).put("cancelled", !extend)
            .put("extension_seconds", 0).put("deadline_ms", deadline + p.getLong("clockOffset", 0L)).put("revision", revision).put("expected_deadline_ms", expected + p.getLong("clockOffset",0L))
        if (extend) body.put("extend", true)
        all.put(JSONObject().put("account_uid", uid).put("installation_id", p.getString("installation", ""))
            .put("session_id", match.groupValues[1]).put("operation_id", UUID.randomUUID().toString().replace("-", "")).put("body", body))
        check(p.edit().putString("actions", all.toString()).commit())
    }
    fun sync(c: Context, finished: () -> Unit = {}) {
        if (RecipeTimers.foreground) { TimerSyncNative.changed(); finished(); return }
        synchronized(this) { if (sending) { finished(); return }; sending = true }
        val all = pending(c)
        val first = (0 until all.length()).map { all.getJSONObject(it) }.firstOrNull { !it.optBoolean("sent", false) }
        val user = FirebaseAuth.getInstance().currentUser
        if (first == null || user == null || first.optString("account_uid") != user.uid) { synchronized(this) { sending = false }; finished(); return }
        var socket: WebSocket? = null
        var done = false
        fun finish() {
            synchronized(this) { if (done) return; done = true; sending = false }
            socket?.cancel(); finished()
        }
        handler.postDelayed({ finish() }, 8000)
        user.getIdToken(false).addOnCompleteListener { task ->
            if (done) return@addOnCompleteListener
            if (!task.isSuccessful) { finish(); return@addOnCompleteListener }
            val token = task.result?.token
            if (token == null || FirebaseAuth.getInstance().currentUser?.uid != user.uid) { finish(); return@addOnCompleteListener }
            socket = client.newWebSocket(Request.Builder().url("wss://ctr.coffeybean.com/shopping").build(), object : WebSocketListener() {
                override fun onOpen(ws: WebSocket, response: Response) {
                    ws.send(JSONObject().put("v", 1).put("type", "auth").put("token", token).put("scope", "cooking").put("household_id", JSONObject.NULL).toString())
                }
                override fun onMessage(ws: WebSocket, text: String) {
                    try {
                        if (FirebaseAuth.getInstance().currentUser?.uid != user.uid) { finish(); return }
                        val frame = JSONObject(text)
                        when (frame.optString("type")) {
                            "ready" -> {
                                val body = JSONObject(first.getJSONObject("body").toString()).put("installation_id", first.getString("installation_id")).put("operation_id", first.getString("operation_id"))
                                ws.send(JSONObject().put("v", 1).put("type", "request").put("id", first.getString("operation_id")).put("path", "/me/cooking-sessions/${first.getString("session_id")}/timer").put("body", body).toString())
                            }
                            "response" -> {
                                val timers = frame.getJSONObject("data").getJSONObject("session").getJSONArray("timers")
                                for (i in 0 until timers.length()) {
                                    val timer = timers.getJSONObject(i)
                                    if (timer.optString("action_id") == first.getJSONObject("body").optString("action_id")) TimerSyncNative.recordRevision(c, timer.getString("timer_id"), timer.getLong("revision"))
                                }
                                sent(c, user.uid, first.getString("operation_id")); TimerSyncNative.changed(); finish()
                                handler.post { sync(c) }
                            }
                            "error" -> {
                                if (frame.optInt("status") in listOf(404, 409, 422)) { acknowledge(c, user.uid, first.getString("operation_id")); TimerSyncNative.changed() }
                                finish()
                            }
                        }
                    } catch (_: Exception) { finish() }
                }
                override fun onFailure(ws: WebSocket, error: Throwable, response: Response?) { finish() }
                override fun onClosed(ws: WebSocket, code: Int, reason: String) { finish() }
            })
        }
    }
}
