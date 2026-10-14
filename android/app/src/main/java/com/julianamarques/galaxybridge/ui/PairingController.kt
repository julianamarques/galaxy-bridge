package com.julianamarques.galaxybridge.ui

import android.app.Activity
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.julianamarques.galaxybridge.bridge.BridgeConnection
import com.julianamarques.galaxybridge.bridge.BridgeService
import com.julianamarques.galaxybridge.bridge.Identity
import com.julianamarques.galaxybridge.bridge.MacFinder
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

    data class CodeEntry(
        val macs: List<MacFinder.Found> = emptyList(),
        val searching: Boolean = true,
        val selected: MacFinder.Found? = null,
        val code: String = "",
        val connecting: Boolean = false,
        val error: String? = null,
    ) : PairingStep

    data class Confirm(val connection: BridgeConnection, val fingerprint: String, val code: String) : PairingStep
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
                else step = PairingStep.Failed("Este não é um código do Galaxy Bridge. Escaneie o código que aparece no Mac.")
            }
            .addOnFailureListener { step = PairingStep.Failed("Não foi possível abrir o leitor de códigos: ${it.message}") }
    }

    fun pair(link: PairingLink) {
        step = PairingStep.Working
        scope.launch {
            finish(withContext(Dispatchers.IO) { Pairing.pair(context, link) })
        }
    }

    fun startCode() {
        step = PairingStep.CodeEntry()
        scope.launch {
            val macs = withContext(Dispatchers.IO) { MacFinder(context).findAll(SEARCH_MS) }
            val current = step as? PairingStep.CodeEntry ?: return@launch
            step = current.copy(macs = macs, searching = false, selected = current.selected ?: macs.firstOrNull())
        }
    }

    fun updateCode(code: String) {
        val current = step as? PairingStep.CodeEntry ?: return
        step = current.copy(code = code.filter(Char::isDigit).take(6), error = null)
    }

    fun select(mac: MacFinder.Found) {
        val current = step as? PairingStep.CodeEntry ?: return
        step = current.copy(selected = mac)
    }

    fun submitCode() {
        val current = step as? PairingStep.CodeEntry ?: return
        val mac = current.selected ?: return
        if (current.code.length != 6) return
        step = current.copy(connecting = true, error = null)
        scope.launch {
            val connection = withContext(Dispatchers.IO) { runCatching { Pairing.connect(mac) }.getOrNull() }
            if (step !is PairingStep.CodeEntry) {
                connection?.close()
                return@launch
            }
            step = if (connection != null) {
                PairingStep.Confirm(connection, Identity.display(connection.macFingerprint), current.code)
            } else {
                current.copy(connecting = false, error = "Não foi possível conectar ao ${mac.name}.")
            }
        }
    }

    fun confirm() {
        val current = step as? PairingStep.Confirm ?: return
        step = PairingStep.Working
        scope.launch {
            finish(withContext(Dispatchers.IO) { Pairing.pair(context, current.connection, current.code) })
        }
    }

    fun cancel() {
        (step as? PairingStep.Confirm)?.connection?.let { connection ->
            scope.launch(Dispatchers.IO) { connection.close() }
        }
        step = PairingStep.Idle
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

    private companion object {
        const val SEARCH_MS = 4_000L
    }
}
