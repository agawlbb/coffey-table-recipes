package com.coffeytable.coffey_table_recipes

import android.app.*
import android.content.*
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel

object NotificationPreferences {
    val channels = linkedMapOf("invitations" to "cooking_invitations", "timers" to "cooking_alarms", "pendingSaves" to "pending_saves", "updates" to "android_updates")
    private val labels = mapOf("invitations" to "Cooking invitations", "timers" to "Cooking timers", "pendingSaves" to "Pending saves", "updates" to "App updates")
    private fun prefs(c: Context) = c.getSharedPreferences("notification_preferences", Context.MODE_PRIVATE)
    fun enabled(c: Context, category: String) = prefs(c).getBoolean(category, true)
    fun allowed(c: Context, category: String): Boolean {
        val manager = c.getSystemService(NotificationManager::class.java)
        return enabled(c, category) && manager.areNotificationsEnabled() && (Build.VERSION.SDK_INT < 26 || manager.getNotificationChannel(channels.getValue(category))?.importance != NotificationManager.IMPORTANCE_NONE)
    }
    fun createChannels(c: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = c.getSystemService(NotificationManager::class.java)
            channels.forEach { (key, id) -> manager.createNotificationChannel(NotificationChannel(id, labels[key]!!, if (key == "timers") NotificationManager.IMPORTANCE_HIGH else NotificationManager.IMPORTANCE_DEFAULT).apply { if (key == "timers") setSound(null, null) }) }
        }
    }
    fun register(activity: Activity, channel: MethodChannel) {
        createChannels(activity)
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "read" -> {
                        RecipeTimers.reconcileNotifications(activity)
                        PendingSaveNotifications.refresh(activity)
                        val manager = activity.getSystemService(NotificationManager::class.java)
                        result.success(channels.keys.associateWith { enabled(activity, it) } + mapOf("blockedChannels" to channels.filter { (_, id) -> Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(id)?.importance == NotificationManager.IMPORTANCE_NONE }.keys.toList()))
                    }
                    "set" -> {
                        val category = call.argument<String>("category")!!
                        val enabled = call.argument<Boolean>("enabled")!!
                        require(channels.containsKey(category))
                        check(prefs(activity).edit().putBoolean(category, enabled).commit())
                        if (category == "timers") RecipeTimers.reconcileNotifications(activity)
                        if (category == "pendingSaves") PendingSaveNotifications.refresh(activity)
                        if (!enabled && category == "invitations") activity.getSystemService(NotificationManager::class.java).cancel(7102)
                        if (!enabled && category == "updates") activity.getSystemService(NotificationManager::class.java).cancel(7103)
                        result.success(null)
                    }
                    "openSettings" -> {
                        val category = call.argument<String>("category")
                        val intent = if (Build.VERSION.SDK_INT >= 26 && category != null) Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName).putExtra(Settings.EXTRA_CHANNEL_ID, channels[category])
                            else Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                        try { activity.startActivity(intent) }
                        catch (_: ActivityNotFoundException) { activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:" + activity.packageName))) }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("notifications", e.message, null) }
        }
    }
}
