package com.julianamarques.galaxybridge.bridge

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

/**
 * Uma conexão TLS 1.3 com o Mac, com a chave do Keystore como certificado de cliente.
 * [receive] bloqueia; [send] pode ser chamado de qualquer thread (inclusive a principal) e escreve em segundo plano.
 */
class BridgeConnection private constructor(
    private val socket: SSLSocket,
    /** A impressão digital do certificado que o Mac apresentou. */
    val macFingerprint: String,
) : Closeable {
    private val input = DataInputStream(BufferedInputStream(socket.inputStream))
    private val output = DataOutputStream(BufferedOutputStream(socket.outputStream))
    private val writer = Executors.newSingleThreadExecutor { Thread(it, "bridge-writer") }

    val host: String get() = socket.inetAddress.hostAddress ?: ""
    val port: Int get() = socket.port

    /** Tempo máximo esperando a próxima mensagem; passado esse tempo, [receive] lança `SocketTimeoutException`. */
    var receiveTimeoutMs: Int
        get() = socket.soTimeout
        set(value) { socket.soTimeout = value }

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

    /** Envia e espera a escrita terminar; só fora da thread principal. */
    fun sendNow(envelope: Envelope) {
        synchronized(output) { Frames.write(output, envelope) }
    }

    override fun close() {
        writer.shutdown()
        runCatching { socket.close() }
    }

    companion object {
        private const val CONNECT_TIMEOUT_MS = 5_000

        /** Conecta e faz o handshake. Com [pinnedMac] nulo aceita qualquer Mac (pareamento por código). */
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
