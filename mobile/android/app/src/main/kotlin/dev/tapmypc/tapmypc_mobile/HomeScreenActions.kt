package dev.tapmypc.tapmypc_mobile

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import com.it_nomads.fluttersecurestorage.FlutterSecureStoragePlugin
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

internal const val HOME_PC_ID = "pcId"
internal val homePcIdPattern = Regex("[0-9a-f]{64}")

internal object HomeScreenActions {
    private var desktopRequest: String? = null

    fun intent(context: Context, action: String, id: String) =
        Intent(action, null, context, HomeShortcutActivity::class.java).putExtra(HOME_PC_ID, id)

    fun openDesktop(context: Context, id: String) {
        desktopRequest = id
        context.startActivity(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
    }

    fun takeDesktopRequest(): String? = desktopRequest.also { desktopRequest = null }

    fun publish(context: Context, fields: Map<*, *>?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return
        val manager = context.getSystemService(ShortcutManager::class.java) ?: return
        val id = fields?.get("id") as? String
        val name = (fields?.get("name") as? String)?.trim()?.take(30)
        val entries = if (id != null && homePcIdPattern.matches(id) && !name.isNullOrEmpty()) {
            fun shortcut(action: String, label: String, icon: Int) =
                ShortcutInfo.Builder(context, "$action-$id")
                    .setShortLabel("$label · $name")
                    .setIcon(Icon.createWithResource(context, icon))
                    .setIntent(intent(context, action, id))
                    .build()
            buildList {
                if (fields?.get("wake") == true) add(shortcut("wake", "Wake", R.drawable.home_wake))
                add(shortcut("desktop", "Remote Desktop", R.drawable.home_desktop))
            }.take(manager.maxShortcutCountPerActivity)
        } else emptyList()
        val current = manager.dynamicShortcuts.sortedBy { it.rank }
        if (current.map { it.id to it.shortLabel } != entries.map { it.id to it.shortLabel }) {
            manager.dynamicShortcuts = entries
        }
    }
}

class HomeShortcutActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val id = intent.getStringExtra(HOME_PC_ID)
        if (savedInstanceState != null || id == null || !homePcIdPattern.matches(id)) {
            finish()
            return
        }
        when (intent.action) {
            "desktop" -> {
                HomeScreenActions.openDesktop(this, id)
                finish()
            }
            "wake" -> HomeActionRunner.run(this, "wake", id) { result ->
                val message = (result["message"] as? String) ?: "Could not send the wake packet."
                val name = result["name"] as? String
                Toast.makeText(this, if (name == null) message else "$name · $message", Toast.LENGTH_LONG).show()
                finish()
            }
            else -> finish()
        }
    }
}

/** Runs a bounded, one-shot action using the same secure profile store and Dart client as the app. */
internal object HomeActionRunner {
    private val handler = Handler(Looper.getMainLooper())
    private var running = false

    fun run(
        context: Context,
        action: String,
        id: String? = null,
        onResult: (Map<*, *>) -> Unit,
    ) {
        if (running) {
            onResult(mapOf("message" to "Another TapMyPC action is running."))
            return
        }
        running = true
        var activeEngine: FlutterEngine? = null
        var channel: MethodChannel? = null
        var finished = false
        lateinit var timeout: Runnable
        fun finish(result: Map<*, *>) {
            if (finished) return
            finished = true
            handler.removeCallbacks(timeout)
            try {
                onResult(result)
            } finally {
                // Avoid destroying an engine while it is dispatching its result message.
                handler.post {
                    try {
                        channel?.setMethodCallHandler(null)
                        activeEngine?.destroy()
                    } finally {
                        running = false
                    }
                }
            }
        }
        timeout = Runnable { finish(mapOf("message" to "TapMyPC action timed out.")) }
        handler.postDelayed(timeout, 8_000)
        try {
            val app = context.applicationContext
            val engine = FlutterEngine(app, null, false)
            activeEngine = engine
            engine.plugins.add(FlutterSecureStoragePlugin())
            registerWakeOnLan(app, engine)
            channel = MethodChannel(engine.dartExecutor.binaryMessenger, "dev.tapmypc/home_background")
            channel.setMethodCallHandler { call, result ->
                if (call.method == "complete") {
                    result.success(null)
                    finish(call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                } else result.notImplemented()
            }
            val bundle = FlutterInjector.instance().flutterLoader().findAppBundlePath()
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(bundle, "homeActionMain"),
                listOfNotNull(action, id),
            )
        } catch (_: Exception) {
            finish(mapOf("message" to "Could not start TapMyPC. Open the app and try again."))
        }
    }
}
