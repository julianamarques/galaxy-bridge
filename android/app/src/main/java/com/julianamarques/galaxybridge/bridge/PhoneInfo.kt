package com.julianamarques.galaxybridge.bridge

import android.content.Context
import android.content.Intent
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.Settings
import android.telephony.TelephonyManager
import com.julianamarques.galaxybridge.BuildConfig
import com.julianamarques.galaxybridge.protocol.Hello
import com.julianamarques.galaxybridge.protocol.PhoneStatus

object PhoneInfo {
    fun name(context: Context): String =
        Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)?.takeIf { it.isNotBlank() }
            ?: Build.MODEL

    fun hello(context: Context) = Hello(appVersion = BuildConfig.VERSION_NAME, name = name(context), model = Build.MODEL)

    fun status(context: Context, battery: Intent, signals: PhoneSignals?): PhoneStatus {
        val level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, 100).takeIf { it > 0 } ?: 100
        val status = battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val telephony = context.getSystemService(TelephonyManager::class.java)
        return PhoneStatus(
            battery = PhoneStatus.Battery(
                level = (level * 100 / scale).coerceIn(0, 100),
                charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL,
            ),
            networkCountry = telephony?.networkCountryIso?.takeIf { it.isNotBlank() }?.uppercase(),
            simCountry = telephony?.simCountryIso?.takeIf { it.isNotBlank() }?.uppercase(),
            carrier = (telephony?.networkOperatorName?.takeIf { it.isNotBlank() } ?: telephony?.simOperatorName)?.takeIf { it.isNotBlank() },
            signal = signals?.signal,
            network = signals?.network,
            wifi = signals?.wifi,
            storage = storage(),
            dnd = NotificationListener.dnd,
        )
    }

    private fun storage(): PhoneStatus.Storage? = runCatching {
        val stat = StatFs(Environment.getDataDirectory().path)
        PhoneStatus.Storage(free = stat.availableBytes / STORAGE_STEP * STORAGE_STEP, total = stat.totalBytes)
    }.getOrNull()

    private const val STORAGE_STEP = 100_000_000L
}
