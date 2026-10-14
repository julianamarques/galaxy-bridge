package com.julianamarques.galaxybridge.bridge

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Log
import java.net.Inet4Address
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/** Procura Macs com o Galaxy Bridge na rede local pelo Bonjour (`_galaxybridge._tcp`). */
class MacFinder(context: Context) {
    data class Found(val name: String, val host: String, val port: Int, val id: String?)

    private val context = context.applicationContext
    private val nsd = context.getSystemService(NsdManager::class.java)

    /** Procura por até [timeoutMs] e devolve o primeiro Mac que satisfaz [matches], ou `null`. Bloqueia. */
    fun find(timeoutMs: Long, matches: (Found) -> Boolean): Found? =
        search(timeoutMs) { found -> matches(found) }.firstOrNull()

    /** Todos os Macs encontrados em [timeoutMs]. Bloqueia. */
    fun findAll(timeoutMs: Long): List<Found> = search(timeoutMs) { false }

    private fun search(timeoutMs: Long, stopAt: (Found) -> Boolean): List<Found> {
        val wifi = context.getSystemService(WifiManager::class.java)
        // O Wi-Fi descarta multicast para economizar bateria; a trava fica só enquanto procura.
        val lock = wifi.createMulticastLock("galaxybridge-discovery").apply {
            setReferenceCounted(false)
            acquire()
        }
        val services = LinkedBlockingQueue<NsdServiceInfo>()
        val listener = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(info: NsdServiceInfo) { services.add(info) }
            override fun onServiceLost(info: NsdServiceInfo) {}
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.w(TAG, "Descoberta falhou: $errorCode")
            }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
        }
        val results = mutableListOf<Found>()
        try {
            nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
            val deadline = System.currentTimeMillis() + timeoutMs
            while (true) {
                val remaining = deadline - System.currentTimeMillis()
                if (remaining <= 0) break
                val info = services.poll(remaining, TimeUnit.MILLISECONDS) ?: break
                val found = resolve(info) ?: continue
                if (results.none { it.host == found.host && it.port == found.port }) results += found
                if (stopAt(found)) return listOf(found)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Descoberta interrompida: ${e.message}")
        } finally {
            runCatching { nsd.stopServiceDiscovery(listener) }
            lock.release()
        }
        return results
    }

    /** O `NsdManager` resolve um serviço por vez; esta função espera cada um terminar. */
    @Suppress("DEPRECATION")
    private fun resolve(info: NsdServiceInfo): Found? {
        val latch = CountDownLatch(1)
        var resolved: NsdServiceInfo? = null
        nsd.resolveService(info, object : NsdManager.ResolveListener {
            override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                resolved = serviceInfo
                latch.countDown()
            }
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) { latch.countDown() }
        })
        if (!latch.await(5, TimeUnit.SECONDS)) return null
        val service = resolved ?: return null
        val address = if (Build.VERSION.SDK_INT >= 34) {
            service.hostAddresses.firstOrNull { it is Inet4Address } ?: service.hostAddresses.firstOrNull()
        } else {
            service.host
        } ?: return null
        val id = service.attributes["id"]?.toString(Charsets.UTF_8)
        return Found(service.serviceName, address.hostAddress ?: return null, service.port, id)
    }

    companion object {
        const val SERVICE_TYPE = "_galaxybridge._tcp"
        private const val TAG = "GalaxyBridge"
    }
}
