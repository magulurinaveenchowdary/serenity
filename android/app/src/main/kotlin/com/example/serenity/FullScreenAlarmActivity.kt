package com.serenity.sunrise

import android.app.AlarmManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.PowerManager
import android.view.WindowManager

class FullScreenAlarmActivity : FlutterActivity() {
    private var sunriseWl: PowerManager.WakeLock? = null
    override fun onCreate(savedInstanceState: Bundle?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val km = getSystemService(android.content.Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
            km.requestDismissKeyguard(this, null)
        } else {
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON
            )
        }
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_FULLSCREEN)
        super.onCreate(savedInstanceState)
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val id = intent.getIntExtra("alarm_id", (System.currentTimeMillis() / 1000).toInt())
        val label = intent.getStringExtra("label") ?: "Alarm"
        val type = intent.getStringExtra("type") ?: "alarm"
        val challengeType = intent.getIntExtra("challengeType", 0)
        val sunrise = intent.getBooleanExtra("sunrise", false)
        android.widget.Toast.makeText(this, "Challenge: $challengeType", android.widget.Toast.LENGTH_LONG).show()
        val isSunrise = intent.getBooleanExtra("is_sunrise", false)
        val isSuccess = intent.getBooleanExtra("is_success", false)

        if (isSuccess) {
            try { stopService(Intent(applicationContext, AlarmForegroundService::class.java)) } catch (_: Exception) {}
            try {
                val nm = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
                nm.cancel(id)
            } catch (_: Exception) {}
        }

        if (!isSunrise && !isSuccess) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "serenity/current_alarm")
                .invokeMethod("push", mapOf("alarm_id" to id, "label" to label, "type" to type, "challengeType" to challengeType, "sunrise" to sunrise))
        }

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
                            val type = args["type"] as? String
                            val challengeType = (args["challengeType"] as? Number)?.toInt() ?: 0
                            val sunrise = args["sunrise"] as? Boolean ?: false
                            AlarmScheduler.scheduleExact(this, alarmId, whenMs, lbl, type, challengeType, sunrise)
                            result.success(null)
                        }
                        "cancel" -> {
                            val alarmId = (call.arguments as Number).toInt()
                            AlarmScheduler.cancel(this, alarmId)
                            result.success(null)
                        }
                        "scheduleSunrise" -> {
                            val args = call.arguments as Map<*, *>
                            val alarmId = (args["id"] as Number).toInt()
                            val whenMs = (args["whenMs"] as Number).toLong()
                            val lead = (args["leadMinutes"] as Number).toInt()
                            val lbl = args["label"] as? String
                            val sunriseAt = whenMs - lead * 60_000L
                            AlarmScheduler.scheduleSunrise(this, alarmId, sunriseAt, lbl)
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
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val id = intent.getIntExtra("alarm_id", (System.currentTimeMillis() / 1000).toInt())
        val label = intent.getStringExtra("label") ?: "Alarm"
        val challengeType = intent.getIntExtra("challengeType", 0)
        val isSuccess = intent.getBooleanExtra("is_success", false)

        // Stop service + cancel notification when success is requested
        if (isSuccess) {
            try { stopService(Intent(applicationContext, AlarmForegroundService::class.java)) } catch (_: Exception) {}
            try {
                val nm = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
                nm.cancel(id)
            } catch (_: Exception) {}
        }

        // Inform Flutter via method channel to navigate appropriately
        val engine = flutterEngine ?: return
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, "serenity/current_alarm")
        try {
            if (isSuccess) {
                ch.invokeMethod("tap", mapOf("alarm_id" to id, "label" to label, "type" to intent.getStringExtra("type"), "challengeType" to challengeType))
            } else {
                val type = intent.getStringExtra("type")
                val sunrise = intent.getBooleanExtra("sunrise", false)
                val args = mutableMapOf<String, Any?>(
                    "alarm_id" to id, 
                    "label" to label, 
                    "type" to type, 
                    "challengeType" to challengeType,
                    "sunrise" to sunrise
                )
                /*if (type == "post_call") {
                    args["phone"] = intent.getStringExtra("phone")
                    args["duration"] = intent.getStringExtra("duration")
                }*/
                ch.invokeMethod("push", args)
            }
        } catch (_: Exception) {}
    }

    override fun getInitialRoute(): String? {
        val id = intent.getIntExtra("alarm_id", (System.currentTimeMillis() / 1000).toInt())
        val label = intent.getStringExtra("label") ?: "Alarm"
        val type = intent.getStringExtra("type") ?: "alarm"
        val challengeType = intent.getIntExtra("challengeType", 0)
        val isSunrise = intent.getBooleanExtra("is_sunrise", false)
        val isSuccess = intent.getBooleanExtra("is_success", false)
        // Provide an initial route that Flutter can parse to show Ringing UI
        val encodedLabel = Uri.encode(label)
        return when {
            isSuccess -> "success?label=$encodedLabel"
            isSunrise -> "sunrise?alarm_id=$id&label=$encodedLabel"
            type == "reminder" -> "reminder_trigger?alarm_id=$id&label=$encodedLabel"
            /*type == "post_call" -> {
                val phone = intent.getStringExtra("phone") ?: ""
                val duration = intent.getStringExtra("duration") ?: ""
                "post_call?phone=$phone&duration=$duration"
            }*/
            else -> "ringing?alarm_id=$id&label=$encodedLabel&challengeType=$challengeType&sunrise=${intent.getBooleanExtra("sunrise", false)}"
        }
    }
}
