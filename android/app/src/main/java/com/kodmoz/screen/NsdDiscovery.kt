package com.kodmoz.screen

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper

data class Peer(
    val name: String,
    val host: String,
    val port: Int,
)

/** Bonjour/DNS-SD ile aynı ağdaki Kodmoz Screen sunucularını bulur. */
class NsdDiscovery(context: Context) {
    companion object {
        const val SERVICE_TYPE = "_kodmoz-screen._tcp"
    }

    var onPeers: ((List<Peer>) -> Unit)? = null
    var onError: ((String) -> Unit)? = null

    private val appContext = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val peers = linkedMapOf<String, Peer>()
    private val resolving = mutableSetOf<String>()
    private var manager: NsdManager? = null
    private var listener: NsdManager.DiscoveryListener? = null
    private var running = false

    fun start() {
        if (running) return
        val nsd = appContext.getSystemService(Context.NSD_SERVICE) as? NsdManager ?: run {
            onError?.invoke("DNS-SD servisi bulunamadı.")
            return
        }
        manager = nsd
        running = true
        peers.clear()
        publish()

        val discovery = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {
                publish()
            }

            override fun onServiceFound(service: NsdServiceInfo) {
                if (!service.serviceType.startsWith(SERVICE_TYPE)) return
                resolve(service)
            }

            override fun onServiceLost(service: NsdServiceInfo) {
                synchronized(peers) { peers.remove(service.serviceName) }
                publish()
            }

            override fun onDiscoveryStopped(serviceType: String) {
                running = false
            }

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                running = false
                main.post {
                    onError?.invoke("Ağ taraması başlatılamadı (kod $errorCode). Adresi elle girin.")
                }
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                // Yok sayılabilir.
            }
        }

        listener = discovery
        try {
            nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discovery)
        } catch (error: Exception) {
            running = false
            onError?.invoke("Ağ taraması başlatılamadı: ${error.message}")
        }
    }

    @Suppress("DEPRECATION")
    private fun resolve(service: NsdServiceInfo) {
        if (!resolving.add(service.serviceName)) return
        val nsd = manager ?: return
        try {
            nsd.resolveService(service, object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                    resolving.remove(service.serviceName)
                }

                override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                    resolving.remove(service.serviceName)
                    val address = serviceInfo.host ?: return
                    val host = address.hostAddress ?: return
                    // IPv4 tercih edilir; IPv6 bağlantıları kapsam kimliği
                    // olmadan çoğu ağda çalışmaz.
                    if (host.contains(':')) return
                    synchronized(peers) {
                        peers[serviceInfo.serviceName] = Peer(
                            name = serviceInfo.serviceName,
                            host = host,
                            port = serviceInfo.port,
                        )
                    }
                    publish()
                }
            })
        } catch (error: Exception) {
            resolving.remove(service.serviceName)
        }
    }

    fun stop() {
        val nsd = manager
        val discovery = listener
        running = false
        listener = null
        manager = null
        resolving.clear()
        if (nsd != null && discovery != null) {
            try {
                nsd.stopServiceDiscovery(discovery)
            } catch (_: Exception) {
            }
        }
        synchronized(peers) { peers.clear() }
        publish()
    }

    private fun publish() {
        val snapshot = synchronized(peers) { peers.values.toList() }
        main.post { onPeers?.invoke(snapshot) }
    }
}
