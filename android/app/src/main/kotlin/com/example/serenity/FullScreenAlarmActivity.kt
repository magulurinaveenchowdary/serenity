package com.example.serenity

import android.app.AlarmManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class FullScreenAlarmActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val id = intent.getIntExtra("alarm_id", (System.currentTimeMillis() / 1000).toInt())
        val label = intent.getStringExtra("label") ?: "Alarm"
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "serenity/current_alarm")
            .invokeMethod("push", mapOf("alarm_id" to id, "label" to label))

        // Also register the alarm manager channel for this engine so Stop/Snooze works
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "serenity/alarm_manager")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "scheduleExact" -> {
                            val args = call.arguments as Map<*, *>
                            val alarmId = (args["id"] as Number).toInt()
                            val whenMs = (args["whenMs"] as Number).toLong()
                            val lbl = args["label"] as? String
                            AlarmScheduler.scheduleExact(this, alarmId, whenMs, lbl)
                            result.success(null)
                        }
                        "cancel" -> {
                            val alarmId = (call.arguments as Number).toInt()
                            AlarmScheduler.cancel(this, alarmId)
                            result.success(null)
                        }
                        "stopRinging" -> {
                            try {
                                stopService(Intent(applicationContext, AlarmForegroundService::class.java))
                            } catch (_: Exception) {}
                            // Cancel the posted notification if id provided
                            try {
                                val arg = call.arguments
                                val nid = when (arg) {
                                    is Number -> arg.toInt()
                                    is Map<*, *> -> (arg["id"] as? Number)?.toInt()
                                    else -> null
                                }
                                if (nid != null) {
                                    val nm = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
                                    nm.cancel(nid)
                                }
                            } catch (_: Exception) {}
                            result.success(null)
                        }
                        "finishActivity" -> {
                            try { finish() } catch (_: Exception) {}
                            result.success(null)
                        }
                        "openExactAlarmSettings" -> {
                            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(null)
                        }
                        "isExactAlarmAllowed" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                val am = getSystemService(ALARM_SERVICE) as AlarmManager
                                result.success(am.canScheduleExactAlarms())
                            } else {
                                result.success(true)
                            }
                        }
                        "openNotificationSettings" -> {
                            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                }
                            } else {
                                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                    data = Uri.fromParts("package", packageName, null)
                                }
                            }
                            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(null)
                        }
                        "openBatteryOptimizationSettings" -> {
                            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("alarm_error", e.message, null)
                }
            }
    }

    override fun getInitialRoute(): String? {
        val id = intent.getIntExtra("alarm_id", (System.currentTimeMillis() / 1000).toInt())
        val label = intent.getStringExtra("label") ?: "Alarm"
        // Provide an initial route that Flutter can parse to show Ringing UI
        val encodedLabel = Uri.encode(label)
        return "ringing?alarm_id=$id&label=$encodedLabel"
    }
}
