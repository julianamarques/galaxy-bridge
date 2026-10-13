package com.julianamarques.galaxybridge.spike

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.telecom.TelecomManager

/** Comandos do adb: escolher o método da próxima chamada e fazer uma ligação com o app em segundo plano. */
class CommandReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            "com.julianamarques.galaxybridge.spike.SET_MODE" -> {
                val name = intent.getStringExtra("mode").orEmpty().uppercase()
                if (name == "SEQUENCE") {
                    Spike.startSequence(context)
                    return
                }
                val mode = Spike.Mode.entries.firstOrNull { it.name == name }
                if (mode == null) {
                    Spike.log("Modo desconhecido: $name. Use: ${Spike.Mode.entries.joinToString { it.name.lowercase() }}")
                } else {
                    Spike.setMode(context, mode)
                }
            }
            "com.julianamarques.galaxybridge.spike.END_CALL" -> {
                try {
                    @Suppress("DEPRECATION")
                    val ended = context.getSystemService(TelecomManager::class.java).endCall()
                    Spike.log("endCall() devolveu $ended")
                } catch (e: Exception) {
                    Spike.log("endCall falhou", e)
                }
            }
            "com.julianamarques.galaxybridge.spike.PLACE_CALL" -> {
                val number = intent.getStringExtra("number").orEmpty()
                try {
                    context.getSystemService(TelecomManager::class.java)
                        .placeCall(Uri.fromParts("tel", number, null), Bundle())
                    Spike.log("placeCall($number) chamado em segundo plano")
                } catch (e: Exception) {
                    Spike.log("placeCall falhou", e)
                }
            }
        }
    }
}
