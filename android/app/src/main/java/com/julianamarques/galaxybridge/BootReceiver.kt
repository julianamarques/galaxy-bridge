package com.julianamarques.galaxybridge

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.julianamarques.galaxybridge.bridge.BridgeService

/** Volta a conectar ao Mac depois de o celular reiniciar ou de o app ser atualizado, sem precisar abri-lo. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> BridgeService.start(context)
        }
    }
}
