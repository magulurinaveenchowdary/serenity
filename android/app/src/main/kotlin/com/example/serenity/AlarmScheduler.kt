package com.serenity.sunrise

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.AlarmManager.AlarmClockInfo
import android.provider.Settings
import android.content.Context
import android.content.Intent
import android.os.Build

object AlarmScheduler {
    private const val REQ_BASE = 40000

    fun scheduleExact(context: Context, id: Int, triggerAtMillis: Long, label: String?, type: String?, challengeType: Int = 0, sunrise: Boolean = false) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra("alarm_id", id)
            putExtra("label", label ?: "Alarm")
            putExtra("type", type ?: "alarm")
            putExtra("challengeType", challengeType)
            putExtra("sunrise", sunrise)
        }
        val pi = PendingIntent.getBroadcast(
            context,
            REQ_BASE + id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Prefer AlarmClock for user-visible alarms to avoid OEM delays and exact alarm permission
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            android.util.Log.d("SerenityAlarm", "Scheduling alarm $id for $triggerAtMillis Ms")
            val showIntent = Intent(context, FullScreenAlarmActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                putExtra("alarm_id", id)
                putExtra("label", label ?: "Alarm")
                putExtra("type", type ?: "alarm")
                putExtra("challengeType", challengeType)
                putExtra("sunrise", sunrise)
            }
            val showPi = PendingIntent.getActivity(
                context,
                REQ_BASE + id + 1,
                showIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            am.setAlarmClock(AlarmClockInfo(triggerAtMillis, showPi), pi)
            return
        }

        // Fallback paths for very old devices
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
        } else {
            am.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
        }
    }

    fun scheduleSunrise(context: Context, id: Int, triggerAtMillis: Long, label: String?) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val activityIntent = Intent(context, FullScreenAlarmActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("alarm_id", id)
            putExtra("label", label ?: "Alarm")
            putExtra("type", "alarm") // Sunrise implies alarm type for now
            putExtra("is_sunrise", true)
        }

        val opPi = PendingIntent.getActivity(
            context,
            REQ_BASE + id + 2,
            activityIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            // Use AlarmClock to ensure timely launch and proper user experience
            am.setAlarmClock(AlarmClockInfo(triggerAtMillis, opPi), opPi)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, opPi)
        } else {
            am.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, opPi)
        }
    }

    fun cancel(context: Context, id: Int) {
        val intent = Intent(context, AlarmReceiver::class.java)
        val pi = PendingIntent.getBroadcast(
            context,
            REQ_BASE + id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pi)
    }
}
