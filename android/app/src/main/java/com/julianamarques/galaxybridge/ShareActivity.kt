package com.julianamarques.galaxybridge

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import com.julianamarques.galaxybridge.bridge.BridgeService
import com.julianamarques.galaxybridge.bridge.PairingStore
import com.julianamarques.galaxybridge.bridge.parcelable
import com.julianamarques.galaxybridge.bridge.parcelables

class ShareActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val extras = intent.extras
        val files = when (intent.action) {
            Intent.ACTION_SEND -> listOfNotNull(extras?.parcelable<Uri>(Intent.EXTRA_STREAM))
            Intent.ACTION_SEND_MULTIPLE -> extras?.parcelables<Uri>(Intent.EXTRA_STREAM).orEmpty()
            else -> emptyList()
        }
        val text = extras?.getCharSequence(Intent.EXTRA_TEXT)?.toString()
        val message = when {
            PairingStore.current(this) == null -> R.string.share_not_paired
            files.isEmpty() && !text.isNullOrBlank() -> if (BridgeService.copyToMac(text)) R.string.share_copied else R.string.share_not_connected
            files.isEmpty() -> R.string.share_nothing
            else -> if (runCatching { BridgeService.send(this, files) }.isSuccess) R.string.share_sending else R.string.share_unreadable
        }
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        finish()
    }
}
