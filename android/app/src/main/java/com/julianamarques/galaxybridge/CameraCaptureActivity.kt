package com.julianamarques.galaxybridge

import android.app.Activity
import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import android.widget.Toast
import androidx.core.content.FileProvider
import com.julianamarques.galaxybridge.bridge.BridgeService
import java.io.File
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

class CameraCaptureActivity : Activity() {
    private var photo: File? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        getSystemService(NotificationManager::class.java).cancel(BridgeService.CAMERA_REQUEST_ID)
        photo = savedInstanceState?.getString(STATE_PHOTO)?.let(::File)
        if (savedInstanceState != null) return
        val folder = File(cacheDir, FOLDER).apply { mkdirs() }
        val file = File(folder, "Galaxy_${LocalDateTime.now().format(NAME_FORMAT)}.jpg")
        photo = file
        val output = FileProvider.getUriForFile(this, "$packageName.files", file)
        val locked = getSystemService(KeyguardManager::class.java).isKeyguardLocked
        val capture = Intent(if (locked) MediaStore.ACTION_IMAGE_CAPTURE_SECURE else MediaStore.ACTION_IMAGE_CAPTURE)
            .putExtra(MediaStore.EXTRA_OUTPUT, output)
            .addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        try {
            startActivityForResult(capture, REQUEST)
        } catch (e: ActivityNotFoundException) {
            Toast.makeText(this, R.string.camera_unavailable, Toast.LENGTH_SHORT).show()
            finish()
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        photo?.let { outState.putString(STATE_PHOTO, it.path) }
    }

    @Deprecated("Activity result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val file = photo
        if (requestCode == REQUEST && resultCode == RESULT_OK && file != null && file.length() > 0) {
            if (!BridgeService.captured(Uri.fromFile(file))) {
                Toast.makeText(this, R.string.share_not_connected, Toast.LENGTH_SHORT).show()
                file.delete()
            }
        } else {
            file?.delete()
        }
        finish()
    }

    private companion object {
        const val REQUEST = 1
        const val FOLDER = "camera"
        const val STATE_PHOTO = "photo"
        val NAME_FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss")
    }
}
