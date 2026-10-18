package com.julianamarques.galaxybridge.bridge

import android.telephony.TelephonyManager
import com.julianamarques.galaxybridge.protocol.CallState

object CallTracker {
    @Volatile var current: CallState? = null
        private set

    @Volatile var onChange: ((CallState) -> Unit)? = null

    private var callerName: String? = null
    private var callerNumber: String? = null
    private var voicemailAnswering = false
    private var answeredAt = 0L
    private var counter = 0

    @Synchronized
    fun phoneStateChanged(state: Int) {
        val call = current
        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> if (call == null) {
                publish(CallState(nextId(), CallState.RINGING, CallState.INCOMING, callerNumber, callerName))
            }
            TelephonyManager.CALL_STATE_OFFHOOK -> when {
                call == null -> publish(CallState(nextId(), CallState.ACTIVE, CallState.OUTGOING, callerNumber, callerName))
                call.state == CallState.RINGING -> {
                    answeredAt = System.currentTimeMillis()
                    publish(call.copy(state = if (voicemailAnswering) CallState.VOICEMAIL else CallState.ACTIVE))
                }
            }
            TelephonyManager.CALL_STATE_IDLE -> {
                callerName = null
                callerNumber = null
                voicemailAnswering = false
                if (call != null) {
                    current = null
                    onChange?.invoke(call.copy(state = CallState.ENDED))
                }
            }
        }
    }

    @Synchronized
    fun callerChanged(name: String?, number: String?, voicemail: Boolean) {
        callerName = name
        callerNumber = number
        val call = current ?: return
        val justAnswered = call.state == CallState.ACTIVE && System.currentTimeMillis() - answeredAt < VOICEMAIL_WINDOW_MS
        if (voicemail && call.state == CallState.RINGING) voicemailAnswering = true
        val state = if (voicemail && justAnswered) CallState.VOICEMAIL else call.state
        if (call.name != name || call.number != number || call.state != state) {
            publish(call.copy(name = name, number = number, state = state))
        }
    }

    private const val VOICEMAIL_WINDOW_MS = 3_000L

    private fun publish(call: CallState) {
        current = call
        onChange?.invoke(call)
    }

    private fun nextId(): String {
        counter += 1
        return "${System.currentTimeMillis()}-$counter"
    }
}
