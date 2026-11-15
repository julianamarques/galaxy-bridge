package com.julianamarques.galaxybridge

import android.app.Activity
import android.hardware.usb.UsbAccessory
import android.hardware.usb.UsbManager
import android.os.Bundle
import com.julianamarques.galaxybridge.bridge.BridgeService
import com.julianamarques.galaxybridge.bridge.UsbTunnel
import com.julianamarques.galaxybridge.bridge.parcelable

class UsbAccessoryActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val accessory = intent.extras?.parcelable<UsbAccessory>(UsbManager.EXTRA_ACCESSORY)
        if (accessory != null && UsbTunnel.isOurs(accessory)) {
            UsbTunnel.start(applicationContext, accessory)
            BridgeService.start(this)
        }
        finish()
    }
}
