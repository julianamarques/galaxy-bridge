package com.julianamarques.galaxybridge.bridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Bundle
import android.os.IBinder
import android.telecom.TelecomManager
import android.util.Log
import com.julianamarques.galaxybridge.MainActivity
import com.julianamarques.galaxybridge.Permission
import com.julianamarques.galaxybridge.R
import com.julianamarques.galaxybridge.TAG
import com.julianamarques.galaxybridge.protocol.BridgeError
import com.julianamarques.galaxybridge.protocol.Envelope
import com.julianamarques.galaxybridge.protocol.Message
import com.julianamarques.galaxybridge.protocol.PhoneStatus
import java.io.IOException
import javax.net.ssl.SSLException
import kotlin.concurrent.thread

/**
 * Mantém a conexão com o Mac pareado: encontra o Mac, conecta, envia o status e atende os pedidos.
 * É um serviço em primeiro plano do tipo `connectedDevice`, sem wakelock: a fase 0 mostrou que ele sobrevive
 * à noite com a bateria em "Sem restrições", e que um pacote vindo do Mac acorda o celular.
 */
class BridgeService : Service() {
    private val lock = Object()
    private var wakeRequested = false
    @Volatile private var running = false
    @Volatile private var connection: BridgeConnection? = null
    @Volatile private var established = false
    @Volatile private var lastStatus: PhoneStatus? = null
    @Volatile private var lastBattery: Pair<Int, Int>? = null
    private var worker: Thread? = null

    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = sendStatus(intent)
    }

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = wake()
        // A conexão com o Mac morreu junto com a rede; fechar já evita esperar o tempo limite.
        override fun onLost(network: Network) {
            connection?.close()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel(this)
        startForeground(NOTIFICATION_ID, notification(BridgeState.Connection.Searching), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        running = true
        getSystemService(ConnectivityManager::class.java).registerDefaultNetworkCallback(networkCallback)
        worker = thread(name = "bridge") { run() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        wake()
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        instance = null
        connection?.close()
        wake()
        runCatching { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(networkCallback) }
        BridgeState.set(BridgeState.Connection.Stopped)
        super.onDestroy()
    }

    // MARK: Conexão

    private fun run() {
        var delay = 0L
        while (running) {
            val mac = PairingStore.current(this) ?: break
            if (BridgeState.connection.value != BridgeState.Connection.Refused) setState(BridgeState.Connection.Searching)
            // Fora do Wi-Fi o Mac não está ao alcance: em vez de tentar a cada poucos minutos, espera a rede mudar.
            if (!isOnWiFi()) {
                sleep(0)
                continue
            }
            val wasEstablished = session(mac)
            if (!running) break
            delay = if (wasEstablished) RETRY_DELAYS.first() else RETRY_DELAYS.firstOrNull { it > delay } ?: RETRY_DELAYS.last()
            sleep(delay)
        }
        if (PairingStore.current(this) == null) stopSelf()
    }

    /** Uma conexão, do início ao fim. Devolve `true` se chegou a trocar o `hello` com o Mac. */
    private fun session(mac: PairedMac): Boolean {
        val connection = open(mac) ?: return false
        this.connection = connection
        var greeted = false
        try {
            connection.sendNow(Envelope(Message.HelloMessage(PhoneInfo.hello(this))))
            when (val first = connection.receive().message) {
                is Message.HelloMessage -> {
                    greeted = true
                    PairingStore.updateAddress(this, connection.host, connection.port, first.body.name)
                    setState(BridgeState.Connection.Connected(first.body.name))
                }
                is Message.ErrorMessage -> {
                    Log.w(TAG, "Mac recusou: ${first.body.message}")
                    return false
                }
                is Message.PairRejectedMessage -> {
                    setState(BridgeState.Connection.Refused)
                    return false
                }
                else -> return false
            }
            established = true
            lastStatus = null
            lastBattery = null
            // Só escuta a bateria enquanto há conexão; o registro já entrega o estado atual.
            registerReceiver(batteryReceiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            connection.receiveTimeoutMs = RECEIVE_TIMEOUT_MS
            while (running) {
                val envelope = connection.receive()
                handle(envelope, connection)
            }
        } catch (e: SSLException) {
            // Antes do `hello`, um erro de certificado quer dizer que o Mac não reconhece mais este celular.
            if (!greeted && e.message.orEmpty().contains("certificate", ignoreCase = true)) {
                setState(BridgeState.Connection.Refused)
            }
            Log.i(TAG, "Conexão TLS encerrada: ${e.message}")
        } catch (e: IOException) {
            Log.i(TAG, "Conexão encerrada: ${e.javaClass.simpleName} ${e.message}")
        } finally {
            if (established) runCatching { unregisterReceiver(batteryReceiver) }
            established = false
            this.connection = null
            connection.close()
        }
        return greeted
    }

    private fun open(mac: PairedMac): BridgeConnection? =
        BridgeConnection.openPinned(this, mac.host, mac.port, mac.fingerprint, DISCOVERY_TIMEOUT_MS)

    private fun isOnWiFi(): Boolean {
        val connectivity = getSystemService(ConnectivityManager::class.java)
        return connectivity.getNetworkCapabilities(connectivity.activeNetwork)
            ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
    }

    private fun handle(envelope: Envelope, connection: BridgeConnection) {
        when (val message = envelope.message) {
            Message.Ping -> connection.send(Envelope(Message.Pong, replyTo = envelope.id))
            is Message.CallPlaceMessage -> placeCall(message.body.number)?.let {
                connection.send(Envelope(Message.ErrorMessage(it), replyTo = envelope.id))
            }
            Message.Unpair -> {
                Log.i(TAG, "O Mac esqueceu este celular")
                PairingStore.clear(this)
                running = false
                stopSelf()
            }
            else -> Unit
        }
    }

    /** Espera [millis] ms, ou até [wake] (com 0, só até [wake]). */
    private fun sleep(millis: Long) {
        synchronized(lock) {
            if (!wakeRequested) lock.wait(millis)
            wakeRequested = false
        }
    }

    /** Interrompe a espera entre tentativas: a rede voltou ou o app foi aberto. */
    private fun wake() {
        synchronized(lock) {
            wakeRequested = true
            lock.notifyAll()
        }
    }

    // MARK: Pedidos do Mac

    private fun sendStatus(battery: Intent) {
        val connection = connection ?: return
        if (!established) return
        // A transmissão chega a cada mudança de tensão ou temperatura; só o nível e o carregamento interessam.
        val key = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) to battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        if (key == lastBattery) return
        lastBattery = key
        val status = PhoneInfo.status(this, battery)
        if (status == lastStatus) return
        lastStatus = status
        connection.send(Envelope(Message.StatusMessage(status)))
    }

    /** Devolve o erro para o Mac, ou `null` se a ligação começou. */
    private fun placeCall(number: String): BridgeError? {
        if (!Permission.Calls.isGranted(this)) {
            return BridgeError("permission", "O Galaxy Bridge não tem permissão para fazer ligações. Abra o app no Galaxy para permitir.")
        }
        return try {
            getSystemService(TelecomManager::class.java).placeCall(Uri.fromParts("tel", number, null), Bundle())
            Log.i(TAG, "Ligação pedida pelo Mac")
            null
        } catch (e: SecurityException) {
            BridgeError("permission", "O Galaxy recusou a ligação: ${e.message}")
        } catch (e: Exception) {
            BridgeError("failed", "Não foi possível ligar: ${e.message}")
        }
    }

    // MARK: Notificação

    private fun setState(state: BridgeState.Connection) {
        if (state == BridgeState.connection.value) return
        BridgeState.set(state)
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification(state))
    }

    private fun notification(state: BridgeState.Connection): Notification {
        val macName = PairingStore.current(this)?.name ?: "Mac"
        val text = when (state) {
            is BridgeState.Connection.Connected -> getString(R.string.notification_connected, state.macName)
            BridgeState.Connection.Refused -> getString(R.string.notification_refused, macName)
            else -> getString(R.string.notification_searching, macName)
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "connection"
        private const val NOTIFICATION_ID = 1
        private const val RECEIVE_TIMEOUT_MS = 6 * 60_000
        private const val DISCOVERY_TIMEOUT_MS = 10_000L
        private val RETRY_DELAYS = listOf(2_000L, 5_000L, 15_000L, 30_000L, 60_000L, 120_000L, 300_000L)

        @Volatile private var instance: BridgeService? = null

        fun start(context: Context) {
            if (PairingStore.current(context) == null) return
            context.startForegroundService(Intent(context, BridgeService::class.java))
        }

        /** Esquece o Mac dos dois lados: avisa-o se estiver conectado e para o serviço. */
        fun forget(context: Context) {
            val app = context.applicationContext
            val connection = instance?.connection
            PairingStore.clear(app)
            // Avisa antes de parar o serviço, que fecha a conexão ao terminar.
            thread {
                connection?.let { runCatching { it.sendNow(Envelope(Message.Unpair)) } }
                app.stopService(Intent(app, BridgeService::class.java))
            }
        }

        private fun createChannel(context: Context) {
            val channel = NotificationChannel(
                CHANNEL_ID, context.getString(R.string.channel_connection), NotificationManager.IMPORTANCE_MIN,
            )
            channel.setShowBadge(false)
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }
}
