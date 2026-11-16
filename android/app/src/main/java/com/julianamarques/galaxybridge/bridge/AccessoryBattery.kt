package com.julianamarques.galaxybridge.bridge

import android.annotation.SuppressLint
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import com.julianamarques.galaxybridge.Permission
import com.julianamarques.galaxybridge.protocol.PhoneStatus
import java.util.concurrent.ConcurrentHashMap

@SuppressLint("MissingPermission")
class AccessoryBattery(private val context: Context, private val onChange: () -> Unit) {
    @Volatile var current: List<PhoneStatus.Accessory> = emptyList()
        private set

    private val devices = ConcurrentHashMap<String, BluetoothDevice>()
    private val levels = ConcurrentHashMap<String, Int>()
    private var registered = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val device = intent.extras?.parcelable<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE) ?: return
            val address = device.address
            when (intent.action) {
                BluetoothDevice.ACTION_ACL_CONNECTED -> devices[address] = device
                BluetoothDevice.ACTION_ACL_DISCONNECTED -> {
                    devices.remove(address)
                    levels.remove(address)
                }
                ACTION_BATTERY_LEVEL_CHANGED -> {
                    devices[address] = device
                    val level = intent.getIntExtra(EXTRA_BATTERY_LEVEL, -1)
                    if (level in 0..100) levels[address] = level else levels.remove(address)
                }
            }
            publish()
        }
    }

    fun start() {
        if (registered || !Permission.NearbyDevices.isGranted(context)) return
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
            addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
            addAction(ACTION_BATTERY_LEVEL_CHANGED)
        }
        registered = runCatching { context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED) }.isSuccess
        if (!registered) return
        runCatching {
            context.getSystemService(BluetoothManager::class.java).adapter?.bondedDevices.orEmpty()
                .filter { isConnected(it) }
                .forEach { devices[it.address] = it }
        }
        publish()
    }

    fun stop() {
        if (registered) runCatching { context.unregisterReceiver(receiver) }
        registered = false
    }

    private fun publish() {
        val accessories = runCatching {
            devices.values.mapNotNull { device ->
                val level = levels[device.address] ?: batteryLevel(device)?.also { levels[device.address] = it } ?: return@mapNotNull null
                PhoneStatus.Accessory(device.alias ?: device.name ?: device.address, level, kind(device))
            }.sortedBy { it.name }
        }.getOrDefault(emptyList())
        if (accessories == current) return
        current = accessories
        onChange()
    }

    private fun kind(device: BluetoothDevice): String = when (device.bluetoothClass?.majorDeviceClass) {
        BluetoothClass.Device.Major.AUDIO_VIDEO -> PhoneStatus.Accessory.HEADPHONES
        BluetoothClass.Device.Major.WEARABLE -> PhoneStatus.Accessory.WATCH
        else -> PhoneStatus.Accessory.OTHER
    }

    private fun isConnected(device: BluetoothDevice): Boolean =
        runCatching { BluetoothDevice::class.java.getMethod("isConnected").invoke(device) as Boolean }.getOrDefault(false)

    private fun batteryLevel(device: BluetoothDevice): Int? =
        runCatching { BluetoothDevice::class.java.getMethod("getBatteryLevel").invoke(device) as Int }.getOrNull()?.takeIf { it in 0..100 }

    private companion object {
        const val ACTION_BATTERY_LEVEL_CHANGED = "android.bluetooth.device.action.BATTERY_LEVEL_CHANGED"
        const val EXTRA_BATTERY_LEVEL = "android.bluetooth.device.extra.BATTERY_LEVEL"
    }
}
