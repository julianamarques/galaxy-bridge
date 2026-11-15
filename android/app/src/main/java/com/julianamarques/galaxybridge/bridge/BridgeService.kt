package com.julianamarques.galaxybridge.bridge

import android.Manifest
import android.app.Notification
import android.content.ClipData
import android.content.ClipboardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.database.ContentObserver
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.CallLog
import android.telecom.TelecomManager
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log
import com.julianamarques.galaxybridge.Diagnostics
import com.julianamarques.galaxybridge.MainActivity
import com.julianamarques.galaxybridge.Permission
import com.julianamarques.galaxybridge.R
import com.julianamarques.galaxybridge.Diagnostics.TAG
import com.julianamarques.galaxybridge.protocol.BridgeError
import com.julianamarques.galaxybridge.protocol.CallState
import com.julianamarques.galaxybridge.protocol.Clipboard
import com.julianamarques.galaxybridge.protocol.ContactPhoto
import com.julianamarques.galaxybridge.protocol.ContactResults
import com.julianamarques.galaxybridge.protocol.NotificationKey
import com.julianamarques.galaxybridge.protocol.NotificationKeys
import com.julianamarques.galaxybridge.protocol.Envelope
import com.julianamarques.galaxybridge.protocol.GalleryResults
import com.julianamarques.galaxybridge.protocol.Message
import com.julianamarques.galaxybridge.protocol.PhoneStatus
import com.julianamarques.galaxybridge.protocol.RecentCall
import com.julianamarques.galaxybridge.protocol.RecentCalls
import com.julianamarques.galaxybridge.protocol.Ring
import java.io.IOException
import javax.net.ssl.SSLException
import kotlin.concurrent.thread

class BridgeService : Service() {
    private val lock = Object()
    private var wakeRequested = false
    @Volatile private var running = false
    @Volatile private var connection: BridgeConnection? = null
    @Volatile private var established = false
    @Volatile private var lastStatus: PhoneStatus? = null
    @Volatile private var lastBattery: Pair<Int, Int>? = null
    private var lastRecentCalls: List<RecentCall>? = null
    private var worker: Thread? = null
    private var callCallback: TelephonyCallback? = null
    private var callLogObserver: ContentObserver? = null
    private val handler = Handler(Looper.getMainLooper())
    private val recentCallsUpdate = Runnable { thread(name = "recent-calls") { sendRecentCalls() } }
    private lateinit var transfers: Transfers
    private lateinit var ringer: PhoneRinger

    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = sendStatus(intent)
    }

    private val shutdownReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            running = false
            val connection = connection ?: return
            Diagnostics.record(context, "Celular desligando; encerrando a conexão")
            thread { connection.close() }.join(SHUTDOWN_CLOSE_MS)
        }
    }

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            Diagnostics.record(this@BridgeService, "Rede disponível")
            wake()
        }

        override fun onLost(network: Network) {
            Diagnostics.record(this@BridgeService, "Rede perdida")
            connection?.close()
        }

        override fun onBlockedStatusChanged(network: Network, blocked: Boolean) {
            Diagnostics.record(this@BridgeService, if (blocked) "Rede bloqueada para o app" else "Rede desbloqueada para o app")
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel(this)
        startForeground(NOTIFICATION_ID, notification(BridgeState.Connection.Searching), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        running = true
        Diagnostics.record(this, "Serviço iniciado")
        transfers = Transfers(this)
        ringer = PhoneRinger(this, Intent(this, BridgeService::class.java).setAction(ACTION_STOP_RINGING)) {
            send(Message.RingMessage(Ring(it)))
        }
        CallTracker.onChange = ::sendCall
        CallTracker.wasDeclined = { CallHistory.wasDeclined(this, it) }
        NotificationRelay.onPosted = { send(Message.NotificationPostedMessage(it)) }
        NotificationRelay.onRemoved = { send(Message.NotificationRemovedMessage(NotificationKey(it))) }
        monitorCalls()
        watchCallLog()
        registerReceiver(shutdownReceiver, IntentFilter(Intent.ACTION_SHUTDOWN))
        getSystemService(ConnectivityManager::class.java).registerDefaultNetworkCallback(networkCallback)
        worker = thread(name = "bridge") { run() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val shared = intent?.clipData?.takeIf { intent.action == ACTION_SEND_FILES }
        shared?.let { clip -> transfers.upload((0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }) }
        if (intent?.action == ACTION_STOP_RINGING) ringer.stop()
        monitorCalls()
        watchCallLog()
        wake()
        return START_STICKY
    }

    override fun onDestroy() {
        Diagnostics.record(this, "Serviço parado")
        transfers.shutdown()
        ringer.stop()
        handler.removeCallbacks(recentCallsUpdate)
        callLogObserver?.let(contentResolver::unregisterContentObserver)
        callLogObserver = null
        running = false
        instance = null
        connection?.close()
        wake()
        runCatching { unregisterReceiver(shutdownReceiver) }
        CallTracker.onChange = null
        CallTracker.wasDeclined = null
        NotificationRelay.onPosted = null
        NotificationRelay.onRemoved = null
        callCallback?.let { getSystemService(TelephonyManager::class.java).unregisterTelephonyCallback(it) }
        callCallback = null
        runCatching { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(networkCallback) }
        BridgeState.set(BridgeState.Connection.Stopped)
        super.onDestroy()
    }

    private fun run() {
        var delay = 0L
        while (running) {
            val mac = PairingStore.current(this) ?: break
            if (BridgeState.connection.value != BridgeState.Connection.Refused) setState(BridgeState.Connection.Searching)
            if (!isOnWiFi()) {
                Diagnostics.record(this, "Sem Wi-Fi; aguardando")
                sleep(0)
                continue
            }
            val wasEstablished = session(mac)
            if (!running) break
            delay = if (wasEstablished) RETRY_DELAYS.first() else RETRY_DELAYS.firstOrNull { it > delay } ?: RETRY_DELAYS.last()
            Diagnostics.record(this, "Nova tentativa em ${delay / 1000} s")
            sleep(delay)
        }
        if (PairingStore.current(this) == null) stopSelf()
    }

    private fun session(mac: PairedMac): Boolean {
        val connection = BridgeConnection.open(this, mac) ?: run {
            Diagnostics.record(this, "Não foi possível conectar ao Mac")
            return false
        }
        this.connection = connection
        var greeted = false
        try {
            connection.sendNow(Envelope(Message.HelloMessage(PhoneInfo.hello(this))))
            when (val first = connection.receive().message) {
                is Message.HelloMessage -> {
                    greeted = true
                    PairingStore.updateAddress(this, connection.host, connection.port, first.body.name)
                    setState(BridgeState.Connection.Connected(first.body.name))
                    Diagnostics.record(this, "Conectado a ${first.body.name}")
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
            synchronized(handler) { lastRecentCalls = null }
            registerReceiver(batteryReceiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            CallTracker.current?.let(::sendCall)
            NotificationRelay.connected()
            connection.send(Envelope(Message.NotificationActiveMessage(NotificationKeys(NotificationRelay.activeKeys))))
            handler.post(recentCallsUpdate)
            connection.receiveTimeoutMs = RECEIVE_TIMEOUT_MS
            while (running) {
                val envelope = connection.receive()
                handle(envelope, connection)
            }
        } catch (e: SSLException) {
            if (!greeted && e.message.orEmpty().contains("certificate", ignoreCase = true)) {
                setState(BridgeState.Connection.Refused)
            }
            Diagnostics.record(this, "Conexão TLS encerrada: ${e.message}")
        } catch (e: IOException) {
            Diagnostics.record(this, "Conexão encerrada: ${e.javaClass.simpleName} ${e.message}")
        } finally {
            if (established) runCatching { unregisterReceiver(batteryReceiver) }
            established = false
            this.connection = null
            connection.close()
        }
        return greeted
    }

    private fun isOnWiFi(): Boolean {
        val connectivity = getSystemService(ConnectivityManager::class.java)
        return connectivity.getNetworkCapabilities(connectivity.activeNetwork)
            ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
    }

    private fun handle(envelope: Envelope, connection: BridgeConnection) {
        when (val message = envelope.message) {
            Message.Ping -> {
                Diagnostics.record(this, "Ping")
                connection.send(Envelope(Message.Pong, replyTo = envelope.id))
            }
            is Message.CallPlaceMessage -> placeCall(message.body.number)?.let {
                connection.send(Envelope(Message.ErrorMessage(it), replyTo = envelope.id))
            }
            is Message.CallAnswerMessage -> controlCall(message.body.call, CallControl.Answer)?.let {
                connection.send(Envelope(Message.ErrorMessage(it), replyTo = envelope.id))
            }
            is Message.CallDeclineMessage -> controlCall(message.body.call, CallControl.Decline)?.let {
                connection.send(Envelope(Message.ErrorMessage(it), replyTo = envelope.id))
            }
            is Message.CallEndMessage -> controlCall(message.body.call, CallControl.End)?.let {
                connection.send(Envelope(Message.ErrorMessage(it), replyTo = envelope.id))
            }
            is Message.ContactsSearchMessage -> connection.send(
                if (!PhoneContacts.canRead(this)) {
                    Envelope(Message.ErrorMessage(BridgeError("permission", getString(R.string.error_contacts_permission))), replyTo = envelope.id)
                } else {
                    val contacts = PhoneContacts.search(this, message.body.query, message.body.limit)
                    Envelope(Message.ContactsResultsMessage(ContactResults(contacts)), replyTo = envelope.id)
                },
            )
            is Message.NotificationActionMessage -> {
                val done = NotificationRelay.act(this, message.body.key, message.body.action, message.body.reply)
                Diagnostics.record(this, "Mac pediu ação de notificação: ${if (done) "feita" else "não encontrada"}")
            }
            is Message.NotificationDismissMessage -> NotificationListener.dismiss(message.body.key)
            is Message.NotificationFilterMessage -> NotificationRelay.muted = message.body.muted.toSet()
            is Message.TransferOfferMessage -> transfers.download(message.body)
            is Message.ClipboardMessage -> copy(message.body.text)
            is Message.RingMessage -> if (message.body.on) ringer.start() else ringer.stop()
            is Message.GalleryRequestMessage -> thread(name = "gallery") {
                connection.send(
                    if (!PhoneGallery.canRead(this)) {
                        Envelope(Message.ErrorMessage(BridgeError("permission", getString(R.string.error_photos_permission))), replyTo = envelope.id)
                    } else {
                        val photos = runCatching { PhoneGallery.recent(this, message.body.limit) }.getOrDefault(emptyList())
                        Envelope(Message.GalleryResultsMessage(GalleryResults(photos)), replyTo = envelope.id)
                    },
                )
            }
            is Message.GalleryImportMessage -> PhoneGallery.uri(message.body.id)?.let { transfers.upload(listOf(it)) }
            is Message.PhotoRequestMessage -> PhoneContacts.photo(this, message.body.contact)?.let {
                connection.send(Envelope(Message.PhotoMessage(ContactPhoto(message.body.contact, it)), replyTo = envelope.id))
            }
            Message.Unpair -> {
                Diagnostics.record(this, "O Mac esqueceu este celular")
                PairingStore.clear(this)
                running = false
                stopSelf()
            }
            else -> Unit
        }
    }

    private fun sleep(millis: Long) {
        synchronized(lock) {
            if (!wakeRequested) lock.wait(millis)
            wakeRequested = false
        }
    }

    private fun wake() {
        synchronized(lock) {
            wakeRequested = true
            lock.notifyAll()
        }
    }

    private fun sendStatus(battery: Intent) {
        val connection = connection ?: return
        if (!established) return
        val key = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) to battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        if (key == lastBattery) return
        lastBattery = key
        val status = PhoneInfo.status(this, battery)
        if (status == lastStatus) return
        lastStatus = status
        connection.send(Envelope(Message.StatusMessage(status)))
    }

    private fun monitorCalls() {
        if (callCallback != null || !Permission.has(this, Manifest.permission.READ_PHONE_STATE)) return
        val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
            override fun onCallStateChanged(state: Int) = CallTracker.phoneStateChanged(state)
        }
        getSystemService(TelephonyManager::class.java).registerTelephonyCallback(mainExecutor, callback)
        callCallback = callback
    }

    private fun watchCallLog() {
        if (callLogObserver != null || !CallHistory.canRead(this)) return
        val observer = object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean) {
                handler.removeCallbacks(recentCallsUpdate)
                handler.postDelayed(recentCallsUpdate, CALL_LOG_SETTLE_MS)
            }
        }
        runCatching { contentResolver.registerContentObserver(CallLog.Calls.CONTENT_URI, true, observer) }.onSuccess {
            callLogObserver = observer
            handler.post(recentCallsUpdate)
        }
    }

    private fun sendRecentCalls() {
        if (!established) return
        val calls = CallHistory.recent(this) ?: return
        synchronized(handler) {
            if (calls == lastRecentCalls) return
            if (send(Message.CallsRecentMessage(RecentCalls(calls)))) lastRecentCalls = calls
        }
    }

    private fun send(message: Message): Boolean {
        val connection = connection ?: return false
        if (!established) return false
        connection.send(Envelope(message))
        return true
    }

    private fun copy(text: String) {
        mainExecutor.execute {
            getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText(getString(R.string.clipboard_label), text))
        }
        Diagnostics.record(this, "Texto copiado do Mac: ${text.length} caracteres")
    }

    private fun sendCall(call: CallState) {
        Diagnostics.record(this, "Ligação ${call.direction}: ${call.state}")
        send(Message.CallStateMessage(call))
    }

    private enum class CallControl { Answer, Decline, End }

    @Suppress("DEPRECATION")
    private fun controlCall(id: String, control: CallControl): BridgeError? {
        val call = CallTracker.current
        if (call == null || call.call != id) return null
        if (!Permission.has(this, Manifest.permission.ANSWER_PHONE_CALLS)) {
            return BridgeError("permission", getString(R.string.error_answer_permission))
        }
        val telecom = getSystemService(TelecomManager::class.java)
        Diagnostics.record(this, "Mac pediu: $control")
        return try {
            when (control) {
                CallControl.Answer -> if (call.state == CallState.RINGING) telecom.acceptRingingCall()
                CallControl.Decline -> if (call.state == CallState.RINGING) telecom.endCall()
                CallControl.End -> telecom.endCall()
            }
            null
        } catch (e: SecurityException) {
            BridgeError("permission", getString(R.string.error_request_refused, e.message.orEmpty()))
        }
    }

    private fun placeCall(number: String): BridgeError? {
        if (!Permission.has(this, Manifest.permission.CALL_PHONE)) {
            return BridgeError("permission", getString(R.string.error_call_permission))
        }
        CallTracker.placing(number, PhoneContacts.lookup(this, number))
        return try {
            getSystemService(TelecomManager::class.java).placeCall(Uri.fromParts("tel", number, null), Bundle())
            Log.i(TAG, "Ligação pedida pelo Mac")
            null
        } catch (e: SecurityException) {
            BridgeError("permission", getString(R.string.error_call_refused, e.message.orEmpty()))
        } catch (e: Exception) {
            BridgeError("failed", getString(R.string.error_call_failed, e.message.orEmpty()))
        }
    }

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
        private const val ACTION_SEND_FILES = "com.julianamarques.galaxybridge.SEND_FILES"
        private const val ACTION_STOP_RINGING = "com.julianamarques.galaxybridge.STOP_RINGING"
        private const val CALL_LOG_SETTLE_MS = 1_000L
        private const val NOTIFICATION_ID = 1
        private const val RECEIVE_TIMEOUT_MS = 6 * 60_000
        private const val SHUTDOWN_CLOSE_MS = 1_000L
        private val RETRY_DELAYS = listOf(2_000L, 5_000L, 15_000L, 30_000L, 60_000L, 120_000L, 300_000L)

        @Volatile private var instance: BridgeService? = null

        fun start(context: Context) {
            if (PairingStore.current(context) == null) return
            context.startForegroundService(Intent(context, BridgeService::class.java))
        }

        fun send(context: Context, files: List<Uri>) {
            val clip = ClipData.newRawUri(null, files.first()).apply { files.drop(1).forEach { addItem(ClipData.Item(it)) } }
            val intent = Intent(context, BridgeService::class.java)
                .setAction(ACTION_SEND_FILES)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            intent.clipData = clip
            context.startForegroundService(intent)
        }

        fun copyToMac(text: String): Boolean =
            instance?.send(Message.ClipboardMessage(Clipboard(text.take(Clipboard.MAX_LENGTH)))) == true

        fun forget(context: Context) {
            val app = context.applicationContext
            val connection = instance?.connection
            PairingStore.clear(app)
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
