package com.julianamarques.galaxybridge.mirror

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import com.julianamarques.galaxybridge.Permission
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection

class AudioCapture(private val projection: MediaProjection, private val output: (ByteArray, Int) -> Unit) {
    @Volatile private var stopped = false

    @SuppressLint("MissingPermission")
    fun run(context: Context) {
        if (!Permission.has(context, Manifest.permission.RECORD_AUDIO)) return
        val config = AudioPlaybackCaptureConfiguration.Builder(projection)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()
        val format = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(SAMPLE_RATE)
            .setChannelMask(AudioFormat.CHANNEL_IN_STEREO)
            .build()
        val minimum = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_STEREO, AudioFormat.ENCODING_PCM_16BIT)
        val record = AudioRecord.Builder()
            .setAudioFormat(format)
            .setBufferSizeInBytes(maxOf(minimum, CHUNK_BYTES * 4))
            .setAudioPlaybackCaptureConfig(config)
            .build()
        val buffer = ByteArray(CHUNK_BYTES)
        try {
            record.startRecording()
            while (!stopped) {
                val count = record.read(buffer, 0, buffer.size)
                if (count < 0) break
                if (count > 0) output(buffer, count)
            }
        } finally {
            runCatching { record.stop() }
            record.release()
        }
    }

    fun stop() {
        stopped = true
    }

    private companion object {
        const val SAMPLE_RATE = 48_000
        const val CHUNK_BYTES = 960 * 4
    }
}
