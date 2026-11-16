package com.julianamarques.galaxybridge.bridge

import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Environment
import com.julianamarques.galaxybridge.protocol.FilesListing
import com.julianamarques.galaxybridge.protocol.PhoneFile
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

object PhoneFiles {
    private const val SCAN_TIMEOUT_S = 3L
    const val MAX_FILES = 5_000
    private val root: File get() = Environment.getExternalStorageDirectory().canonicalFile

    fun canRead(): Boolean = Environment.isExternalStorageManager()

    fun list(path: String): FilesListing? {
        val folder = folder(path) ?: return null
        val files = folder.listFiles().orEmpty()
            .filter { !it.name.startsWith(".") }
            .map { PhoneFile(it.name, it.isDirectory, if (it.isDirectory) 0 else it.length(), it.lastModified()) }
            .sortedWith(compareBy<PhoneFile> { !it.folder }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.name })
        val truncated = files.size > MAX_FILES
        return FilesListing(relative(folder), files.take(MAX_FILES), truncated.takeIf { it })
    }

    fun file(path: String): File? = resolve(path)?.takeIf { it.isFile && canRead() }

    fun folder(path: String): File? = resolve(path)?.takeIf { it.isDirectory && canRead() }

    fun unique(folder: File, name: String): File {
        val base = name.substringBeforeLast('.', name)
        val ext = name.substringAfterLast('.', "").let { if (it.isEmpty() || it == name) "" else ".$it" }
        return generateSequence(1) { it + 1 }
            .map { if (it == 1) File(folder, name) else File(folder, "$base ($it)$ext") }
            .first { !it.exists() }
    }

    fun scan(context: Context, file: File): Uri? {
        val latch = CountDownLatch(1)
        var uri: Uri? = null
        MediaScannerConnection.scanFile(context, arrayOf(file.path), null) { _, scanned ->
            uri = scanned
            latch.countDown()
        }
        latch.await(SCAN_TIMEOUT_S, TimeUnit.SECONDS)
        return uri
    }

    private fun resolve(path: String): File? {
        val root = root
        val file = File(root, path.trim('/')).canonicalFile
        return file.takeIf { it == root || it.path.startsWith(root.path + File.separator) }
    }

    private fun relative(file: File): String = file.path.removePrefix(root.path).trim('/')
}
