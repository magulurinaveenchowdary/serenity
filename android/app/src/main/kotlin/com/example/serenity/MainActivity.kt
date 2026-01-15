package com.example.serenity

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "serenity/alarm_manager")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "scheduleExact" -> {
                            val args = call.arguments as Map<*, *>
                            val id = (args["id"] as Number).toInt()
                            val whenMs = (args["whenMs"] as Number).toLong()
                            val label = args["label"] as? String
                            AlarmScheduler.scheduleExact(this, id, whenMs, label)
                            result.success(null)
                        }
                        "cancel" -> {
                            val id = (call.arguments as Number).toInt()
                            AlarmScheduler.cancel(this, id)
                            result.success(null)
                        }
                        "stopRinging" -> {
                            try {
                                stopService(Intent(applicationContext, AlarmForegroundService::class.java))
                            } catch (_: Exception) {}
                            // Optionally cancel the posted notification if id provided
                            try {
                                val arg = call.arguments
                                val id = when (arg) {
                                    is Number -> arg.toInt()
                                    is Map<*, *> -> (arg["id"] as? Number)?.toInt()
                                    else -> null
                                }
                                if (id != null) {
                                    val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                                    nm.cancel(id)
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
}
