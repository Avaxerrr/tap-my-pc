package dev.tapmypc.tapmypc_mobile

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress

internal fun registerWakeOnLan(context: Context, engine: FlutterEngine) {
    val messenger = engine.dartExecutor.binaryMessenger
    MethodChannel(
        messenger,
        "dev.tapmypc/wake_on_lan",
        StandardMethodCodec.INSTANCE,
        messenger.makeBackgroundTaskQueue()
    ).setMethodCallHandler { call, result ->
        if (call.method != "send") {
            result.notImplemented()
            return@setMethodCallHandler
        }
        val octets = call.argument<String>("destination")
            ?.split('.')?.map { it.toIntOrNull()?.takeIf { n -> n in 0..255 } }
        val port = call.argument<Int>("port")
        val packet = call.argument<ByteArray>("packet")
        if (octets?.size != 4 || octets.any { it == null } ||
            port == null || port !in 1..65535 || packet?.size != 102
        ) {
            result.error("wake_settings", "Check the saved Wake-on-LAN settings.", null)
            return@setMethodCallHandler
        }
        val destination = InetAddress.getByAddress(octets.filterNotNull().map { it.toByte() }.toByteArray())
        val limitedBroadcast = octets.all { it == 255 }
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        try {
            // A one-shot snapshot is sufficient for an explicit Wake PC tap.
            @Suppress("DEPRECATION")
            val networks = listOfNotNull(manager.activeNetwork) + manager.allNetworks
            val wifi = networks.firstOrNull { network ->
                val capabilities = manager.getNetworkCapabilities(network)
                if (capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) != true ||
                    !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                ) {
                    return@firstOrNull false
                }
                val link = manager.getLinkProperties(network) ?: return@firstOrNull false
                if (limitedBroadcast) {
                    link.linkAddresses.any { it.address is Inet4Address }
                } else {
                    link.routes.any {
                        (it.gateway == null || it.gateway?.isAnyLocalAddress == true) &&
                            !it.isDefaultRoute && it.matches(destination)
                    }
                }
            }
            if (wifi == null) {
                result.error("wake_network", "Join the PC’s Wi-Fi network and check the saved destination.", null)
                return@setMethodCallHandler
            }
            DatagramSocket(null).use { socket ->
                wifi.bindSocket(socket)
                socket.broadcast = true
                socket.send(DatagramPacket(packet, packet.size, destination, port))
            }
            result.success(null)
        } catch (_: SecurityException) {
            result.error("wake_permission", "Allow local network access to send the wake packet.", null)
        } catch (_: IOException) {
            result.error("wake_send", "Could not send the wake packet. Check Wi-Fi and try again.", null)
        }
    }
}
