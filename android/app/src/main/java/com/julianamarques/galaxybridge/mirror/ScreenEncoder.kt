package com.julianamarques.galaxybridge.mirror

import android.content.Context
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.Surface
import java.nio.ByteBuffer

class ScreenEncoder(
    private val context: Context,
    private val projection: MediaProjection,
    private val maxSize: Int?,
    private val bitRate: Int,
    private val output: (kind: Int, pts: Long, data: ByteBuffer?, extra: ByteArray?) -> Unit,
) {
    @Volatile private var stopped = false
    @Volatile private var restart = false
    @Volatile private var codec: MediaCodec? = null
    private var display: VirtualDisplay? = null
    private val handler = Handler(Looper.getMainLooper())
    private val displays = context.getSystemService(DisplayManager::class.java)

    private val rotation = object : DisplayManager.DisplayListener {
        override fun onDisplayChanged(displayId: Int) {
            if (displayId == Display.DEFAULT_DISPLAY && size() != current) restart = true
        }

        override fun onDisplayAdded(displayId: Int) = Unit
        override fun onDisplayRemoved(displayId: Int) = Unit
    }

    private var current: Pair<Int, Int>? = null

    fun run() {
        displays.registerDisplayListener(rotation, handler)
        try {
            while (!stopped) {
                restart = false
                val (width, height) = size().also { current = it }
                val (videoWidth, videoHeight) = scaled(width, height)
                val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
                codec.configure(format(videoWidth, videoHeight), null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                val surface = codec.createInputSurface()
                codec.start()
                this.codec = codec
                attach(surface, videoWidth, videoHeight)
                output(KIND_SESSION, 0, null, sizeBytes(videoWidth, videoHeight))
                try {
                    drain(codec)
                } finally {
                    this.codec = null
                    display?.surface = null
                    runCatching { codec.stop() }
                    codec.release()
                    surface.release()
                }
            }
        } finally {
            displays.unregisterDisplayListener(rotation)
            display?.release()
            display = null
        }
    }

    fun stop() {
        stopped = true
    }

    fun requestKeyFrame() {
        codec?.let { runCatching { it.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) }) } }
    }

    private fun attach(surface: Surface, width: Int, height: Int) {
        val dpi = context.resources.displayMetrics.densityDpi
        val existing = display
        if (existing == null) {
            display = projection.createVirtualDisplay(
                "Galaxy Bridge", width, height, dpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, surface, null, null,
            )
        } else {
            existing.resize(width, height, dpi)
            existing.surface = surface
        }
    }

    private fun drain(codec: MediaCodec) {
        val info = MediaCodec.BufferInfo()
        while (!stopped && !restart) {
            val index = codec.dequeueOutputBuffer(info, DEQUEUE_TIMEOUT_US)
            if (index < 0) continue
            val buffer = codec.getOutputBuffer(index)
            if (buffer != null && info.size > 0) {
                buffer.position(info.offset).limit(info.offset + info.size)
                val kind = when {
                    info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0 -> KIND_CONFIG
                    info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0 -> KIND_KEY_FRAME
                    else -> KIND_FRAME
                }
                output(kind, info.presentationTimeUs, buffer, null)
            }
            codec.releaseOutputBuffer(index, false)
            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                stopped = true
            }
        }
    }

    private fun size(): Pair<Int, Int> {
        val display = displays.getDisplay(Display.DEFAULT_DISPLAY)
        val bounds = context.createDisplayContext(display).getSystemService(android.view.WindowManager::class.java).maximumWindowMetrics.bounds
        return bounds.width() to bounds.height()
    }

    private fun scaled(width: Int, height: Int): Pair<Int, Int> {
        val longSide = maxOf(width, height)
        val scale = maxSize?.takeIf { it < longSide }?.let { it.toDouble() / longSide } ?: 1.0
        return align(width * scale) to align(height * scale)
    }

    private fun align(value: Double): Int = (value.toInt() / ALIGNMENT * ALIGNMENT).coerceAtLeast(ALIGNMENT)

    private fun format(width: Int, height: Int) = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
        setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
        setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
        setInteger(MediaFormat.KEY_FRAME_RATE, FRAME_RATE)
        setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, KEY_FRAME_INTERVAL_S)
        setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, REPEAT_FRAME_US)
        setInteger(MediaFormat.KEY_PRIORITY, 0)
        setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
    }

    private fun sizeBytes(width: Int, height: Int) = ByteBuffer.allocate(8).putInt(width).putInt(height).array()

    companion object {
        const val KIND_SESSION = 0
        const val KIND_CONFIG = 1
        const val KIND_FRAME = 2
        const val KIND_KEY_FRAME = 3
        private const val ALIGNMENT = 16
        private const val FRAME_RATE = 60
        private const val KEY_FRAME_INTERVAL_S = 10
        private const val REPEAT_FRAME_US = 100_000L
        private const val DEQUEUE_TIMEOUT_US = 100_000L
    }
}
