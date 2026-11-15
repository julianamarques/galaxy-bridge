package com.julianamarques.galaxybridge.bridge

import android.Manifest
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.telephony.SignalStrength
import android.telephony.TelephonyCallback
import android.telephony.TelephonyDisplayInfo
import android.telephony.TelephonyManager
import com.julianamarques.galaxybridge.Permission

class PhoneSignals(private val context: Context, private val onChange: () -> Unit) {
    @Volatile var signal: Int? = null
        private set
    @Volatile var network: String? = null
        private set
    @Volatile var wifi: Int? = null
        private set

    private val telephony = context.getSystemService(TelephonyManager::class.java)
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val wifiManager = context.getSystemService(WifiManager::class.java)
    private var callback: TelephonyCallback? = null
    private var watchingWifi = false

    private val wifiCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
            val level = if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) wifiLevel(capabilities.signalStrength) else null
            if (level != wifi) {
                wifi = level
                onChange()
            }
        }

        override fun onLost(network: Network) {
            if (wifi == null) return
            wifi = null
            onChange()
        }
    }

    private inner class SignalCallback : TelephonyCallback(), TelephonyCallback.SignalStrengthsListener {
        override fun onSignalStrengthsChanged(strength: SignalStrength) {
            if (strength.level == signal) return
            signal = strength.level
            onChange()
        }
    }

    private inner class FullCallback : TelephonyCallback(), TelephonyCallback.SignalStrengthsListener, TelephonyCallback.DisplayInfoListener {
        private val signals = SignalCallback()

        override fun onSignalStrengthsChanged(strength: SignalStrength) = signals.onSignalStrengthsChanged(strength)

        override fun onDisplayInfoChanged(info: TelephonyDisplayInfo) {
            val label = label(info)
            if (label == network) return
            network = label
            onChange()
        }
    }

    fun start() {
        if (!watchingWifi) {
            watchingWifi = runCatching { connectivity.registerDefaultNetworkCallback(wifiCallback) }.isSuccess
        }
        val full = Permission.has(context, Manifest.permission.READ_PHONE_STATE)
        if (callback is FullCallback || (callback != null && !full)) return
        stopTelephony()
        val next = if (full) FullCallback() else SignalCallback()
        runCatching { telephony.registerTelephonyCallback(context.mainExecutor, next) }.onSuccess { callback = next }
    }

    fun stop() {
        stopTelephony()
        if (watchingWifi) runCatching { connectivity.unregisterNetworkCallback(wifiCallback) }
        watchingWifi = false
    }

    private fun stopTelephony() {
        callback?.let { runCatching { telephony.unregisterTelephonyCallback(it) } }
        callback = null
    }

    private fun wifiLevel(rssi: Int): Int {
        val max = wifiManager.maxSignalLevel.takeIf { it > 0 } ?: return 0
        return (wifiManager.calculateSignalLevel(rssi) * MAX_LEVEL + max / 2) / max
    }

    private fun label(info: TelephonyDisplayInfo): String? = when (info.overrideNetworkType) {
        TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NR_NSA, TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NR_ADVANCED -> "5G"
        TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_LTE_CA, TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_LTE_ADVANCED_PRO -> "4G+"
        else -> when (info.networkType) {
            TelephonyManager.NETWORK_TYPE_NR -> "5G"
            TelephonyManager.NETWORK_TYPE_LTE, TelephonyManager.NETWORK_TYPE_IWLAN -> "4G"
            TelephonyManager.NETWORK_TYPE_HSPAP, TelephonyManager.NETWORK_TYPE_HSPA, TelephonyManager.NETWORK_TYPE_HSDPA,
            TelephonyManager.NETWORK_TYPE_HSUPA, TelephonyManager.NETWORK_TYPE_UMTS, TelephonyManager.NETWORK_TYPE_TD_SCDMA,
            TelephonyManager.NETWORK_TYPE_EVDO_0, TelephonyManager.NETWORK_TYPE_EVDO_A, TelephonyManager.NETWORK_TYPE_EVDO_B,
            TelephonyManager.NETWORK_TYPE_EHRPD -> "3G"
            TelephonyManager.NETWORK_TYPE_EDGE, TelephonyManager.NETWORK_TYPE_GPRS, TelephonyManager.NETWORK_TYPE_GSM,
            TelephonyManager.NETWORK_TYPE_CDMA, TelephonyManager.NETWORK_TYPE_1xRTT -> "2G"
            else -> null
        }
    }

    private companion object {
        const val MAX_LEVEL = 4
    }
}
