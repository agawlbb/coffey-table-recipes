package com.coffeytable.coffey_table_recipes

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.security.MessageDigest

/** Device-side reminders work even when Flutter is suspended or stopped. */
object PendingSaveNotifications {
    private const val STORE = "pending_save_notifications"
    private fun prefs(c: Context) = c.getSharedPreferences(STORE, Context.MODE_PRIVATE)
    private fun intent(c: Context, key: String): PendingIntent = PendingIntent.getBroadcast(c, 0,
        Intent(c, PendingSaveReceiver::class.java).setData(Uri.parse("ctr-pending:$key")),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun arm(c: Context, key: String, deadline: Long) {
        val alarms = c.getSystemService(AlarmManager::class.java)
        if (Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms())
            alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, maxOf(System.currentTimeMillis() + 100, deadline), intent(c, key))
        else alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, maxOf(System.currentTimeMillis() + 100, deadline), intent(c, key))
    }
    fun restore(c: Context) {
        for ((key, value) in prefs(c).all.filterKeys { it.contains(":") }) {
            val row = JSONObject(value as String)
            if (!row.optBoolean("fired")) arm(c, key, row.getLong("deadline"))
        }
    }
    fun deliver(c: Context, key: String) {
        val raw = prefs(c).getString(key, null) ?: return
        val row = JSONObject(raw)
        if (row.optBoolean("fired")) return
        if (System.currentTimeMillis() < row.getLong("deadline")) { arm(c, key, row.getLong("deadline")); return }
        val manager = c.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("pending_saves", "Changes waiting to sync", NotificationManager.IMPORTANCE_DEFAULT))
        if (Build.VERSION.SDK_INT >= 33 && c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val open = PendingIntent.getActivity(c, 0, Intent(c, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(c, "pending_saves") else Notification.Builder(c)
        manager.notify(key, 0, builder.setSmallIcon(c.applicationInfo.icon).setContentTitle("Change waiting to sync")
            .setContentText("Saved on this device, but the server has not confirmed it after one minute.")
            .setStyle(Notification.BigTextStyle().bigText("Saved on this device, but the server has not confirmed it after one minute. Open Coffey Table Recipes to check synchronization."))
            .setContentIntent(open).setAutoCancel(true).build())
        prefs(c).edit().putString(key, row.put("fired", true).toString()).commit()
    }
    fun register(activity: Activity, channel: MethodChannel) {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "update") { result.notImplemented(); return@setMethodCallHandler }
            try {
                val scope = call.argument<String>("scope") ?: error("Missing account")
                val prefix = MessageDigest.getInstance("SHA-256").digest(scope.toByteArray()).joinToString("") { "%02x".format(it) } + ":"
                val changes = call.argument<List<Map<String, Any>>>("changes") ?: emptyList()
                val wanted = changes.associate { prefix + it["id"] to (it["deadline"] as Number).toLong() }
                val saved = prefs(activity)
                for (key in saved.all.keys.filter { it.startsWith(prefix) && it !in wanted }) {
                    activity.getSystemService(AlarmManager::class.java).cancel(intent(activity, key))
                    activity.getSystemService(NotificationManager::class.java).cancel(key, 0)
                    saved.edit().remove(key).commit()
                }
                for ((key, deadline) in wanted) {
                    if (!saved.contains(key)) {
                        check(saved.edit().putString(key, JSONObject().put("deadline", deadline).put("fired", false).toString()).commit())
                        arm(activity, key, deadline)
                    }
                }
                restore(activity)
                if (wanted.isNotEmpty() && Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    // Ask once; denial is also surfaced by the in-app status.
                    if (!saved.getBooleanCompat("permission_requested")) {
                        saved.edit().putString("permission_requested", "true").commit()
                        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 602)
                    }
                    result.error("notifications_denied", "Allow notifications in device settings.", null)
                } else result.success(null)
            } catch (e: Exception) { result.error("pending_save", e.message, null) }
        }
    }
    private fun android.content.SharedPreferences.getBooleanCompat(key: String) = getString(key, null) == "true"
}

class PendingSaveReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED || intent.action == AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED) PendingSaveNotifications.restore(context)
        else intent.data?.schemeSpecificPart?.let { PendingSaveNotifications.deliver(context, it) }
    }
}
