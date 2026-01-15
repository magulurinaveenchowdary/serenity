package com.example.serenity

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONArray

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val sp = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val json = sp.getString("flutter.alarms", "") ?: ""
        if (json.isEmpty()) return
        try {
            val arr = JSONArray(json)
            val now = java.util.Calendar.getInstance()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val id = o.optInt("id", (System.currentTimeMillis() / 1000).toInt())
                val hour = o.optInt("hour", 0)
                val minute = o.optInt("minute", 0)
                val isAm = o.optBoolean("isAm", true)
                val label = o.optString("label", "Alarm")

                val h24 = (hour % 12) + if (isAm) 0 else 12
                val cal = java.util.Calendar.getInstance().apply {
                    set(java.util.Calendar.HOUR_OF_DAY, h24)
                    set(java.util.Calendar.MINUTE, minute)
                    set(java.util.Calendar.SECOND, 0)
                    set(java.util.Calendar.MILLISECOND, 0)
                    if (before(now)) add(java.util.Calendar.DAY_OF_MONTH, 1)
                }
                AlarmScheduler.scheduleExact(context, id, cal.timeInMillis, label)
            }
        } catch (_: Exception) {
        }
    }
}
