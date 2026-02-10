package com.serenity.sunrise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.TelephonyManager
import android.util.Log

/*
class CallReceiver : BroadcastReceiver() {
    companion object {
        private var lastState = TelephonyManager.CALL_STATE_IDLE
        private var isIncoming = false
        private var savedNumber: String? = null
        private var callStartTime: Long = 0
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d("CallReceiver", "onReceive: ${intent.action}")
        if (intent.action == "android.intent.action.NEW_OUTGOING_CALL") {
            savedNumber = intent.extras?.getString("android.intent.extra.PHONE_NUMBER")
            Log.d("CallReceiver", "Outgoing call number: $savedNumber")
        } else {
            val stateStr = intent.extras?.getString(TelephonyManager.EXTRA_STATE)
            val number = intent.extras?.getString(TelephonyManager.EXTRA_INCOMING_NUMBER)
            Log.d("CallReceiver", "Phone State: $stateStr, Number: $number")
            var state = 0
            if (stateStr == TelephonyManager.EXTRA_STATE_IDLE) {
                state = TelephonyManager.CALL_STATE_IDLE
            } else if (stateStr == TelephonyManager.EXTRA_STATE_OFFHOOK) {
                state = TelephonyManager.CALL_STATE_OFFHOOK
            } else if (stateStr == TelephonyManager.EXTRA_STATE_RINGING) {
                state = TelephonyManager.CALL_STATE_RINGING
            }

            onCallStateChanged(context, state, number)
        }
    }

    private fun onCallStateChanged(context: Context, state: Int, number: String?) {
        if (lastState == state) {
            return
        }
        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> {
                isIncoming = true
                callStartTime = System.currentTimeMillis()
                savedNumber = number
            }
            TelephonyManager.CALL_STATE_OFFHOOK -> {
                if (lastState != TelephonyManager.CALL_STATE_RINGING) {
                    isIncoming = false
                    callStartTime = System.currentTimeMillis()
                }
            }
            TelephonyManager.CALL_STATE_IDLE -> {
                if (lastState == TelephonyManager.CALL_STATE_RINGING) {
                    // Missed call
                    showPostCall(context, "Missed Call", savedNumber, 0)
                } else if (isIncoming) {
                    val duration = (System.currentTimeMillis() - callStartTime) / 1000
                    showPostCall(context, "Incoming Call", savedNumber, duration)
                } else {
                    val duration = (System.currentTimeMillis() - callStartTime) / 1000
                    showPostCall(context, "Outgoing Call", savedNumber, duration)
                }
            }
        }
        lastState = state
    }

    private fun showPostCall(context: Context, type: String, number: String?, durationSeconds: Long) {
        val durationStr = String.format("%02d:%02d", durationSeconds / 60, durationSeconds % 60)
        val intent = Intent(context, FullScreenAlarmActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("alarm_id", (System.currentTimeMillis() / 1000).toInt())
            putExtra("label", type)
            putExtra("type", "post_call")
            putExtra("phone", number ?: "Private")
            putExtra("duration", durationStr)
        }
        context.startActivity(intent)
    }
}
*/
