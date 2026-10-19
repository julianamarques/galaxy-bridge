package com.julianamarques.galaxybridge.bridge

import android.content.Context
import com.julianamarques.galaxybridge.R
import com.julianamarques.galaxybridge.protocol.Envelope
import com.julianamarques.galaxybridge.protocol.Message
import com.julianamarques.galaxybridge.protocol.PairRequest
import com.julianamarques.galaxybridge.protocol.PairingLink

object Pairing {
    sealed interface Result {
        data object Paired : Result
        data class Failed(val message: String) : Result
    }

    fun pair(context: Context, link: PairingLink): Result {
        val connection = BridgeConnection.openPinned(context, link.host, link.port, link.fingerprint, discoveryMs = 8_000)
            ?: return Result.Failed(context.getString(R.string.pairing_connect_failed))
        return connection.use { request(context, it, link.token) }
    }

    fun connect(found: MacFinder.Found): BridgeConnection = BridgeConnection.open(found.host, found.port, pinnedMac = null)

    fun pair(context: Context, connection: BridgeConnection, code: String): Result =
        connection.use { request(context, it, code) }

    private fun request(context: Context, connection: BridgeConnection, secret: String): Result {
        val hello = PhoneInfo.hello(context)
        try {
            connection.sendNow(Envelope(Message.HelloMessage(hello)))
            connection.sendNow(Envelope(Message.PairRequestMessage(PairRequest(secret, hello.name, hello.model))))
            connection.receiveTimeoutMs = 15_000
            var macName: String? = null
            while (true) {
                when (val message = connection.receive().message) {
                    is Message.PairAcceptedMessage -> macName = message.body.name
                    is Message.HelloMessage -> {
                        val name = macName ?: message.body.name
                        PairingStore.save(context, PairedMac(connection.macFingerprint, name, connection.host, connection.port))
                        return Result.Paired
                    }
                    is Message.PairRejectedMessage -> return Result.Failed(
                        context.getString(if (message.body.reason == "invalid") R.string.pairing_wrong_code else R.string.pairing_code_expired)
                    )
                    is Message.ErrorMessage -> return Result.Failed(message.body.message)
                    else -> Unit
                }
            }
        } catch (e: Exception) {
            return Result.Failed(context.getString(R.string.pairing_refused))
        }
    }
}
