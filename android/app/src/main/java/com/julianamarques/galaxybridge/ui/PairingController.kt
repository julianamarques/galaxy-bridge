package com.julianamarques.galaxybridge.ui

import android.app.Activity
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.julianamarques.galaxybridge.R
import com.julianamarques.galaxybridge.bridge.BridgeService
import com.julianamarques.galaxybridge.bridge.Pairing
import com.julianamarques.galaxybridge.protocol.PairingLink
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

sealed interface PairingStep {
    data object Idle : PairingStep
    data object Working : PairingStep
    data class Failed(val message: String) : PairingStep
}

class PairingController(context: Context, private val scope: CoroutineScope) {
    private val context = context.applicationContext
    var step by mutableStateOf<PairingStep>(PairingStep.Idle)
        private set

    fun scan(activity: Activity) {
        val options = GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()
        GmsBarcodeScanning.getClient(activity, options).startScan()
            .addOnSuccessListener { barcode ->
                val link = barcode.rawValue?.let(PairingLink::parse)
                if (link != null) pair(link)
                else step = PairingStep.Failed(context.getString(R.string.pairing_not_our_code))
            }
            .addOnFailureListener { step = PairingStep.Failed(context.getString(R.string.pairing_scanner_failed, it.message.orEmpty())) }
    }

    fun pair(link: PairingLink) {
        step = PairingStep.Working
        scope.launch {
            finish(withContext(Dispatchers.IO) { Pairing.pair(context, link) })
        }
    }

    private fun finish(result: Pairing.Result) {
        step = when (result) {
            Pairing.Result.Paired -> {
                BridgeService.start(context)
                PairingStep.Idle
            }
            is Pairing.Result.Failed -> PairingStep.Failed(result.message)
        }
    }
}
