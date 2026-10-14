package com.julianamarques.galaxybridge.spike.tls

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import java.io.DataInputStream
import java.io.DataOutputStream
import java.math.BigInteger
import java.net.InetSocketAddress
import java.net.Socket
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.Principal
import java.security.PrivateKey
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import java.util.Date
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509ExtendedKeyManager
import javax.net.ssl.X509ExtendedTrustManager
import javax.security.auth.x500.X500Principal

object TlsSpike {
    private const val TAG = "GBSpike"
    private const val ALIAS = "galaxybridge-identity"

    private val keyStore: KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    fun log(message: String) {
        Log.i(TAG, message)
    }

    fun ensureIdentity(): String {
        if (!keyStore.containsAlias(ALIAS)) {
            val now = System.currentTimeMillis()
            val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
                .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_NONE, KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA384, KeyProperties.DIGEST_SHA512)
                .setCertificateSubject(X500Principal("CN=Galaxy Bridge (teste)"))
                .setCertificateSerialNumber(BigInteger.ONE)
                .setCertificateNotBefore(Date(now - 3_600_000))
                .setCertificateNotAfter(Date(now + 10L * 365 * 24 * 3_600_000))
                .build()
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply {
                initialize(spec)
                generateKeyPair()
            }
            log("Chave nova criada no Android Keystore")
        }
        return fingerprint(certificate().encoded)
    }

    fun connect(host: String, port: Int, pinnedMac: String) {
        val context = SSLContext.getInstance("TLSv1.3")
        context.init(arrayOf(KeyManager), arrayOf(PinningTrustManager(pinnedMac.lowercase())), null)
        val socket = context.socketFactory.createSocket() as SSLSocket
        socket.enabledProtocols = arrayOf("TLSv1.3")
        socket.use {
            it.connect(InetSocketAddress(host, port), 5_000)
            it.soTimeout = 5_000
            it.startHandshake()
            log("Handshake ok: ${it.session.protocol}, ${it.session.cipherSuite}")
            val output = DataOutputStream(it.outputStream)
            val body = """{"type":"hello","body":{"name":"S25 (teste)"}}""".toByteArray()
            output.writeInt(body.size)
            output.write(body)
            output.flush()
            val input = DataInputStream(it.inputStream)
            val reply = ByteArray(input.readInt()).also(input::readFully)
            log("Resposta do Mac: ${String(reply)}")
        }
    }

    private fun certificate() = keyStore.getCertificate(ALIAS) as X509Certificate

    fun fingerprint(der: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(der).joinToString("") { "%02x".format(it) }

    private object KeyManager : X509ExtendedKeyManager() {
        override fun chooseClientAlias(keyType: Array<out String>?, issuers: Array<out Principal>?, socket: Socket?) = ALIAS
        override fun chooseEngineClientAlias(keyType: Array<out String>?, issuers: Array<out Principal>?, engine: SSLEngine?) = ALIAS
        override fun getCertificateChain(alias: String?) = arrayOf(certificate())
        override fun getPrivateKey(alias: String?) = keyStore.getKey(ALIAS, null) as PrivateKey
        override fun getClientAliases(keyType: String?, issuers: Array<out Principal>?) = arrayOf(ALIAS)
        override fun getServerAliases(keyType: String?, issuers: Array<out Principal>?): Array<String>? = null
        override fun chooseServerAlias(keyType: String?, issuers: Array<out Principal>?, socket: Socket?): String? = null
    }

    private class PinningTrustManager(private val pinned: String) : X509ExtendedTrustManager() {
        override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String?) {
            val actual = fingerprint(chain.first().encoded)
            log("Certificado do Mac: $actual")
            if (actual != pinned) throw CertificateException("não é o Mac pareado")
        }
        override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String?, socket: Socket?) =
            checkServerTrusted(chain, authType)
        override fun checkServerTrusted(chain: Array<out X509Certificate>, authType: String?, engine: SSLEngine?) =
            checkServerTrusted(chain, authType)
        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) =
            throw CertificateException("o celular não aceita conexões")
        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, socket: Socket?) =
            throw CertificateException("o celular não aceita conexões")
        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, engine: SSLEngine?) =
            throw CertificateException("o celular não aceita conexões")
        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
    }
}
