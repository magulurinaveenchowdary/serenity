package com.serenity.sunrise

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class SnoozeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("alarm_id", (System.currentTimeMillis() / 1000).toInt())
        val label = intent.getStringExtra("label") ?: "Alarm"

        // Read snooze minutes from FlutterSharedPreferences if present
        val sp = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val mins = try { sp.getInt("flutter.snooze_minutes", 5) } catch (_: Exception) { 5 }
        val triggerAt = System.currentTimeMillis() + mins * 60_000L

        val type = intent.getStringExtra("type") ?: "alarm"
        val challengeType = intent.getIntExtra("challengeType", 0)
        // Reschedule the same alarm ID
        try { AlarmScheduler.scheduleExact(context, id, triggerAt, label, type, challengeType) } catch (_: Exception) {}

        // Stop ringing service (if running)
        try { context.stopService(Intent(context, AlarmForegroundService::class.java)) } catch (_: Exception) {}

        // Dismiss current notification
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(id)
        } catch (_: Exception) {}
    }
}
