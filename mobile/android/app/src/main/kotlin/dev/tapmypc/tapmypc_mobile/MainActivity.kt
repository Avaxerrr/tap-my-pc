package dev.tapmypc.tapmypc_mobile

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.util.ArrayDeque

class MainActivity : FlutterActivity() {
    private var bluetoothBridge: BluetoothBridge? = null
    private var sink: EventChannel.EventSink? = null
    private var listener: NsdManager.DiscoveryListener? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var generation = 0
    private var resolving = false
    private val queue = ArrayDeque<NsdServiceInfo>()
    private val resolved = mutableMapOf<String, Map<String, String>>()
    private val manager get() = getSystemService(Context.NSD_SERVICE) as NsdManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bluetoothBridge = BluetoothBridge(this, MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.tapmypc/bluetooth"))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.tapmypc/app")
            .setMethodCallHandler { call, result ->
                if (call.method == "version") {
                    @Suppress("DEPRECATION")
                    val info = packageManager.getPackageInfo(packageName, 0)
                    @Suppress("DEPRECATION")
                    val number = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()
                    result.success(mapOf("version" to info.versionName, "build" to number.toString()))
                } else result.notImplemented()
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.tapmypc/discovery")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    sink = events
                    startDiscovery()
                }
                override fun onCancel(arguments: Any?) { stopDiscovery(); sink = null }
            })
    }

    private fun startDiscovery() {
        stopDiscovery()
        val current = generation
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("TapMyPC discovery").apply {
                setReferenceCounted(false)
                acquire()
            }
            val callbacks = object : NsdManager.DiscoveryListener {
                override fun onDiscoveryStarted(type: String) {
                    runOnUiThread { if (generation == current) sink?.success(mapOf("kind" to "started")) }
                }
                override fun onServiceFound(info: NsdServiceInfo) {
                    runOnUiThread {
                        if (generation == current && info.serviceType.startsWith("_tapmypc._tcp") && queue.size < 20) {
                            queue.add(info)
                            resolveNext(current)
                        }
                    }
                }
                override fun onServiceLost(info: NsdServiceInfo) {
                    runOnUiThread {
                        if (generation == current) resolved.remove(info.serviceName)?.let {
                            sink?.success(it + mapOf("kind" to "lost"))
                        }
                    }
                }
                override fun onDiscoveryStopped(type: String) {}
                override fun onStartDiscoveryFailed(type: String, error: Int) {
                    runOnUiThread {
                        if (generation == current) {
                            sink?.success(mapOf("kind" to "error", "message" to "Discovery unavailable. Saved addresses are still tried."))
                            stopDiscovery()
                        }
                    }
                }
                override fun onStopDiscoveryFailed(type: String, error: Int) {}
            }
            listener = callbacks
            manager.discoverServices("_tapmypc._tcp.", NsdManager.PROTOCOL_DNS_SD, callbacks)
        } catch (error: Exception) {
            sink?.success(mapOf("kind" to "error", "message" to "Allow local network access to discover PCs. Saved addresses are still tried."))
            stopDiscovery()
        }
    }

    @Suppress("DEPRECATION")
    private fun resolveNext(current: Int) {
        if (generation != current || resolving || queue.isEmpty()) return
        resolving = true
        val info = queue.removeFirst()
        try {
            manager.resolveService(info, object : NsdManager.ResolveListener {
                override fun onResolveFailed(service: NsdServiceInfo, error: Int) {
                    runOnUiThread { if (generation == current) { resolving = false; resolveNext(current) } }
                }
                override fun onServiceResolved(service: NsdServiceInfo) {
                    runOnUiThread {
                        if (generation != current) return@runOnUiThread
                        val host = service.host
                        val fp = service.attributes["fp"]?.toString(Charsets.UTF_8)?.lowercase()
                        val version = service.attributes["v"]?.toString(Charsets.UTF_8)
                        if (version == "1" && fp != null && fp.matches(Regex("[a-f0-9]{64}")) &&
                            host is Inet4Address && (host.isSiteLocalAddress || host.isLoopbackAddress) &&
                            service.port in 1024..65535) {
                            val data = mapOf("kind" to "found", "fingerprint" to fp,
                                "keyFingerprint" to service.attributes["pk"]?.toString(Charsets.UTF_8)?.lowercase().orEmpty(),
                                "address" to "https://${host.hostAddress}:${service.port}", "service" to service.serviceName)
                            resolved[service.serviceName] = data
                            sink?.success(data)
                        }
                        resolving = false
                        resolveNext(current)
                    }
                }
            })
        } catch (error: Exception) {
            resolving = false
            resolveNext(current)
        }
    }
    private fun stopDiscovery() {
        generation++
        listener?.let { try { manager.stopServiceDiscovery(it) } catch (_: Exception) {} }
        listener = null
        queue.clear(); resolved.clear(); resolving = false
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (bluetoothBridge?.permissionResponse(requestCode, grantResults) != true) super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
    override fun onDestroy() { bluetoothBridge?.close(); stopDiscovery(); sink = null; super.onDestroy() }
}
