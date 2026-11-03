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
        if (message.data["kind"] == "android_update") {
            val build = message.data["build"]?.toLongOrNull() ?: return
            val version = message.data["version"] ?: return
            if (!version.matches(Regex("[0-9]+\\.[0-9]+\\.[0-9]+"))) return
            val info = packageManager.getPackageInfo(packageName, 0)
            val installed = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
            if (build > installed) AndroidReleaseNotice.show(this, version)
            return
        }
        if (message.data["kind"] == "cooking_invitation") {
            TimerSyncNative.invitation(this, message.data)
            return
        }
        if (message.data["kind"] != "recipe_timer") return
        try { TimerSyncNative.apply(this, JSONObject(message.data as Map<*, *>)) }
        catch (_: Exception) {
            // Permission failures must not create a fake running timer.
            // Snapshot reconciliation retries without an unsolicited notification.
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
        TimerActions.configure(c, uid)
        if (args["guard_only"] == true && !switched) return
        val revisions = JSONObject(p.getString("revisions", "{}")!!)
        val sessions = if (args.containsKey("session_ids")) (args["session_ids"] as List<*>).filterIsInstance<String>().toSet() else if (switched) emptySet<String>() else p.getStringSet("sessions", emptySet())!!
        for (key in RecipeTimers.rows(c).keys().asSequence().toList()) {
            if (key.startsWith("remote:session:") && key.split(":").getOrNull(2) !in sessions) RecipeTimers.cancel(c, key)
        }
        if (switched || !receive) {
            val rows = RecipeTimers.rows(c)
            for (key in rows.keys().asSequence().toList()) {
                if ((key.startsWith("remote:") && !key.startsWith("remote:session:")) || (switched && !p.getString("uid", "").isNullOrEmpty())) {
                    RecipeTimers.cancel(c, key)
                    if (key.startsWith("remote:")) revisions.remove(key.removePrefix("remote:"))
                }
            }
        }
        val editor = p.edit().putString("uid", uid).putString("installation", args["installation_id"] as String).putBoolean("receive", receive)
        editor.putLong("clockOffset", (args["clock_offset_ms"] as? Number)?.toLong() ?: p.getLong("clockOffset", 0L))
        editor.putStringSet("sessions", sessions)
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
        val id = data.getString("timer_id")
        if (!id.startsWith("session:")) return
        val session = id.split(":").getOrNull(1) ?: return
        if (session !in p.getStringSet("sessions", emptySet())!!) return
        require(id.matches(Regex("[A-Za-z0-9:_-]{1,160}")))
        val version = data.getLong("revision")
        val revisions = JSONObject(p.getString("revisions", "{}")!!)
        if (version <= revisions.optLong(id, 0)) return
        val key = "remote:$id"
        val cancelled = data.optString("cancelled") in listOf("1", "true")
        val deadline = data.getLong("deadline_ms") - p.getLong("clockOffset", 0L)
        val extension = data.optInt("extension_seconds", 0)
        if (cancelled || (deadline <= System.currentTimeMillis() && extension <= 0)) {
            RecipeTimers.cancel(c, key)
        } else {
            check(Build.VERSION.SDK_INT < 33 || c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
            val rows = RecipeTimers.rows(c)
            val old = rows.optJSONObject(key)
            val title = data.getString("title")
            if (old == null || old.optLong("deadline") != deadline || old.optString("title") != title || old.optInt("extension_seconds", 0) != extension) {
                rows.put(key, JSONObject().put("deadline", deadline).put("title", title).put("tone", RecipeTimers.tone(c)).put("extension_seconds", extension))
                RecipeTimers.save(c, rows)
                try { if (deadline > System.currentTimeMillis()) RecipeTimers.schedule(c, key, deadline) } catch (error: Exception) {
                    if (old == null) rows.remove(key) else rows.put(key, old)
                    RecipeTimers.save(c, rows); throw error
                }
                RecipeTimerService.stopTimer(c, key)
            }
        }
        // Record only after the OS accepted the operation; failures can retry.
        revisions.put(id, version)
        check(p.edit().putString("revisions", revisions.toString()).commit())
        changed()
    }

    fun invitation(c: Context, data: Map<String, String>) {
        val p = prefs(c)
        if (p.getString("uid", "").isNullOrEmpty() || data["account_uid"] != p.getString("uid", "") || data["target_device"] != p.getString("installation", "")) return
        notice(c, data["title"] ?: "Cooking invitation")
        changed()
    }

    fun notice(c: Context, text: String) {
        if (Build.VERSION.SDK_INT >= 33 && c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = c.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("cooking_invitations", "Cooking invitations", NotificationManager.IMPORTANCE_DEFAULT))
        val open = PendingIntent.getActivity(c, 0, Intent(c, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, "cooking_invitations") else Notification.Builder(c)
        manager.notify(7102, builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm).setContentTitle("Cooking invitation")
            .setContentText(text).setContentIntent(open).setAutoCancel(true).build())
    }

    fun register(bridge: MethodChannel) { channel = bridge }
}

/** Informational release notices; recipients use their own Google Drive location. */
object AndroidReleaseNotice {
    fun show(c: Context, version: String) {
        if (Build.VERSION.SDK_INT >= 33 && c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = c.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("android_updates", "App updates", NotificationManager.IMPORTANCE_DEFAULT))
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, "android_updates") else Notification.Builder(c)
        manager.notify(7103, builder.setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Coffey Table Recipes update")
            .setContentText("Version $version is available in Google Drive.")
            .setStyle(Notification.BigTextStyle().bigText("A new version of Coffey Table Recipes ($version) is available in Google Drive."))
            .build())
    }
}
