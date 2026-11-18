package dev.tapmypc.tapmypc_mobile

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/** Byte tunnel only: Dart verifies the PC's pinned TLS identity before HTTP can send credentials. */
class BluetoothBridge(private val activity: Activity, channel: MethodChannel) {
    companion object {
        const val SERVICE = "8cf69287-4d5e-47f1-97c8-0a4ec3b5d290"
        const val PERMISSION_REQUEST = 7345
    }
    private val handler = Handler(Looper.getMainLooper())
    private val workers = Executors.newCachedThreadPool()
    private val bridges = ConcurrentHashMap<Int, Tunnel>()
    private val nextId = AtomicInteger()
    private var permissionResult: MethodChannel.Result? = null
    private val adapter get() = (activity.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
    private fun permitted() = Build.VERSION.SDK_INT < 31 ||
        activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "requestAccess" -> {
                        if (permitted()) result.success(true)
                        else if (permissionResult != null) result.error("busy", "Bluetooth permission is already being requested.", null)
                        else {
                            permissionResult = result
                            activity.requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), PERMISSION_REQUEST)
                        }
                    }
                    "settings" -> { activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS)); result.success(null) }
                    "open" -> {
                        if (!permitted()) throw SecurityException("Allow Nearby devices in Connection settings to use Bluetooth.")
                        val address = call.argument<String>("address") ?: ""
                        if (!BluetoothAdapter.checkBluetoothAddress(address)) throw IllegalArgumentException("Pair over Wi-Fi once to save this PC's Bluetooth address.")
                        val radio = adapter ?: throw IllegalStateException("This phone has no Bluetooth adapter.")
                        if (!radio.isEnabled) throw IllegalStateException("Turn on Bluetooth on your phone.")
                        val id = nextId.incrementAndGet()
                        val tunnel = Tunnel(radio, address)
                        bridges[id] = tunnel
                        workers.execute { tunnel.accept() }
                        result.success(mapOf("id" to id, "port" to tunnel.server.localPort))
                    }
                    "error" -> { result.success(call.argument<Int>("id")?.let { bridges[it]?.lastError }) }
                    "close" -> {
                        call.argument<Int>("id")?.let { bridges.remove(it)?.close() }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("bluetooth_unavailable", error.message ?: "Bluetooth is unavailable.", null)
            }
        }
    }

    fun permissionResponse(requestCode: Int, grants: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        permissionResult?.success(grants.isNotEmpty() && grants[0] == PackageManager.PERMISSION_GRANTED)
        permissionResult = null
        return true
    }

    fun close() {
        permissionResult?.success(false); permissionResult = null
        bridges.values.forEach { it.close() }; bridges.clear()
        workers.shutdownNow()
    }

    @Suppress("MissingPermission")
    private inner class Tunnel(private val radio: BluetoothAdapter, private val address: String) {
        val server = ServerSocket(0, 4, InetAddress.getByName("127.0.0.1"))
        @Volatile var lastError: String? = null
        private val closed = AtomicBoolean(false)
        private val peers = ConcurrentHashMap<Socket, BluetoothSocket>()

        fun accept() {
            try {
                while (!closed.get()) {
                    val local = server.accept()
                    if (closed.get() || peers.size >= 4) { local.close(); continue }
                    val remote = radio.getRemoteDevice(address).createRfcommSocketToServiceRecord(UUID.fromString(SERVICE))
                    peers[local] = remote
                    workers.execute { forward(local, remote) }
                }
            } catch (_: Exception) { close() }
        }

        private fun forward(local: Socket, remote: BluetoothSocket) {
            val timeout = Runnable { try { remote.close(); local.close() } catch (_: Exception) {} }
            handler.postDelayed(timeout, 25000)
            try {
                remote.connect()
                lastError = null
                handler.removeCallbacks(timeout)
                if (closed.get()) return
                local.tcpNoDelay = true
                workers.execute {
                    try { remote.inputStream.copyTo(local.getOutputStream(), 16384) }
                    catch (_: Exception) {}
                    finally { closePeer(local, remote) }
                }
                local.getInputStream().copyTo(remote.outputStream, 16384)
            } catch (error: Exception) {
                if (!closed.get() && peers.containsKey(local)) {
                    lastError = "Could not connect to this PC. Check Bluetooth power, pairing, and range, then retry."
                    android.util.Log.w("TapMyPCBluetooth", "RFCOMM connection failed", error)
                }
            } finally {
                handler.removeCallbacks(timeout)
                closePeer(local, remote)
            }
        }

        private fun closePeer(local: Socket, remote: BluetoothSocket) {
            peers.remove(local)
            try { local.close() } catch (_: Exception) {}
            try { remote.close() } catch (_: Exception) {}
        }

        fun close() {
            if (!closed.compareAndSet(false, true)) return
            try { server.close() } catch (_: Exception) {}
            peers.entries.forEach { closePeer(it.key, it.value) }
        }
    }
}
