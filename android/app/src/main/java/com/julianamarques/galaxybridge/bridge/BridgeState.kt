package com.julianamarques.galaxybridge.bridge

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

object BridgeState {
    sealed interface Connection {
        data object Stopped : Connection
        data object Searching : Connection
        data class Connected(val macName: String, val usb: Boolean) : Connection
        data object Refused : Connection
    }

    private val state = MutableStateFlow<Connection>(Connection.Stopped)
    val connection: StateFlow<Connection> = state

    fun set(connection: Connection) {
        state.value = connection
    }
}
