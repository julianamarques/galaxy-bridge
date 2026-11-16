package com.julianamarques.galaxybridge.mirror

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.julianamarques.galaxybridge.Diagnostics
import com.julianamarques.galaxybridge.R
import com.julianamarques.galaxybridge.bridge.BridgeConnection
import com.julianamarques.galaxybridge.bridge.BridgeService
import com.julianamarques.galaxybridge.bridge.PairingStore
import com.julianamarques.galaxybridge.bridge.parcelable
import com.julianamarques.galaxybridge.protocol.Envelope
import com.julianamarques.galaxybridge.protocol.Frames
import com.julianamarques.galaxybridge.Permission
import com.julianamarques.galaxybridge.protocol.Message
import com.julianamarques.galaxybridge.protocol.MirrorStream
import java.nio.ByteBuffer
import kotlin.concurrent.thread

class ScreenMirrorService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var projection: MediaProjection? = null
    @Volatile private var encoder: ScreenEncoder? = null
    @Volatile private var connection: BridgeConnection? = null
    @Volatile private var audio: AudioCapture? = null
    private var worker: Thread? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP || worker != null) {
            if (intent?.action == ACTION_STOP) stopMirroring()
            return START_NOT_STICKY
        }
        val data = intent?.extras?.parcelable<Intent>(EXTRA_DATA)
        val resultCode = intent?.getIntExtra(EXTRA_RESULT, 0) ?: 0
        if (data == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        val wantsAudio = intent.getBooleanExtra(EXTRA_AUDIO, false) && Permission.has(this, Manifest.permission.RECORD_AUDIO)
        val types = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION or
            if (wantsAudio) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0
        startForeground(NOTIFICATION_ID, notification(), types)
        val projection = getSystemService(MediaProjectionManager::class.java).getMediaProjection(resultCode, data)
        if (projection == null) {
            finished(null)
            return START_NOT_STICKY
        }
        this.projection = projection
        projection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() = stopMirroring()
        }, handler)
        val maxSize = intent.getIntExtra(EXTRA_MAX_SIZE, 0).takeIf { it > 0 }
        val bitRate = intent.getIntExtra(EXTRA_BIT_RATE, DEFAULT_BIT_RATE)
        worker = thread(name = "mirror") { stream(projection, maxSize, bitRate, wantsAudio) }
        return START_NOT_STICKY
    }

    private fun stream(projection: MediaProjection, maxSize: Int?, bitRate: Int, withAudio: Boolean) {
        var failure: String? = null
        try {
            val connection = BridgeConnection.openPaired(this)
            this.connection = connection
            connection.sendBufferBytes = SEND_BUFFER_BYTES
            connection.sendNow(Envelope(Message.MirrorStreamMessage(MirrorStream(CODEC))))
            val encoder = ScreenEncoder(this, projection, maxSize, bitRate) { kind, pts, data, extra -> write(connection, kind, pts, data, extra) }
            this.encoder = encoder
            if (withAudio) {
                val capture = AudioCapture(projection) { data, count -> write(connection, KIND_AUDIO, 0, ByteBuffer.wrap(data, 0, count), null) }
                audio = capture
                thread(name = "mirror-audio") { runCatching { capture.run(this) } }
            }
            BridgeService.mirrorStarted(MirrorControlService.isEnabled(this))
            Diagnostics.record(this, "Espelhamento iniciado")
            encoder.run()
        } catch (e: Exception) {
            if (encoder == null || connection == null) failure = e.message
            Diagnostics.record(this, "Espelhamento encerrado: ${e.javaClass.simpleName} ${e.message}")
        }
        handler.post { finished(failure) }
    }

    private fun write(connection: BridgeConnection, kind: Int, pts: Long, data: ByteBuffer?, extra: ByteArray?) {
        val payload = data?.remaining() ?: extra?.size ?: 0
        val frame = Frames.framed(HEADER + payload)
        val start = Frames.PREFIX + HEADER
        ByteBuffer.wrap(frame, Frames.PREFIX, HEADER).put(kind.toByte()).putLong(pts)
        if (data != null) data.get(frame, start, payload) else extra?.copyInto(frame, start)
        connection.sendFrame(frame)
    }

    fun requestKeyFrame() {
        encoder?.requestKeyFrame()
    }

    private fun stopMirroring() {
        audio?.stop()
        encoder?.stop()
        connection?.close()
        if (worker == null) finished(null)
    }

    private fun finished(failure: String?) {
        audio?.stop()
        encoder?.stop()
        connection?.close()
        projection?.stop()
        projection = null
        if (instance === this) instance = null
        BridgeService.mirrorStopped(failure)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel(this)
    }

    override fun onDestroy() {
        encoder?.stop()
        connection?.close()
        if (instance === this) instance = null
        super.onDestroy()
    }

    private fun notification(): Notification {
        val stop = PendingIntent.getService(
            this, 0, Intent(this, ScreenMirrorService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(getString(R.string.mirror_running_title))
            .setContentText(getString(R.string.mirror_running_text))
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, getString(R.string.mirror_stop), stop).build())
            .build()
    }

    companion object {
        const val CHANNEL_ID = "mirror"
        private const val NOTIFICATION_ID = 3
        private const val ACTION_STOP = "com.julianamarques.galaxybridge.STOP_MIRROR"
        private const val EXTRA_DATA = "data"
        private const val EXTRA_RESULT = "result"
        const val EXTRA_MAX_SIZE = "maxSize"
        const val EXTRA_BIT_RATE = "bitRate"
        const val EXTRA_AUDIO = "audio"
        private const val KIND_AUDIO = 4
        private const val DEFAULT_BIT_RATE = 8_000_000
        private const val SEND_BUFFER_BYTES = 1 shl 20
        private const val HEADER = 9
        private const val CODEC = "h264"

        @Volatile var instance: ScreenMirrorService? = null
            private set

        fun start(context: Context, resultCode: Int, data: Intent, options: Bundle?) {
            val intent = Intent(context, ScreenMirrorService::class.java)
                .putExtra(EXTRA_RESULT, resultCode)
                .putExtra(EXTRA_DATA, data)
            options?.let(intent::putExtras)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            if (instance == null) return
            context.startService(Intent(context, ScreenMirrorService::class.java).setAction(ACTION_STOP))
        }

        fun createChannel(context: Context) {
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, context.getString(R.string.channel_mirror), NotificationManager.IMPORTANCE_HIGH),
            )
        }
    }
}
