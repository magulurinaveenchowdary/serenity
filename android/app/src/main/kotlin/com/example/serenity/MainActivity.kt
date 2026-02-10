package com.serenity.sunrise

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.media.RingtoneManager
import android.os.PowerManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var sunriseWl: PowerManager.WakeLock? = null
    private var ringtoneResult: MethodChannel.Result? = null
    private val RINGTONE_REQ = 10021
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
                            val type = args["type"] as? String
                            val challengeType = (args["challengeType"] as? Number)?.toInt() ?: 0
                            val sunrise = args["sunrise"] as? Boolean ?: false
                            AlarmScheduler.scheduleExact(this, id, whenMs, label, type, challengeType, sunrise)
                            result.success(null)
                        }
                        "cancel" -> {
                            val id = (call.arguments as Number).toInt()
                            AlarmScheduler.cancel(this, id)
                            result.success(null)
                        }
                        "scheduleSunrise" -> {
                            val args = call.arguments as Map<*, *>
                            val id = (args["id"] as Number).toInt()
                            val whenMs = (args["whenMs"] as Number).toLong()
                            val lead = (args["leadMinutes"] as Number).toInt()
                            val label = args["label"] as? String
                            val sunriseAt = whenMs - lead * 60_000L
                            AlarmScheduler.scheduleSunrise(this, id, sunriseAt, label)
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
                        "startFloatingIcon" -> {
                            startService(Intent(this, FloatingService::class.java))
                            result.success(null)
                        }
                        "stopFloatingIcon" -> {
                            stopService(Intent(this, FloatingService::class.java))
                            result.success(null)
                        }
                        "canDrawOverlays" -> {
                            result.success(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.canDrawOverlays(this) else true)
                        }
                        "openOverlaySettings" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
                                startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            }
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("alarm_error", e.message, null)
                }
            }

        // Sunrise control channel for wake lock, screen, brightness
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "serenity/sunrise")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "acquireWakeLock" -> {
                            val pm = getSystemService(POWER_SERVICE) as PowerManager
                            if (sunriseWl == null || !(sunriseWl?.isHeld ?: false)) {
                                sunriseWl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "serenity:sunrise")
                                sunriseWl?.acquire(10 * 60_000L)
                            }
                            result.success(null)
                        }
                        "turnScreenOn" -> {
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O_MR1) {
                                try {
                                    setShowWhenLocked(true)
                                    setTurnScreenOn(true)
                                } catch (_: Exception) {}
                            } else {
                                window.addFlags(
                                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                                )
                            }
                            result.success(null)
                        }
                        "startForegroundIfNeeded" -> {
                            // No-op: activity is foreground; service not required for sunrise
                            result.success(null)
                        }
                        "setBrightness" -> {
                            val v = (call.arguments as Number).toFloat().coerceIn(0f, 1f)
                            val lp = window.attributes
                            lp.screenBrightness = v
                            window.attributes = lp
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("sunrise_error", e.message, null)
                }
            }

        // Ringtone picker channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "serenity/ringtone")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pick" -> {
                        try {
                            val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                            val currentUri = (args["currentUri"] as? String)?.takeIf { it.isNotBlank() }
                            val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                                putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
                                putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Select alarm sound")
                                putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                                putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                                putExtra(
                                    RingtoneManager.EXTRA_RINGTONE_DEFAULT_URI,
                                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                                )
                                if (currentUri != null) {
                                    putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(currentUri))
                                }
                            }
                            ringtoneResult = result
                            startActivityForResult(intent, RINGTONE_REQ)
                        } catch (e: Exception) {
                            result.error("ringtone_error", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == RINGTONE_REQ) {
            val result = ringtoneResult ?: return
            ringtoneResult = null
            if (resultCode == RESULT_OK) {
                try {
                    val uri: Uri? = data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
                    if (uri != null) {
                        val rt = RingtoneManager.getRingtone(this, uri)
                        val title = try { rt.getTitle(this) } catch (_: Exception) { "Custom" }
                        result.success(mapOf("uri" to uri.toString(), "title" to title))
                    } else {
                        result.success(mapOf("uri" to "", "title" to "Default"))
                    }
                } catch (e: Exception) {
                    result.error("ringtone_error", e.message, null)
                }
            } else {
                result.success(null)
            }
        }
    }
}
