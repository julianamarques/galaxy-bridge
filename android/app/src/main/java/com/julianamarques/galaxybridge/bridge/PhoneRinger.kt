package com.julianamarques.galaxybridge.bridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.VibratorManager
import android.provider.Settings
import com.julianamarques.galaxybridge.Diagnostics
import com.julianamarques.galaxybridge.R

class PhoneRinger(private val context: Context, private val stopIntent: Intent, private val onChange: (Boolean) -> Unit) {
    private val handler = Handler(Looper.getMainLooper())
    private val audio = context.getSystemService(AudioManager::class.java)
    private val vibrator = context.getSystemService(VibratorManager::class.java).defaultVibrator
    private val notifications = context.getSystemService(NotificationManager::class.java)
    private val timeout = Runnable { silence() }
    private var ringing = false
    private var player: MediaPlayer? = null
    private var savedVolume: Int? = null

    init {
        val channel = NotificationChannel(CHANNEL_ID, context.getString(R.string.channel_find), NotificationManager.IMPORTANCE_HIGH)
        channel.setSound(null, null)
        notifications.createNotificationChannel(channel)
    }

    fun start() {
        handler.post(::ring)
    }

    fun stop() {
        handler.post(::silence)
    }

    private fun ring() {
        if (ringing) return
        ringing = true
        savedVolume = audio.getStreamVolume(AudioManager.STREAM_ALARM)
        runCatching { audio.setStreamVolume(AudioManager.STREAM_ALARM, audio.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0) }
        player = SOUNDS.firstNotNullOfOrNull(::play)
        vibrate()
        notifications.notify(NOTIFICATION_ID, notification())
        handler.postDelayed(timeout, RING_MS)
        Diagnostics.record(context, "Tocando a pedido do Mac")
        onChange(true)
    }

    private fun silence() {
        handler.removeCallbacks(timeout)
        if (!ringing) return
        ringing = false
        player?.let {
            runCatching { it.stop() }
            it.release()
        }
        player = null
        vibrator.cancel()
        savedVolume?.let { runCatching { audio.setStreamVolume(AudioManager.STREAM_ALARM, it, 0) } }
        savedVolume = null
        notifications.cancel(NOTIFICATION_ID)
        onChange(false)
    }

    private fun play(sound: Uri): MediaPlayer? {
        val player = MediaPlayer()
        return runCatching {
            player.setAudioAttributes(ALARM)
            player.setDataSource(context, sound)
            player.isLooping = true
            player.prepare()
            player.start()
            player
        }.getOrElse {
            player.release()
            null
        }
    }

    private fun vibrate() {
        val effect = VibrationEffect.createWaveform(longArrayOf(0, 800, 600), 0)
        vibrator.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM))
    }

    private fun notification(): Notification {
        val stop = PendingIntent.getService(context, NOTIFICATION_ID, stopIntent, PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.ringing_title))
            .setContentText(context.getString(R.string.ringing_text))
            .setCategory(Notification.CATEGORY_ALARM)
            .setContentIntent(stop)
            .setDeleteIntent(stop)
            .addAction(Notification.Action.Builder(null, context.getString(R.string.ringing_stop), stop).build())
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "find"
        private const val NOTIFICATION_ID = 2
        private const val RING_MS = 60_000L
        private val SOUNDS = listOf(Settings.System.DEFAULT_RINGTONE_URI, Settings.System.DEFAULT_ALARM_ALERT_URI, Settings.System.DEFAULT_NOTIFICATION_URI)
        private val ALARM = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
    }
}
