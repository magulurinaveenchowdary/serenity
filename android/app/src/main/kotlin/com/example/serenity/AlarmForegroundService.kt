package com.serenity.sunrise

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class AlarmForegroundService : Service() {
    private var ringtone: Ringtone? = null
    private var id: Int = (System.currentTimeMillis() / 1000).toInt()
    private val channelId = "serenity_alarm_channel_v4" // Matched to AlarmReceiver's channel

    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Ensure channel exists with High Priority/Max Importance for alarms
            val ch = NotificationChannel(channelId, "Alarms", NotificationManager.IMPORTANCE_MAX).apply {
                description = "Serenity alarm notifications"
                setBypassDnd(true)
                enableVibration(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(ch)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        id = intent?.getIntExtra("alarm_id", id) ?: id
        val label = intent?.getStringExtra("label") ?: "Alarm"

        // 1. Full Screen Intent (Heads Up)
        val fsIntent = Intent(this, FullScreenAlarmActivity::class.java).apply {
            this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("alarm_id", id)
            putExtra("label", label)
        }
        val fullScreenPi = PendingIntent.getActivity(
            this,
            id,
            fsIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 2. Content Tap Intent -> Open App (Ringing Screen)
        val tapIntent = Intent(this, FullScreenAlarmActivity::class.java).apply {
            this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("alarm_id", id)
            putExtra("label", label)
            // Removed is_success=true so it opens the Ringing UI instead of dismissing
        }
        val contentPi = PendingIntent.getActivity(
            this,
            id + 1000,
            tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 3. Snooze Action
        val snoozeIntent = Intent(this, SnoozeReceiver::class.java).apply {
            putExtra("alarm_id", id)
            putExtra("label", label)
        }
        val snoozePi = PendingIntent.getBroadcast(
            this,
            id + 2000,
            snoozeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 4. Stop Action
        val stopIntent = Intent(this, StopReceiver::class.java).apply {
            putExtra("alarm_id", id)
            putExtra("label", label)
        }
        val stopPi = PendingIntent.getBroadcast(
            this,
            id + 3000,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 5. Delete Intent (Swipe away)
        val deleteIntent = Intent(this, StopReceiver::class.java).apply {
            putExtra("alarm_id", id)
            putExtra("label", label)
            putExtra("from_delete", true)
        }
        val deletePi = PendingIntent.getBroadcast(
            this,
            id + 4000,
            deleteIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(label)
            .setContentText("Ringing…")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setFullScreenIntent(fullScreenPi, true)
            .setContentIntent(contentPi)

        val challengeType = intent?.getIntExtra("challengeType", 0) ?: 0
        if (challengeType == 0) {
            builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Dismiss", stopPi)
        }
        
        builder.addAction(android.R.drawable.ic_lock_idle_alarm, "Snooze", snoozePi)
            .setDeleteIntent(deletePi)
        
        val notif = builder.build()

        // Start Foreground with the rich notification
        startForeground(id, notif)

        val sp = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        // Flutter SharedPreferences uses "flutter." prefix for all keys
        val key = "flutter.alarm_sound_$id"
        val saved = sp.getString(key, null)
        val uri = try {
            if (!saved.isNullOrBlank()) Uri.parse(saved) else RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        } catch (e: Exception) {
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        }
        ringtone = RingtoneManager.getRingtone(this, uri)
        try {
            ringtone?.isLooping = true
        } catch (_: Exception) {}
        try {
            ringtone?.play()
        } catch (_: Exception) {}

        return START_STICKY
    }

    override fun onDestroy() {
        try { ringtone?.stop() } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
