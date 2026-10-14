package com.julianamarques.galaxybridge.spike.background

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import java.io.File
import java.net.ConnectException
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.Socket
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class HeartbeatService : Service() {
    private val thread = HandlerThread("heartbeat").apply { start() }
    private val handler = Handler(thread.looper)
    private lateinit var file: File
    private var lastTick = 0L
    private var tick = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        file = File(filesDir, "heartbeat.csv")
        if (!file.exists()) {
            file.writeText("hora,tick,intervalo_s,tela,doze,sem_otimizacao_bateria,bateria,carregando,wifi,rede_local\n")
        }
        val channel = NotificationChannel("bridge", "Conexão com o Mac", NotificationManager.IMPORTANCE_LOW)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = Notification.Builder(this, "bridge")
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentTitle("Teste de segundo plano")
            .setContentText("Gravando um sinal por minuto")
            .setOngoing(true)
            .build()
        try {
            startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            append("início", "serviço em primeiro plano iniciado (startId=$startId, flags=$flags)")
        } catch (e: Exception) {
            append("erro", "startForeground falhou: ${e.javaClass.simpleName}: ${e.message}")
            stopSelf()
            return START_NOT_STICKY
        }
        handler.removeCallbacksAndMessages(null)
        handler.post(::beat)
        return START_STICKY
    }

    override fun onDestroy() {
        append("fim", "onDestroy")
        handler.removeCallbacksAndMessages(null)
        thread.quitSafely()
        super.onDestroy()
    }

    private fun beat() {
        val now = SystemClock.elapsedRealtime()
        val interval = if (lastTick == 0L) 0 else (now - lastTick) / 1000
        lastTick = now
        tick += 1

        val power = getSystemService(PowerManager::class.java)
        val battery = getSystemService(BatteryManager::class.java)
        val (wifi, network) = localNetwork()
        val row = listOf(
            timestamp(),
            tick,
            interval,
            if (power.isInteractive) "acesa" else "apagada",
            if (power.isDeviceIdleMode) "sim" else "não",
            if (power.isIgnoringBatteryOptimizations(packageName)) "sim" else "não",
            battery.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY),
            if (battery.isCharging) "sim" else "não",
            wifi,
            network,
        ).joinToString(",")
        file.appendText(row + "\n")
        Log.i(TAG, row)
        handler.postDelayed(::beat, 60_000)
    }

    private fun localNetwork(): Pair<String, String> {
        val connectivity = getSystemService(ConnectivityManager::class.java)
        val active = connectivity.activeNetwork ?: return "sem rede" to "-"
        val capabilities = connectivity.getNetworkCapabilities(active)
        if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) != true) return "não" to "-"
        val gateway = connectivity.getLinkProperties(active)?.routes
            ?.firstOrNull { it.isDefaultRoute && it.gateway is Inet4Address }?.gateway
            ?: return "sim" to "sem gateway"
        val start = SystemClock.elapsedRealtime()
        val result = try {
            Socket().use { it.connect(InetSocketAddress(gateway, 53), 3_000) }
            "ok"
        } catch (e: ConnectException) {
            "ok (recusada)"
        } catch (e: Exception) {
            "falhou (${e.javaClass.simpleName})"
        }
        return "sim" to "$result ${SystemClock.elapsedRealtime() - start}ms"
    }

    private fun append(event: String, detail: String) {
        val row = "${timestamp()},$event,,,,,,,,${detail.replace(',', ';')}"
        file.appendText(row + "\n")
        Log.i(TAG, row)
    }

    private fun timestamp() = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.ROOT).format(Date())

    companion object {
        const val TAG = "GBSpike"
    }
}
