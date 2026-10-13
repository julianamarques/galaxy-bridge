package com.julianamarques.galaxybridge.spike

import android.app.Notification
import android.app.PendingIntent
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager

/**
 * Acompanha as chamadas por três caminhos ao mesmo tempo, para comparar o que cada um revela:
 * `TelephonyCallback` (API atual, sem número), `PhoneStateListener` (obsoleto, com número se houver
 * READ_CALL_LOG) e a notificação de chamada do discador (`Notification.CallStyle`).
 * Quando o celular toca, executa o método escolhido com `mode.sh`.
 */
class CallListenerService : NotificationListenerService() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var telephony: TelephonyManager
    private lateinit var telecom: TelecomManager
    private var lastState = TelephonyManager.CALL_STATE_IDLE
    private var answeredBy: Spike.Mode? = null

    private val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
        override fun onCallStateChanged(state: Int) {
            Spike.log("TelephonyCallback: ${stateName(state)}")
            callStateChanged(state)
        }
    }

    @Suppress("DEPRECATION")
    private val legacyListener = object : PhoneStateListener() {
        override fun onCallStateChanged(state: Int, phoneNumber: String?) {
            Spike.log("PhoneStateListener: ${stateName(state)}, número: ${phoneNumber.orEmpty().ifEmpty { "(vazio)" }}")
        }
    }

    override fun onListenerConnected() {
        Spike.log("Acesso às notificações ativo. Modo atual: ${Spike.mode(this)}")
        telephony = getSystemService(TelephonyManager::class.java)
        telecom = getSystemService(TelecomManager::class.java)
        try {
            telephony.registerTelephonyCallback(mainExecutor, callback)
            @Suppress("DEPRECATION")
            telephony.listen(legacyListener, PhoneStateListener.LISTEN_CALL_STATE)
        } catch (e: SecurityException) {
            Spike.log("Sem permissão para acompanhar chamadas", e)
        }
    }

    override fun onListenerDisconnected() {
        telephony.unregisterTelephonyCallback(callback)
        @Suppress("DEPRECATION")
        telephony.listen(legacyListener, PhoneStateListener.LISTEN_NONE)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (!isCall(sbn)) return
        current = sbn
        val n = sbn.notification
        val extras = n.extras
        Spike.log(
            "Notificação de chamada de ${sbn.packageName}: " +
                "título=${extras.getCharSequence(Notification.EXTRA_TITLE)}, " +
                "texto=${extras.getCharSequence(Notification.EXTRA_TEXT)}, " +
                "estilo=${extras.getString(Notification.EXTRA_TEMPLATE)}, " +
                "callType=${extras.getInt(Notification.EXTRA_CALL_TYPE, -1)}, " +
                "pessoa=${extras.getParcelable(Notification.EXTRA_CALL_PERSON, android.app.Person::class.java)?.let { "${it.name} ${it.uri}" }}, " +
                "answer=${callIntent(n, Notification.EXTRA_ANSWER_INTENT) != null}, " +
                "decline=${callIntent(n, Notification.EXTRA_DECLINE_INTENT) != null}, " +
                "hangUp=${callIntent(n, Notification.EXTRA_HANG_UP_INTENT) != null}, " +
                "ações=${n.actions?.joinToString { it.title } ?: "nenhuma"}"
        )
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        if (sbn.key == current?.key) current = null
    }

    private fun isCall(sbn: StatusBarNotification): Boolean {
        val n = sbn.notification
        return n.category == Notification.CATEGORY_CALL ||
            n.extras.getString(Notification.EXTRA_TEMPLATE) == Notification.CallStyle::class.java.name
    }

    private fun callStateChanged(state: Int) {
        val previous = lastState
        lastState = state
        when {
            state == TelephonyManager.CALL_STATE_RINGING -> scheduleAction()
            state == TelephonyManager.CALL_STATE_OFFHOOK && previous == TelephonyManager.CALL_STATE_RINGING -> scheduleHangUp()
            state == TelephonyManager.CALL_STATE_IDLE && previous != TelephonyManager.CALL_STATE_IDLE -> {
                answeredBy = null
                Spike.advance(this)
            }
        }
    }

    private fun scheduleAction() {
        val mode = Spike.mode(this)
        if (mode == Spike.Mode.OBSERVE) return
        Spike.log("Tocando. Em 3 s: $mode")
        handler.postDelayed({ run(mode) }, 3_000)
    }

    @Suppress("DEPRECATION")
    private fun run(mode: Spike.Mode) {
        if (lastState != TelephonyManager.CALL_STATE_RINGING) {
            Spike.log("Não está mais tocando; nada a fazer")
            return
        }
        try {
            when (mode) {
                Spike.Mode.ANSWER_TELECOM -> {
                    answeredBy = mode
                    telecom.acceptRingingCall()
                    Spike.log("acceptRingingCall() chamado")
                }
                Spike.Mode.DECLINE_TELECOM -> Spike.log("endCall() devolveu ${telecom.endCall()}")
                Spike.Mode.ANSWER_NOTIFICATION -> {
                    answeredBy = mode
                    send(Notification.EXTRA_ANSWER_INTENT, "Atender")
                }
                Spike.Mode.DECLINE_NOTIFICATION -> send(Notification.EXTRA_DECLINE_INTENT, "Recusar")
                Spike.Mode.OBSERVE -> Unit
            }
        } catch (e: Exception) {
            Spike.log("$mode falhou", e)
        }
    }

    /** Depois de atender, encerra a chamada em 5 s pelo mesmo caminho, para testar também o "desligar". */
    @Suppress("DEPRECATION")
    private fun scheduleHangUp() {
        val mode = answeredBy ?: return
        Spike.log("Chamada atendida. Encerrando em 5 s pelo mesmo caminho")
        handler.postDelayed({
            try {
                if (mode == Spike.Mode.ANSWER_TELECOM) {
                    Spike.log("endCall() na chamada ativa devolveu ${telecom.endCall()}")
                } else {
                    send(Notification.EXTRA_HANG_UP_INTENT, "Desligar")
                }
            } catch (e: Exception) {
                Spike.log("Encerrar falhou", e)
            }
        }, 5_000)
    }

    private fun send(extra: String, label: String) {
        val notification = current?.notification
        if (notification == null) {
            Spike.log("$label: nenhuma notificação de chamada visível")
            return
        }
        val intent = callIntent(notification, extra)
        if (intent == null) {
            Spike.log("$label: a notificação não tem $extra. Ações: ${notification.actions?.joinToString { it.title } ?: "nenhuma"}")
            return
        }
        intent.send()
        Spike.log("$label: PendingIntent da notificação enviado")
    }

    private fun callIntent(notification: Notification, extra: String): PendingIntent? =
        notification.extras.getParcelable(extra, PendingIntent::class.java)

    private fun stateName(state: Int) = when (state) {
        TelephonyManager.CALL_STATE_IDLE -> "IDLE"
        TelephonyManager.CALL_STATE_RINGING -> "RINGING"
        TelephonyManager.CALL_STATE_OFFHOOK -> "OFFHOOK"
        else -> "?$state"
    }

    companion object {
        @Volatile
        var current: StatusBarNotification? = null
    }
}
