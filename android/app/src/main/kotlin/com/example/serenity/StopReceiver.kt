package com.serenity.sunrise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Handles Stop action and notification dismissal to ensure alarm audio stops.
 * - For explicit Stop action: also navigates user to success screen.
 * - For notification swipe-dismiss: only stops audio and clears notification.
 */
class StopReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("alarm_id", (System.currentTimeMillis() / 1000).toInt())
        val label = intent.getStringExtra("label") ?: "Alarm"
        val fromDelete = intent.getBooleanExtra("from_delete", false)

        // Stop foreground service (audio)
        try { context.stopService(Intent(context, AlarmForegroundService::class.java)) } catch (_: Exception) {}

        // Cancel the notification
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            nm.cancel(id)
        } catch (_: Exception) {}

        // If this is explicit Stop action, bring app to foreground success screen
        if (!fromDelete) {
            val successIntent = Intent(context, FullScreenAlarmActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("alarm_id", id)
                putExtra("label", label)
                putExtra("is_success", true)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startActivity(successIntent)
            } else {
                context.startActivity(successIntent)
            }
        }
    }
}
