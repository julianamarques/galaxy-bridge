package com.julianamarques.galaxybridge.bridge

import android.content.Context
import android.util.Log
import com.julianamarques.galaxybridge.Diagnostics
import com.julianamarques.galaxybridge.Diagnostics.TAG
import com.julianamarques.galaxybridge.protocol.Envelope
import com.julianamarques.galaxybridge.protocol.Frames
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.Closeable
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.util.concurrent.Executors
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket

class BridgeConnection private constructor(
    private val socket: SSLSocket,
    val macFingerprint: String,
) : Closeable {
    private val input = DataInputStream(BufferedInputStream(socket.inputStream))
    private val output = DataOutputStream(BufferedOutputStream(socket.outputStream))
    private val writer = Executors.newSingleThreadExecutor { Thread(it, "bridge-writer") }

    val host: String get() = socket.inetAddress.hostAddress ?: ""
    val port: Int get() = socket.port
    val isUsb: Boolean get() = socket.inetAddress.isLoopbackAddress

    var receiveTimeoutMs: Int
        get() = socket.soTimeout
        set(value) { socket.soTimeout = value }

    var sendBufferBytes: Int
        get() = socket.sendBufferSize
        set(value) { socket.sendBufferSize = value }

    fun receive(): Envelope = Frames.read(input)

    fun send(envelope: Envelope) {
        if (writer.isShutdown) return
        runCatching {
            writer.execute {
                try {
                    synchronized(output) { Frames.write(output, envelope) }
                } catch (e: IOException) {
                    close()
                }
            }
        }
    }

    fun sendNow(envelope: Envelope) {
        synchronized(output) { Frames.write(output, envelope) }
    }

    fun sendRaw(body: ByteArray, length: Int = body.size) {
        synchronized(output) { Frames.writeRaw(output, body, length) }
    }

    override fun close() {
        writer.shutdown()
        runCatching { socket.close() }
    }

    companion object {
        private const val DISCOVERY_TIMEOUT_MS = 10_000L
        private const val CONNECT_TIMEOUT_MS = 5_000
        const val LOOPBACK = "127.0.0.1"

        fun open(context: Context, mac: PairedMac): BridgeConnection? {
            UsbTunnel.port?.let { port ->
                runCatching { return open(LOOPBACK, port, mac.fingerprint) }
                    .onFailure { Diagnostics.record(context, "Cabo USB falhou: ${it.javaClass.simpleName} ${it.message}") }
            }
            return openPinned(context, mac.host, mac.port, mac.fingerprint, DISCOVERY_TIMEOUT_MS)
        }

        fun openPinned(context: Context, host: String?, port: Int?, fingerprint: String, discoveryMs: Long): BridgeConnection? {
            if (host != null && port != null) {
                runCatching { return open(host, port, fingerprint) }
            }
            val found = MacFinder(context).find(discoveryMs) { it.id == Identity.shortId(fingerprint) } ?: return null
            return try {
                open(found.host, found.port, fingerprint)
            } catch (e: Exception) {
                Log.i(TAG, "Mac encontrado, mas a conexão falhou: ${e.message}")
                null
            }
        }

        fun open(host: String, port: Int, pinnedMac: String?): BridgeConnection {
            val trust = MacTrustManager(pinnedMac)
            val context = SSLContext.getInstance("TLSv1.3")
            context.init(arrayOf(Identity.KeyManager), arrayOf(trust), null)
            val socket = context.socketFactory.createSocket() as SSLSocket
            try {
                socket.enabledProtocols = arrayOf("TLSv1.3")
                socket.tcpNoDelay = true
                socket.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
                socket.soTimeout = CONNECT_TIMEOUT_MS * 2
                socket.startHandshake()
            } catch (e: Exception) {
                runCatching { socket.close() }
                throw e
            }
            return BridgeConnection(socket, trust.seen ?: "")
        }
    }
}
