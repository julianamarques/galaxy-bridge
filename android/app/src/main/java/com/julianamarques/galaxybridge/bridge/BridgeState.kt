package com.julianamarques.galaxybridge.bridge

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** O estado da conexão com o Mac, para a interface e a notificação. */
object BridgeState {
    sealed interface Connection {
        data object Stopped : Connection
        data object Searching : Connection
        data class Connected(val macName: String) : Connection
        /** O Mac recusou este celular (ele foi esquecido no Mac enquanto estava desligado ou fora de casa). */
        data object Refused : Connection
    }

    private val state = MutableStateFlow<Connection>(Connection.Stopped)
    val connection: StateFlow<Connection> = state

    fun set(connection: Connection) {
        state.value = connection
    }
}
