package com.example.serenity

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("alarm_id", (System.currentTimeMillis() / 1000).toInt())
        val label = intent.getStringExtra("label") ?: "Alarm"

        // Wake the device and turn the screen on
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val wl = pm.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                "serenity:alarm_wakelock"
            )
            wl.acquire(60_000)
        } catch (_: Exception) {}

        // Full-screen activity intent
        val fsIntent = Intent(context, FullScreenAlarmActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("alarm_id", id)
            putExtra("label", label)
        }
        val fullScreenPi = PendingIntent.getActivity(
            context,
            id,
            fsIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Notification channel
        val channelId = "serenity_alarm_channel"
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(channelId, "Alarms", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Serenity alarm notifications"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(ch)
        }

        // Full-screen notification
        val notif = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(label)
            .setContentText("It’s time ⏰")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(fullScreenPi, true)
            .setAutoCancel(true)
            .build()

        // Start foreground service for audio
        val svcIntent = Intent(context, AlarmForegroundService::class.java).apply {
            putExtra("alarm_id", id)
            putExtra("label", label)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(svcIntent)
        } else {
            context.startService(svcIntent)
        }

        nm.notify(id, notif)
    }
}
