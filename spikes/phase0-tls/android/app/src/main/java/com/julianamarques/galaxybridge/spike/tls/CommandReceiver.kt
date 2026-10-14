package com.julianamarques.galaxybridge.spike.tls

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kotlin.concurrent.thread

/** Comandos do adb: `INIT` cria a chave e mostra a impressão digital; `CONNECT` conecta ao Mac. */
class CommandReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        // Rede não pode rodar na thread principal.
        thread {
            try {
                when (intent.action) {
                    "com.julianamarques.galaxybridge.spike.tls.INIT" ->
                        TlsSpike.log("Impressão digital do celular: ${TlsSpike.ensureIdentity()}")
                    "com.julianamarques.galaxybridge.spike.tls.CONNECT" -> TlsSpike.connect(
                        host = intent.getStringExtra("host") ?: "127.0.0.1",
                        port = intent.getIntExtra("port", 52800),
                        pinnedMac = intent.getStringExtra("pin").orEmpty(),
                    )
                }
            } catch (e: Exception) {
                TlsSpike.log("Falhou: ${e.javaClass.simpleName}: ${e.message}")
            } finally {
                pending.finish()
            }
        }
    }
}
