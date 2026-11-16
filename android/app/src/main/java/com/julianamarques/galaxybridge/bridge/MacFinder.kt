package com.julianamarques.galaxybridge.bridge

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import com.julianamarques.galaxybridge.Diagnostics
import java.net.Inet4Address
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

class MacFinder(context: Context) {
    data class Found(val name: String, val host: String, val port: Int, val id: String?)

    private val context = context.applicationContext
    private val nsd = context.getSystemService(NsdManager::class.java)

    fun find(timeoutMs: Long, matches: (Found) -> Boolean): Found? {
        val wifi = context.getSystemService(WifiManager::class.java)
        val lock = wifi.createMulticastLock("galaxybridge-discovery").apply {
            setReferenceCounted(false)
            acquire()
        }
        val services = LinkedBlockingQueue<NsdServiceInfo>()
        val listener = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(info: NsdServiceInfo) {
                Diagnostics.record(context, "Busca: achou ${info.serviceName}")
                services.add(info)
            }
            override fun onServiceLost(info: NsdServiceInfo) {}
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Diagnostics.record(context, "Busca não iniciou: $errorCode")
            }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
        }
        try {
            nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
            val deadline = System.currentTimeMillis() + timeoutMs
            while (true) {
                val remaining = deadline - System.currentTimeMillis()
                if (remaining <= 0) break
                val info = services.poll(remaining, TimeUnit.MILLISECONDS) ?: break
                val found = resolve(info) ?: continue
                if (matches(found)) return found
            }
        } catch (e: Exception) {
            Diagnostics.record(context, "Busca interrompida: ${e.message}")
        } finally {
            runCatching { nsd.stopServiceDiscovery(listener) }
            lock.release()
        }
        return null
    }

    @Suppress("DEPRECATION")
    private fun resolve(info: NsdServiceInfo): Found? {
        val latch = CountDownLatch(1)
        var resolved: NsdServiceInfo? = null
        nsd.resolveService(info, object : NsdManager.ResolveListener {
            override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                resolved = serviceInfo
                latch.countDown()
            }
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                Diagnostics.record(context, "Busca: não resolveu ${serviceInfo.serviceName} ($errorCode)")
                latch.countDown()
            }
        })
        if (!latch.await(5, TimeUnit.SECONDS)) return null.also { Diagnostics.record(context, "Busca: resolução demorou demais") }
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
    }
}
