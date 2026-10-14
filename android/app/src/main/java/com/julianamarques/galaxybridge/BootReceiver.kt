package com.julianamarques.galaxybridge

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.julianamarques.galaxybridge.bridge.BridgeService

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> BridgeService.start(context)
        }
    }
}
