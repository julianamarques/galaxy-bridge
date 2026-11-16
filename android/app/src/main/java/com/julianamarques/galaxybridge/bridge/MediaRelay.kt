package com.julianamarques.galaxybridge.bridge

import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import com.julianamarques.galaxybridge.Diagnostics
import com.julianamarques.galaxybridge.protocol.MediaControl
import com.julianamarques.galaxybridge.protocol.MediaState

class MediaRelay(private val context: Context, private val onChange: (MediaState) -> Unit) {
    private val handler = Handler(Looper.getMainLooper())
    private val sessions = context.getSystemService(MediaSessionManager::class.java)
    private val component = ComponentName(context, NotificationListener::class.java)
    private var controller: MediaController? = null
    private var listening = false
    private var artwork: Pair<String, String?>? = null

    @Volatile var current = MediaState(playing = false)
        private set

    private val sessionsChanged = MediaSessionManager.OnActiveSessionsChangedListener { follow(it.orEmpty()) }

    private val callback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) = publish()
        override fun onMetadataChanged(metadata: MediaMetadata?) = publish()
        override fun onSessionDestroyed() = follow(activeSessions())
    }

    fun start() {
        handler.post {
            if (listening) return@post
            val result = runCatching { sessions.addOnActiveSessionsChangedListener(sessionsChanged, component, handler) }
            listening = result.isSuccess
            Diagnostics.record(context, "Mídia: ${result.exceptionOrNull()?.let { "sem acesso (${it.javaClass.simpleName})" } ?: "acompanhando"}")
            if (listening) follow(activeSessions())
        }
    }

    fun stop() {
        handler.post {
            if (listening) runCatching { sessions.removeOnActiveSessionsChangedListener(sessionsChanged) }
            listening = false
            controller?.unregisterCallback(callback)
            controller = null
        }
    }

    fun control(action: String) {
        handler.post {
            val controls = controller?.transportControls ?: return@post
            when (action) {
                MediaControl.PLAY -> controls.play()
                MediaControl.PAUSE -> controls.pause()
                MediaControl.NEXT -> controls.skipToNext()
                MediaControl.PREVIOUS -> controls.skipToPrevious()
            }
        }
    }

    private fun activeSessions(): List<MediaController> = runCatching { sessions.getActiveSessions(component) }.getOrDefault(emptyList())

    private fun follow(controllers: List<MediaController>) {
        val next = controllers.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING } ?: controllers.firstOrNull()
        if (next?.sessionToken != controller?.sessionToken) {
            controller?.unregisterCallback(callback)
            controller = next
            next?.registerCallback(callback, handler)
        }
        publish()
    }

    private fun publish() {
        val state = controller?.let(::state) ?: MediaState(playing = false)
        if (state == current) return
        current = state
        Diagnostics.record(context, "Mídia: ${state.app ?: "nada"}, ${if (state.playing) "tocando" else "parado"}, título=${state.title != null}")
        onChange(state)
    }

    private fun state(controller: MediaController): MediaState {
        val metadata = controller.metadata
        val title = metadata?.getString(MediaMetadata.METADATA_KEY_TITLE)?.takeIf { it.isNotBlank() } ?: return MediaState(playing = false)
        val artist = metadata.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: metadata.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
        val app = controller.packageName
        return MediaState(
            app = app,
            appName = appName(app),
            title = title,
            artist = artist?.takeIf { it.isNotBlank() },
            playing = controller.playbackState?.state in PLAYING_STATES,
            artwork = artwork(metadata, "$app|$title|$artist"),
        )
    }

    private fun artwork(metadata: MediaMetadata, key: String): String? {
        artwork?.takeIf { it.first == key }?.let { return it.second }
        val bitmap = ARTWORK_KEYS.firstNotNullOfOrNull { metadata.getBitmap(it) }
        val encoded = bitmap?.let { runCatching { it.toBase64(ARTWORK_PX, quality = JPEG_QUALITY) }.getOrNull() }
        artwork = key to encoded
        return encoded
    }

    private fun appName(app: String): String? = runCatching {
        val manager = context.packageManager
        manager.getApplicationLabel(manager.getApplicationInfo(app, 0)).toString()
    }.getOrNull()

    private companion object {
        const val ARTWORK_PX = 160
        const val JPEG_QUALITY = 80
        val ARTWORK_KEYS = listOf(MediaMetadata.METADATA_KEY_ART, MediaMetadata.METADATA_KEY_ALBUM_ART, MediaMetadata.METADATA_KEY_DISPLAY_ICON)
        val PLAYING_STATES = setOf(PlaybackState.STATE_PLAYING, PlaybackState.STATE_BUFFERING, PlaybackState.STATE_CONNECTING)
    }
}
