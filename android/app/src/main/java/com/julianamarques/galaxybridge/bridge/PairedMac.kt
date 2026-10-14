package com.julianamarques.galaxybridge.bridge

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** O Mac pareado: a impressão digital fixada, o nome e o último endereço em que ele respondeu. */
data class PairedMac(
    val fingerprint: String,
    val name: String,
    val host: String?,
    val port: Int?,
)

/** Guarda o Mac pareado (por enquanto um só) e avisa a interface quando ele muda. */
object PairingStore {
    private const val PREFS = "pairing"
    private val state = MutableStateFlow<PairedMac?>(null)
    @Volatile private var loaded = false

    fun mac(context: Context): StateFlow<PairedMac?> {
        load(context)
        return state
    }

    fun current(context: Context): PairedMac? = mac(context).value

    fun save(context: Context, mac: PairedMac) {
        prefs(context).edit()
            .putString("fingerprint", mac.fingerprint)
            .putString("name", mac.name)
            .putString("host", mac.host)
            .putInt("port", mac.port ?: 0)
            .apply()
        loaded = true
        state.value = mac
    }

    /** Guarda o endereço em que o Mac respondeu, para tentar primeiro da próxima vez. */
    fun updateAddress(context: Context, host: String, port: Int, name: String) {
        val mac = current(context) ?: return
        if (mac.host == host && mac.port == port && mac.name == name) return
        save(context, mac.copy(host = host, port = port, name = name))
    }

    fun clear(context: Context) {
        prefs(context).edit().clear().apply()
        loaded = true
        state.value = null
    }

    @Synchronized
    private fun load(context: Context) {
        if (loaded) return
        val prefs = prefs(context)
        state.value = prefs.getString("fingerprint", null)?.let { fingerprint ->
            PairedMac(
                fingerprint = fingerprint,
                name = prefs.getString("name", null) ?: "Mac",
                host = prefs.getString("host", null),
                port = prefs.getInt("port", 0).takeIf { it > 0 },
            )
        }
        loaded = true
    }

    private fun prefs(context: Context) = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
