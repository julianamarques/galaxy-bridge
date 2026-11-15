package com.julianamarques.galaxybridge.mirror

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import com.julianamarques.galaxybridge.bridge.BridgeService

class MirrorConsentActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState != null) return
        val projections = getSystemService(MediaProjectionManager::class.java)
        startActivityForResult(projections.createScreenCaptureIntent(), REQUEST)
    }

    @Deprecated("Activity result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST) return
        if (resultCode == RESULT_OK && data != null) {
            ScreenMirrorService.start(this, resultCode, data, intent.extras)
        } else {
            BridgeService.mirrorDeclined(this)
        }
        finish()
    }

    private companion object {
        const val REQUEST = 1
    }
}
