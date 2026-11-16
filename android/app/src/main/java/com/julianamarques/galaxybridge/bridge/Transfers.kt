package com.julianamarques.galaxybridge.bridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Base64
import android.webkit.MimeTypeMap
import com.julianamarques.galaxybridge.Diagnostics
import com.julianamarques.galaxybridge.R
import com.julianamarques.galaxybridge.protocol.Envelope
import com.julianamarques.galaxybridge.protocol.Message
import com.julianamarques.galaxybridge.protocol.TransferChunk
import com.julianamarques.galaxybridge.protocol.TransferFile
import com.julianamarques.galaxybridge.protocol.TransferID
import com.julianamarques.galaxybridge.protocol.TransferResult
import java.io.IOException
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.text.NumberFormat
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

class Transfers(private val context: Context) {
    private data class Source(val name: String, val size: Long, val mime: String?)

    private val executor = Executors.newSingleThreadExecutor { Thread(it, "transfers") }
    private val notifications = context.getSystemService(NotificationManager::class.java)
    private val nextNotification = AtomicInteger(FIRST_NOTIFICATION)

    init {
        val channel = NotificationChannel(CHANNEL_ID, context.getString(R.string.channel_transfers), NotificationManager.IMPORTANCE_LOW)
        notifications.createNotificationChannel(channel)
    }

    fun upload(uris: List<Uri>, capture: Boolean = false) {
        uris.forEach { uri -> executor.execute { upload(uri, capture) } }
    }

    fun download(file: TransferFile) {
        executor.execute { download(file, nextNotification.getAndIncrement()) }
    }

    fun shutdown() {
        executor.shutdownNow()
    }

    private fun upload(uri: Uri, capture: Boolean) {
        val notification = nextNotification.getAndIncrement()
        val source = runCatching { describe(uri) }.getOrNull()
        if (source == null) return finished(notification, nameOf(uri), context.getString(R.string.transfer_unreadable))
        val error = runCatching { send(uri, source, Progress(notification, R.string.transfer_sending, source.name, source.size), capture) }.getOrElse(::describeError)
        if (capture) uri.path?.let { java.io.File(it).delete() }
        Diagnostics.record(context, "Envio para o Mac: ${if (error == null) "concluído" else "falhou"}, ${source.size} bytes")
        finished(notification, source.name, error)
    }

    private fun download(file: TransferFile, notification: Int) {
        val name = file.name.substringAfterLast('/').ifBlank { context.getString(R.string.transfer_file_from_mac) }
        val result = runCatching { receive(file, name, Progress(notification, R.string.transfer_receiving, name, file.size)) }
        Diagnostics.record(context, "Recebimento do Mac: ${if (result.isSuccess) "concluído" else "falhou"}, ${file.size} bytes")
        result.fold(
            onSuccess = { received(notification, name, it) },
            onFailure = { finished(notification, name, describeError(it), R.string.transfer_receive_failed) },
        )
    }

    private fun describeError(error: Throwable): String =
        (error as? BridgeConnection.Unavailable)?.message ?: context.getString(R.string.transfer_connection_lost, error.javaClass.simpleName)

    private fun openMac(): BridgeConnection {
        return BridgeConnection.openPaired(context).apply {
            receiveTimeoutMs = RESULT_TIMEOUT_MS
            sendBufferBytes = SEND_BUFFER_BYTES
        }
    }

    private inner class Progress(private val notification: Int, private val title: Int, private val name: String, private val total: Long) {
        var done = 0L
            private set
        private var shown = 0

        init {
            progress(notification, title, name, 0)
        }

        fun advance(bytes: Int) {
            done += bytes
            val percent = (done * 100 / total).toInt()
            if (percent < shown + PROGRESS_STEP) return
            shown = percent
            progress(notification, title, name, percent)
        }
    }

    private class Destination(val open: () -> OutputStream, val commit: () -> Uri?, val discard: () -> Unit)

    private fun destination(file: TransferFile, name: String): Destination {
        val folder = file.folder?.let(PhoneFiles::folder)
        if (folder != null) {
            val target = PhoneFiles.unique(folder, name)
            return Destination({ FileOutputStream(target) }, { PhoneFiles.scan(context, target) }, { target.delete() })
        }
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, file.mime ?: mimeType(name))
            put(MediaStore.Downloads.RELATIVE_PATH, DOWNLOAD_FOLDER)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: throw IOException("sem espaço")
        return Destination(
            open = { resolver.openOutputStream(uri)!! },
            commit = {
                resolver.update(uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
                uri
            },
            discard = { resolver.delete(uri, null, null) },
        )
    }

    private fun receive(file: TransferFile, name: String, progress: Progress): Uri? {
        openMac().use {
            var destination: Destination? = null
            try {
                val target = destination(file, name).also { destination = it }
                it.sendNow(Envelope(Message.TransferDownloadMessage(TransferID(file.id))))
                target.open().use { output ->
                    while (progress.done < file.size) {
                        val chunk = (it.receive().message as? Message.TransferChunkMessage)?.body ?: throw IOException("mensagem inesperada")
                        val bytes = Base64.decode(chunk.data, Base64.NO_WRAP)
                        if (progress.done + bytes.size > file.size) throw IOException("o arquivo mudou durante o envio")
                        output.write(bytes)
                        progress.advance(bytes.size)
                    }
                }
                val uri = target.commit()
                it.sendNow(Envelope(Message.TransferResultMessage(TransferResult(file.id, ok = true))))
                return uri
            } catch (e: Exception) {
                destination?.discard()
                runCatching { it.sendNow(Envelope(Message.TransferResultMessage(TransferResult(file.id, ok = false, e.message)))) }
                throw e
            }
        }
    }

    private fun mimeType(name: String): String =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase()) ?: "application/octet-stream"

    private fun describe(uri: Uri): Source? {
        val resolver = context.contentResolver
        var name: String? = null
        var size = -1L
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                name = cursor.getString(0)
                if (!cursor.isNull(1)) size = cursor.getLong(1)
            }
        }
        if (size < 0) size = resolver.openAssetFileDescriptor(uri, "r")?.use { it.length } ?: -1
        if (size < 0) return null
        return Source(name ?: nameOf(uri), size, resolver.getType(uri))
    }

    private fun nameOf(uri: Uri): String = uri.lastPathSegment ?: context.getString(R.string.transfer_file)

    private fun send(uri: Uri, source: Source, progress: Progress, capture: Boolean): String? {
        openMac().use {
            val id = UUID.randomUUID().toString()
            it.sendNow(Envelope(Message.TransferUploadMessage(TransferFile(id, source.name, source.size, source.mime, capture = capture.takeIf { it }))))
            val input = context.contentResolver.openInputStream(uri) ?: return context.getString(R.string.transfer_unreadable)
            input.use { stream ->
                val buffer = ByteArray(CHUNK_SIZE)
                while (progress.done < source.size) {
                    val read = fill(stream, buffer, minOf(CHUNK_SIZE.toLong(), source.size - progress.done).toInt())
                    if (read <= 0) return context.getString(R.string.transfer_file_changed)
                    it.sendNow(Envelope(Message.TransferChunkMessage(TransferChunk(id, Base64.encodeToString(buffer, 0, read, Base64.NO_WRAP)))))
                    progress.advance(read)
                }
            }
            val result = (it.receive().message as? Message.TransferResultMessage)?.body
            return if (result?.ok == true) null else result?.message ?: context.getString(R.string.transfer_not_confirmed)
        }
    }

    private fun fill(input: InputStream, buffer: ByteArray, length: Int): Int {
        var total = 0
        while (total < length) {
            val read = input.read(buffer, total, length - total)
            if (read < 0) break
            total += read
        }
        return total
    }

    private fun builder(title: Int, name: String): Notification.Builder =
        Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(title))
            .setContentText(name)

    private fun progress(notification: Int, title: Int, name: String, percent: Int) {
        notifications.notify(
            notification,
            builder(title, name)
                .setProgress(100, percent, percent == 0)
                .setSubText(NumberFormat.getPercentInstance().format(percent / 100.0))
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .build(),
        )
    }

    private fun received(notification: Int, name: String, file: Uri?) {
        val builder = builder(R.string.transfer_received, name).setAutoCancel(true)
        if (file != null) {
            val open = Intent(Intent.ACTION_VIEW).setDataAndType(file, context.contentResolver.getType(file))
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            builder.setContentIntent(PendingIntent.getActivity(context, notification, open, PendingIntent.FLAG_IMMUTABLE))
        }
        notifications.notify(notification, builder.build())
    }

    private fun finished(notification: Int, name: String, error: String?, failure: Int = R.string.transfer_failed) {
        notifications.notify(
            notification,
            builder(if (error == null) R.string.transfer_sent else failure, if (error == null) name else "$name: $error")
                .setStyle(Notification.BigTextStyle().bigText(if (error == null) name else "$name\n$error"))
                .setAutoCancel(true)
                .build(),
        )
    }

    companion object {
        private const val CHANNEL_ID = "transfers"
        private const val CHUNK_SIZE = 64 * 1024
        private const val FIRST_NOTIFICATION = 100
        private const val PROGRESS_STEP = 5
        private const val SEND_BUFFER_BYTES = 64 * 1024
        private const val RESULT_TIMEOUT_MS = 5 * 60_000
        private const val DOWNLOAD_FOLDER = "Download/Galaxy Bridge"
    }
}
