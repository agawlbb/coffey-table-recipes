package com.coffeytable.coffey_table_recipes

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.media.*
import android.net.Uri
import android.os.*
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

object RecipeTimers {
    private fun prefs(c: Context) = c.getSharedPreferences("recipe_timers", Context.MODE_PRIVATE)
    fun rows(c: Context): JSONObject = JSONObject(prefs(c).getString("timers", "{}")!!)
    fun save(c: Context, rows: JSONObject) { check(prefs(c).edit().putString("timers", rows.toString()).commit()) }
    fun tone(c: Context): String = prefs(c).getString("tone", "")!!
    fun setTone(c: Context, uri: String) { prefs(c).edit().putString("tone", uri).apply() }
    fun intent(c: Context, key: String): PendingIntent = PendingIntent.getBroadcast(c, 0,
        Intent(c, RecipeTimerReceiver::class.java).setAction("timer").setData(Uri.parse("recipe-timer://alarm/" + Uri.encode(key))).putExtra("key", key),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun schedule(c: Context, key: String, deadline: Long) {
        val alarms = c.getSystemService(AlarmManager::class.java)
        check(Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()) { "Allow Alarms & reminders in settings, then start the timer again." }
        val show = PendingIntent.getActivity(c, 0, Intent(c, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        alarms.setAlarmClock(AlarmManager.AlarmClockInfo(deadline, show), intent(c, key))
    }
    fun cancel(c: Context, key: String) {
        c.getSystemService(AlarmManager::class.java).cancel(intent(c, key))
        val all = rows(c); all.remove(key); save(c, all)
        RecipeTimerService.stopTimer(c, key)
    }
    fun tones(c: Context): List<Map<String, String>> {
        val result = mutableListOf(mapOf("value" to "", "label" to "Default alarm"))
        val manager = RingtoneManager(c); manager.setType(RingtoneManager.TYPE_ALARM)
        val cursor = manager.cursor
        try { while (cursor.moveToNext()) result.add(mapOf("value" to manager.getRingtoneUri(cursor.position).toString(), "label" to cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX))) }
        finally { cursor.close() }
        return result
    }
    fun register(activity: Activity, channel: MethodChannel) {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "list" -> {
                        val all = rows(activity)
                        result.success(all.keys().asSequence().map { key -> mapOf("key" to key, "deadline" to all.getJSONObject(key).getLong("deadline")) }.toList())
                    }
                    "schedule" -> {
                        val manager = activity.getSystemService(AlarmManager::class.java)
                        if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 8102)
                            result.error("permission", "Allow timer notifications, then start the timer again.", null)
                        } else if (Build.VERSION.SDK_INT >= 31 && !manager.canScheduleExactAlarms()) {
                            activity.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:" + activity.packageName)))
                            result.error("permission", "Allow Alarms & reminders, then start the timer again.", null)
                        } else {
                            val key = call.argument<String>("key")!!
                            val deadline = call.argument<Number>("deadline")!!.toLong()
                            require(deadline > System.currentTimeMillis())
                            val all = rows(activity)
                            val previous = all.optJSONObject(key)
                            all.put(key, JSONObject().put("deadline", deadline).put("title", call.argument<String>("title")).put("tone", tone(activity)))
                            save(activity, all)
                            try { schedule(activity, key, deadline) } catch (e: Exception) {
                                if (previous == null) all.remove(key) else all.put(key, previous)
                                save(activity, all); throw e
                            }
                            RecipeTimerService.stopTimer(activity, key)
                            result.success(null)
                        }
                    }
                    "cancel" -> { cancel(activity, call.argument<String>("key")!!); result.success(null) }
                    "settings" -> result.success(mapOf("tone" to tone(activity), "tones" to tones(activity), "mode" to "Android system alarm. Exact-alarm and notification permissions are required. Alarm volume, Do Not Disturb, force-stop and device restrictions can prevent sound."))
                    "setTone" -> { setTone(activity, call.argument<String>("tone")!!); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("timer", e.message ?: "Could not schedule timer", null) }
        }
    }
}

class RecipeTimerReceiver : BroadcastReceiver() {
    override fun onReceive(c: Context, intent: Intent) {
        if (intent.action == "timer") {
            val key = intent.getStringExtra("key") ?: return
            if (!RecipeTimers.rows(c).has(key)) return
            val service = Intent(c, RecipeTimerService::class.java).putExtra("key", key)
            if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(service) else c.startService(service)
        } else {
            // Re-register persisted future alarms after reboot/package replacement or permission grant.
            val all = RecipeTimers.rows(c)
            all.keys().forEach { key ->
                val deadline = all.getJSONObject(key).getLong("deadline")
                if (deadline > System.currentTimeMillis()) try { RecipeTimers.schedule(c, key, deadline) } catch (_: Exception) {}
            }
        }
    }
}

class RecipeTimerService : Service() {
    private val players = mutableMapOf<String, MediaPlayer>()
    companion object {
        private var running: RecipeTimerService? = null
        fun stopTimer(c: Context, key: String) {
            running?.stop(key)
            c.getSystemService(NotificationManager::class.java).cancel(key, 1)
        }
    }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onCreate() { super.onCreate(); running = this }
    private fun stop(key: String) {
        players.remove(key)?.release()
        getSystemService(NotificationManager::class.java).cancel(key, 1)
        if (players.isEmpty()) { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val key = intent?.getStringExtra("key") ?: return START_NOT_STICKY
        if (intent.action == "stop") { RecipeTimers.cancel(this, key); return START_NOT_STICKY }
        val row = RecipeTimers.rows(this).optJSONObject(key) ?: return START_NOT_STICKY
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("cooking_alarms", "Cooking alarms", NotificationManager.IMPORTANCE_HIGH).apply { setSound(null, null) })
        val stopIntent = PendingIntent.getService(this, 0, Intent(this, RecipeTimerService::class.java).setAction("stop").setData(Uri.parse("recipe-timer://stop/"+Uri.encode(key))).putExtra("key",key), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this,"cooking_alarms") else Notification.Builder(this)
        val notification = builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm).setContentTitle(row.optString("title", "Cooking timer")).setContentText("Time is up")
            .setCategory(Notification.CATEGORY_ALARM).setOngoing(true).addAction(Notification.Action.Builder(null, "Stop", stopIntent).build()).build()
        startForeground(8101, notification)
        manager.notify(key,1,notification)
        if (!players.containsKey(key)) {
            try {
                val tone = row.optString("tone").takeIf { it.isNotEmpty() }?.let(Uri::parse) ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                val player = MediaPlayer()
                player.setWakeMode(this, PowerManager.PARTIAL_WAKE_LOCK)
                player.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                player.setDataSource(this,tone); player.isLooping=true; player.prepare(); player.start(); players[key]=player
            } catch (_: Exception) { /* Keep the visible alarm available if sound cannot play. */ }
        }
        return START_NOT_STICKY
    }
    override fun onDestroy() { players.values.forEach { it.release() }; players.clear(); running=null; super.onDestroy() }
}
