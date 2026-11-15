package com.julianamarques.galaxybridge.bridge

import android.telephony.TelephonyManager
import com.julianamarques.galaxybridge.protocol.CallState
import kotlin.concurrent.thread

object CallTracker {
    @Volatile var current: CallState? = null
        private set

    @Volatile var onChange: ((CallState) -> Unit)? = null
    @Volatile var wasDeclined: ((Long) -> Boolean)? = null

    private var callerName: String? = null
    private var callerNumber: String? = null
    private var callerContact: String? = null
    private var placed: Placed? = null
    private var voicemailAnswering = false
    private var answeredAt = 0L
    private var ringingAt = 0L
    private var counter = 0

    private data class Placed(val number: String, val contact: PhoneContacts.Match?, val at: Long)

    @Synchronized
    fun placing(number: String, contact: PhoneContacts.Match?) {
        placed = Placed(number, contact, System.currentTimeMillis())
    }

    @Synchronized
    fun phoneStateChanged(state: Int) {
        val call = current
        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> if (call == null) {
                ringingAt = System.currentTimeMillis()
                publish(CallState(nextId(), CallState.RINGING, CallState.INCOMING, callerNumber, callerName, callerContact))
            }
            TelephonyManager.CALL_STATE_OFFHOOK -> when {
                call == null -> {
                    val dialed = placed?.takeIf { System.currentTimeMillis() - it.at < PLACED_WINDOW_MS }
                    placed = null
                    publish(
                        CallState(
                            nextId(),
                            CallState.ACTIVE,
                            CallState.OUTGOING,
                            callerNumber ?: dialed?.number,
                            callerName ?: dialed?.contact?.name,
                            callerContact ?: dialed?.contact?.key,
                        ),
                    )
                }
                call.state == CallState.RINGING -> {
                    answeredAt = System.currentTimeMillis()
                    publish(call.copy(state = if (voicemailAnswering) CallState.VOICEMAIL else CallState.ACTIVE))
                }
            }
            TelephonyManager.CALL_STATE_IDLE -> {
                callerName = null
                callerNumber = null
                callerContact = null
                voicemailAnswering = false
                if (call != null) {
                    current = null
                    ended(call.copy(state = CallState.ENDED), unanswered = call.state == CallState.RINGING)
                }
            }
        }
    }

    @Synchronized
    fun callerChanged(name: String?, number: String?, contact: String?, voicemail: Boolean) {
        callerName = name ?: callerName
        callerNumber = number ?: callerNumber
        callerContact = contact ?: callerContact
        val call = current ?: return
        val justAnswered = call.state == CallState.ACTIVE && System.currentTimeMillis() - answeredAt < VOICEMAIL_WINDOW_MS
        if (voicemail && call.state == CallState.RINGING) voicemailAnswering = true
        val updated = call.copy(
            name = name ?: call.name,
            number = number ?: call.number,
            contact = contact ?: call.contact,
            state = if (voicemail && justAnswered) CallState.VOICEMAIL else call.state,
        )
        if (updated != call) publish(updated)
    }

    private const val VOICEMAIL_WINDOW_MS = 3_000L
    private const val PLACED_WINDOW_MS = 30_000L

    private fun ended(call: CallState, unanswered: Boolean) {
        val lookup = wasDeclined
        if (!unanswered || lookup == null) return onChange?.invoke(call) ?: Unit
        val since = ringingAt
        thread(name = "call-history") { onChange?.invoke(call.copy(declined = lookup(since).takeIf { it })) }
    }

    private fun publish(call: CallState) {
        current = call
        onChange?.invoke(call)
    }

    private fun nextId(): String {
        counter += 1
        return "${System.currentTimeMillis()}-$counter"
    }
}
