package com.serenity.sunrise

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
        val type = intent.getStringExtra("type") ?: "alarm"
        val challengeType = intent.getIntExtra("challengeType", 0)
        val sunrise = intent.getBooleanExtra("sunrise", false)

        // Wake the device and turn the screen on
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val wl = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                "serenity:alarm_wakelock"
            )
            wl.acquire(60_000L)
            android.util.Log.d("SerenityAlarm", "Alarm ring received for id $id at ${System.currentTimeMillis()}")
        } catch (_: Exception) {}

        // Full-screen activity intent
        val fsIntent = Intent(context, FullScreenAlarmActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            putExtra("alarm_id", id)
            putExtra("label", label)
            putExtra("type", type)
            putExtra("challengeType", challengeType)
            putExtra("sunrise", sunrise)
        }
        
        // Try to launch the activity immediately. 
        // Note: Android 10+ might block this unless we have 'Draw over other apps' or screen is off.
        try {
            context.startActivity(fsIntent)
        } catch (e: Exception) {
            android.util.Log.e("SerenityAlarm", "Failed to start FullScreenAlarmActivity directly: ${e.message}")
        }

        val fullScreenPi = PendingIntent.getActivity(
            context,
            id,
            fsIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Notification tap should also open it
        val tapPi = PendingIntent.getActivity(
            context,
            id + 5000,
            fsIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Notification channel
        val channelId = "serenity_alarm_channel_v4"
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            var ch = nm.getNotificationChannel(channelId)
            if (ch == null) {
                ch = NotificationChannel(channelId, "Alarms", NotificationManager.IMPORTANCE_MAX).apply {
                    description = "Serenity alarm notifications"
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    setBypassDnd(true)
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 500, 250, 500)
                }
                nm.createNotificationChannel(ch)
            }
        }

        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(label)
            .setContentText("Wake up! it is time.")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(fullScreenPi, true)
            .setContentIntent(tapPi)
            .setAutoCancel(false)
            .setOngoing(true) // Alarms should be ongoing until dismissed

        // Action Action Pi
        val snoozeIntent = Intent(context, SnoozeReceiver::class.java).apply {
            putExtra("alarm_id", id); putExtra("label", label); putExtra("type", type); putExtra("challengeType", challengeType)
        }
        val snoozePi = PendingIntent.getBroadcast(context, id+6000, snoozeIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        builder.addAction(0, "Snooze", snoozePi)

        if (challengeType == 0) {
            val stopIntent = Intent(context, StopReceiver::class.java).apply {
                putExtra("alarm_id", id); putExtra("label", label); putExtra("type", type); putExtra("challengeType", challengeType)
            }
            val stopPi = PendingIntent.getBroadcast(context, id+7000, stopIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            builder.addAction(0, "Dismiss", stopPi)
        }

        val notif = builder.build()
        notif.flags = notif.flags or Notification.FLAG_INSISTENT or Notification.FLAG_ONGOING_EVENT

        // Log and Toast for debugging
        android.util.Log.d("SerenityAlarm", "Posting notification and starting service for id $id")
        try {
            android.widget.Toast.makeText(context, "Alarm Ringing: $label", android.widget.Toast.LENGTH_LONG).show()
        } catch (_: Exception) {}

        // Start service for background audio
        val svcIntent = Intent(context, AlarmForegroundService::class.java).apply {
            putExtra("alarm_id", id); putExtra("label", label); putExtra("type", type); putExtra("challengeType", challengeType); putExtra("sunrise", sunrise)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(svcIntent)
        } else {
            context.startService(svcIntent)
        }

        nm.notify(id, notif)
    }
}
