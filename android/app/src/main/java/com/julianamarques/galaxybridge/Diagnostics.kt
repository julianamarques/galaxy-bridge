package com.julianamarques.galaxybridge

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import java.io.File
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

object Diagnostics {
    const val TAG = "GalaxyBridge"
    private const val FILE_NAME = "diagnostics.log"
    private const val MAX_BYTES = 512 * 1024L
    private val time = DateTimeFormatter.ofPattern("MM-dd HH:mm:ss")

    fun record(context: Context, event: String) {
        Log.i(TAG, event)
        if (!BuildConfig.DEBUG) return
        val line = "${LocalDateTime.now().format(time)} $event | ${state(context)}\n"
        synchronized(this) {
            val file = File(context.filesDir, FILE_NAME)
            if (file.length() > MAX_BYTES) file.renameTo(File(context.filesDir, "$FILE_NAME.1"))
            file.appendText(line)
        }
    }

    private fun state(context: Context): String {
        val power = context.getSystemService(PowerManager::class.java)
        val battery = context.getSystemService(BatteryManager::class.java)
        val lightIdle = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && power.isDeviceLightIdleMode
        return listOfNotNull(
            "doze".takeIf { power.isDeviceIdleMode },
            "light idle".takeIf { lightIdle },
            if (power.isInteractive) "tela acesa" else "tela apagada",
            network(context),
            "${battery.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)}%",
            "carregando".takeIf { battery.isCharging },
        ).joinToString(", ")
    }

    private fun network(context: Context): String {
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val capabilities = connectivity.getNetworkCapabilities(connectivity.activeNetwork) ?: return "sem rede"
        return when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "dados móveis"
            else -> "outra rede"
        }
    }
}
