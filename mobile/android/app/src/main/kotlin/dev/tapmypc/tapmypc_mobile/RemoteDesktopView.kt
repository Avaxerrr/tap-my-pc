package dev.tapmypc.tapmypc_mobile

import android.content.Context
import android.os.Build
import android.view.View
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.JavaScriptReplyProxy
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewAssetLoader
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

private const val VIEWER_ORIGIN = "https://appassets.androidplatform.net"
private const val VIEWER_URL = "$VIEWER_ORIGIN/assets/remote-desktop/index.html"
private const val VIEWER_BRIDGE = "tapMyPcRemoteDesktop"
private const val MAX_CHUNK = 64 * 1024

internal class RemoteDesktopViewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        RemoteDesktopView(context, MethodChannel(messenger, "dev.tapmypc/remote-desktop/$viewId"))
}

private class RemoteDesktopView(context: Context, private val channel: MethodChannel) : PlatformView {
    private val webView = WebView(context)
    private var reply: JavaScriptReplyProxy? = null
    private val supported = WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER) &&
        WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_ARRAY_BUFFER)

    init {
        val assets = WebViewAssetLoader.Builder()
            .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(context))
            .build()
        webView.setBackgroundColor(android.graphics.Color.BLACK)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            webView.importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        }
        webView.settings.apply {
            javaScriptEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            domStorageEnabled = false
        }
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = true

            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse {
                val uri = request.url
                if (uri.scheme == "https" && uri.host == "appassets.androidplatform.net" &&
                    uri.path?.startsWith("/assets/remote-desktop/") == true) {
                    assets.shouldInterceptRequest(uri)?.let { return it }
                }
                return WebResourceResponse("text/plain", "UTF-8", 403, "Forbidden", emptyMap(), null)
            }
        }
        if (supported) {
            WebViewCompat.addWebMessageListener(webView, VIEWER_BRIDGE, setOf(VIEWER_ORIGIN)) {
                _, message, sourceOrigin, isMainFrame, proxy ->
                if (isMainFrame && sourceOrigin.toString() == VIEWER_ORIGIN) {
                    when (message.type) {
                        WebMessageCompat.TYPE_STRING -> when (val event = message.data) {
                            "ready" -> {
                                reply = proxy
                                channel.invokeMethod("ready", null)
                            }
                            "connected", "disconnected", "passwordRequired", "authenticationFailed" ->
                                channel.invokeMethod(event, null)
                        }
                        WebMessageCompat.TYPE_ARRAY_BUFFER ->
                            message.arrayBuffer?.takeIf { it.isNotEmpty() && it.size <= MAX_CHUNK }?.let {
                                channel.invokeMethod("input", it)
                            }
                    }
                }
            }
        }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    if (supported) {
                        webView.loadUrl(VIEWER_URL)
                        result.success(null)
                    } else result.error("webview", "Update Android System WebView to use Remote Desktop.", null)
                }
                "open", "refresh" -> {
                    reply?.postMessage(call.method)
                    result.success(null)
                }
                "password" -> {
                    val password = call.arguments as? String
                    if (password == null || reply == null) {
                        result.error("viewer", "Remote Desktop viewer is unavailable.", null)
                    } else {
                        reply?.postMessage("password:$password")
                        result.success(null)
                    }
                }
                "screen" -> {
                    val bytes = call.arguments as? ByteArray
                    val page = reply
                    if (page == null || bytes == null || bytes.size > MAX_CHUNK) {
                        result.error("viewer", "Remote Desktop viewer is unavailable.", null)
                    } else {
                        page.postMessage(bytes)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun getView(): WebView = webView

    override fun dispose() {
        channel.setMethodCallHandler(null)
        reply = null
        webView.stopLoading()
        webView.destroy()
    }
}
