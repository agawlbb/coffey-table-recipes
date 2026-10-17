package com.coffeytable.coffey_table_recipes

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** Native reception does not depend on a running Flutter activity or isolate. */
class TimerSyncReceiver : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        if (message.data["kind"] != "recipe_timer") return
        try { TimerSyncNative.apply(this, JSONObject(message.data as Map<*, *>)) }
        catch (_: Exception) {
            // Permission failures must not create a fake running timer.
            TimerSyncNative.notice(this, "Open Coffey Table Recipes to receive your timer.")
        }
    }
    override fun onNewToken(token: String) { TimerSyncNative.tokenChanged() }
}

object TimerSyncNative {
    private var channel: MethodChannel? = null
    private fun prefs(c: Context) = c.getSharedPreferences("timer_sync", Context.MODE_PRIVATE)
    fun tokenChanged() { Handler(Looper.getMainLooper()).post { channel?.invokeMethod("tokenChanged", null) } }
    fun changed() { Handler(Looper.getMainLooper()).post { channel?.invokeMethod("changed", null) } }

    @Synchronized fun configure(c: Context, args: Map<*, *>) {
        val p = prefs(c)
        val uid = args["account_uid"] as String
        val receive = args["receive_timers"] as Boolean
        val switched = p.getString("uid", "") != uid
        if (args["guard_only"] == true && !switched) return
        val revisions = JSONObject(p.getString("revisions", "{}")!!)
        if (switched || !receive) {
            val rows = RecipeTimers.rows(c)
            for (key in rows.keys().asSequence().toList()) {
                if (key.startsWith("remote:") || (switched && !p.getString("uid", "").isNullOrEmpty())) {
                    RecipeTimers.cancel(c, key)
                    if (key.startsWith("remote:")) revisions.remove(key.removePrefix("remote:"))
                }
            }
        }
        val editor = p.edit().putString("uid", uid).putString("installation", args["installation_id"] as String).putBoolean("receive", receive)
        editor.putString("revisions", if (switched) "{}" else revisions.toString())
        check(editor.commit())
    }

    @Synchronized fun revision(c: Context, id: String): Long =
        JSONObject(prefs(c).getString("revisions", "{}")!!).optLong(id, 0)

    @Synchronized fun recordRevision(c: Context, id: String, version: Long?) {
        val p = prefs(c)
        val revisions = JSONObject(p.getString("revisions", "{}")!!)
        if (version == null) revisions.remove(id) else if (version > revisions.optLong(id, 0)) revisions.put(id, version)
        check(p.edit().putString("revisions", revisions.toString()).commit())
    }

    @Synchronized fun apply(c: Context, data: JSONObject) {
        val p = prefs(c)
        val uid = p.getString("uid", "")!!
        val installation = p.getString("installation", "")!!
        if (uid.isEmpty() || data.optString("account_uid") != uid || data.optString("target_device") != installation) return
        val own = data.optString("source_device") == installation
        if (!p.getBoolean("receive", false) && !own) return
        val id = data.getString("timer_id")
        require(id.matches(Regex("[A-Za-z0-9:_-]{1,160}")))
        val version = data.getLong("revision")
        val revisions = JSONObject(p.getString("revisions", "{}")!!)
        if (version <= revisions.optLong(id, 0)) return
        val key = if (own) id.removePrefix("$installation:") else "remote:$id"
        val cancelled = data.optString("cancelled") in listOf("1", "true")
        val deadline = data.getLong("deadline_ms")
        if (cancelled || deadline <= System.currentTimeMillis()) {
            RecipeTimers.cancel(c, key)
            if (cancelled) notice(c, "Shared cooking timer stopped.")
        } else {
            check(Build.VERSION.SDK_INT < 33 || c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
            val rows = RecipeTimers.rows(c)
            val old = rows.optJSONObject(key)
            val title = data.getString("title")
            if (old == null || old.optLong("deadline") != deadline || old.optString("title") != title) {
                rows.put(key, JSONObject().put("deadline", deadline).put("title", title).put("tone", RecipeTimers.tone(c)))
                RecipeTimers.save(c, rows)
                try { RecipeTimers.schedule(c, key, deadline) } catch (error: Exception) {
                    if (old == null) rows.remove(key) else rows.put(key, old)
                    RecipeTimers.save(c, rows); throw error
                }
                RecipeTimerService.stopTimer(c, key)
            }
            if (!own) notice(c, "$title — timer ready on this device.")
        }
        // Record only after the OS accepted the operation; failures can retry.
        revisions.put(id, version)
        check(p.edit().putString("revisions", revisions.toString()).commit())
        changed()
    }

    fun notice(c: Context, text: String) {
        if (Build.VERSION.SDK_INT >= 33 && c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = c.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("timer_sync", "Shared cooking timers", NotificationManager.IMPORTANCE_DEFAULT))
        val open = PendingIntent.getActivity(c, 0, Intent(c, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, "timer_sync") else Notification.Builder(c)
        manager.notify(7102, builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm).setContentTitle("Cooking timers")
            .setContentText(text).setContentIntent(open).setAutoCancel(true).build())
    }

    fun register(bridge: MethodChannel) { channel = bridge }
}
