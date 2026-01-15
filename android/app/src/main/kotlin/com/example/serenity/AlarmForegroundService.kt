package com.example.serenity

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class AlarmForegroundService : Service() {
    private var ringtone: Ringtone? = null
    private var id: Int = (System.currentTimeMillis() / 1000).toInt()
    private val channelId = "serenity_alarm_service"

    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(channelId, "Alarm Service", NotificationManager.IMPORTANCE_HIGH)
            nm.createNotificationChannel(ch)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        id = intent?.getIntExtra("alarm_id", id) ?: id
        val label = intent?.getStringExtra("label") ?: "Alarm"

        val notif: Notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(label)
            .setContentText("Ringing…")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .build()

        startForeground(id, notif)

        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
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
