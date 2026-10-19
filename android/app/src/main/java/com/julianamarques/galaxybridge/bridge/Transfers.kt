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
import java.io.InputStream
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

    fun upload(uris: List<Uri>) {
        uris.forEach { uri -> executor.execute { upload(uri) } }
    }

    fun download(file: TransferFile) {
        executor.execute { download(file, nextNotification.getAndIncrement()) }
    }

    fun shutdown() {
        executor.shutdownNow()
    }

    private fun upload(uri: Uri) {
        val notification = nextNotification.getAndIncrement()
        val source = runCatching { describe(uri) }.getOrNull()
        if (source == null) return finished(notification, uri.lastPathSegment ?: "Arquivo", "Não foi possível ler o arquivo.")
        progress(notification, R.string.transfer_sending, source.name, 0)
        val error = runCatching { send(uri, source, notification) }.getOrElse { "A conexão com o Mac caiu (${it.javaClass.simpleName})." }
        Diagnostics.record(context, "Envio para o Mac: ${if (error == null) "concluído" else "falhou"}, ${source.size} bytes")
        finished(notification, source.name, error)
    }

    private fun download(file: TransferFile, notification: Int) {
        val name = file.name.substringAfterLast('/').ifBlank { "Arquivo do Mac" }
        progress(notification, R.string.transfer_receiving, name, 0)
        val result = runCatching { receive(file, name, notification) }
        Diagnostics.record(context, "Recebimento do Mac: ${if (result.isSuccess) "concluído" else "falhou"}, ${file.size} bytes")
        result.fold(
            onSuccess = { received(notification, name, it) },
            onFailure = { finished(notification, name, "A conexão com o Mac caiu (${it.javaClass.simpleName}).", R.string.transfer_receive_failed) },
        )
    }

    private fun receive(file: TransferFile, name: String, notification: Int): Uri {
        val mac = PairingStore.current(context) ?: throw IOException("sem Mac pareado")
        val connection = BridgeConnection.openPinned(context, mac.host, mac.port, mac.fingerprint, DISCOVERY_TIMEOUT_MS)
            ?: throw IOException("Mac não encontrado")
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, name)
            put(MediaStore.Downloads.MIME_TYPE, file.mime ?: mimeType(name))
            put(MediaStore.Downloads.RELATIVE_PATH, DOWNLOAD_FOLDER)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: throw IOException("sem espaço")
        connection.use {
            try {
                it.receiveTimeoutMs = RESULT_TIMEOUT_MS
                it.sendNow(Envelope(Message.TransferDownloadMessage(TransferID(file.id))))
                resolver.openOutputStream(uri)!!.use { output ->
                    var received = 0L
                    var shown = 0
                    while (received < file.size) {
                        val chunk = (it.receive().message as? Message.TransferChunkMessage)?.body ?: throw IOException("mensagem inesperada")
                        val bytes = Base64.decode(chunk.data, Base64.NO_WRAP)
                        output.write(bytes)
                        received += bytes.size
                        val percent = (received * 100 / file.size).toInt()
                        if (percent >= shown + PROGRESS_STEP) {
                            shown = percent
                            progress(notification, R.string.transfer_receiving, name, percent)
                        }
                    }
                }
                resolver.update(uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
                it.sendNow(Envelope(Message.TransferResultMessage(TransferResult(file.id, ok = true))))
                return uri
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
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
        return Source(name ?: uri.lastPathSegment ?: "Arquivo", size, resolver.getType(uri))
    }

    private fun send(uri: Uri, source: Source, notification: Int): String? {
        val mac = PairingStore.current(context) ?: return "Este celular não está pareado com um Mac."
        val connection = BridgeConnection.openPinned(context, mac.host, mac.port, mac.fingerprint, DISCOVERY_TIMEOUT_MS)
            ?: return "O Mac não foi encontrado. Confira se ele está ligado e na mesma rede Wi-Fi."
        connection.use {
            it.receiveTimeoutMs = RESULT_TIMEOUT_MS
            val id = UUID.randomUUID().toString()
            it.sendNow(Envelope(Message.TransferUploadMessage(TransferFile(id, source.name, source.size, source.mime))))
            val input = context.contentResolver.openInputStream(uri) ?: return "Não foi possível ler o arquivo."
            input.use { stream ->
                val buffer = ByteArray(CHUNK_SIZE)
                var sent = 0L
                var shown = 0
                while (sent < source.size) {
                    val read = fill(stream, buffer, minOf(CHUNK_SIZE.toLong(), source.size - sent).toInt())
                    if (read <= 0) return "O arquivo mudou durante o envio."
                    it.sendNow(Envelope(Message.TransferChunkMessage(TransferChunk(id, Base64.encodeToString(buffer, 0, read, Base64.NO_WRAP)))))
                    sent += read
                    val percent = (sent * 100 / source.size).toInt()
                    if (percent >= shown + PROGRESS_STEP) {
                        shown = percent
                        progress(notification, R.string.transfer_sending, source.name, percent)
                    }
                }
            }
            val result = (it.receive().message as? Message.TransferResultMessage)?.body
            return if (result?.ok == true) null else result?.message ?: "O Mac não confirmou o recebimento."
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

    private fun progress(notification: Int, title: Int, name: String, percent: Int) {
        notifications.notify(
            notification,
            Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(context.getString(title))
                .setContentText(name)
                .setProgress(100, percent, percent == 0)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .build(),
        )
    }

    private fun received(notification: Int, name: String, file: Uri) {
        val open = Intent(Intent.ACTION_VIEW).setDataAndType(file, context.contentResolver.getType(file))
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        notifications.notify(
            notification,
            Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(context.getString(R.string.transfer_received))
                .setContentText(name)
                .setContentIntent(PendingIntent.getActivity(context, notification, open, PendingIntent.FLAG_IMMUTABLE))
                .setAutoCancel(true)
                .build(),
        )
    }

    private fun finished(notification: Int, name: String, error: String?, failure: Int = R.string.transfer_failed) {
        notifications.notify(
            notification,
            Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(context.getString(if (error == null) R.string.transfer_sent else failure))
                .setContentText(if (error == null) name else "$name: $error")
                .setStyle(Notification.BigTextStyle().bigText(if (error == null) name else "$name\n$error"))
                .setAutoCancel(true)
                .build(),
        )
    }

    companion object {
        private const val CHANNEL_ID = "transfers"
        private const val CHUNK_SIZE = 256 * 1024
        private const val FIRST_NOTIFICATION = 100
        private const val PROGRESS_STEP = 5
        private const val DISCOVERY_TIMEOUT_MS = 10_000L
        private const val RESULT_TIMEOUT_MS = 5 * 60_000
        private const val DOWNLOAD_FOLDER = "Download/Galaxy Bridge"
    }
}
