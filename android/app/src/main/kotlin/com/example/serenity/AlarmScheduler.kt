package com.example.serenity

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

object AlarmScheduler {
    private const val REQ_BASE = 40000

    fun scheduleExact(context: Context, id: Int, triggerAtMillis: Long, label: String?) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra("alarm_id", id)
            putExtra("label", label ?: "Alarm")
        }
        val pi = PendingIntent.getBroadcast(
            context,
            REQ_BASE + id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
        } else {
            am.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, pi)
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
