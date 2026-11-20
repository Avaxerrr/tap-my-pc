package dev.tapmypc.tapmypc_mobile

import android.app.Activity
import android.app.AlertDialog
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.text.format.DateFormat
import android.view.View
import android.widget.RemoteViews
import java.util.Date

private const val WIDGET_ACTION = "dev.tapmypc.WIDGET_ACTION"
private const val WIDGET_OPERATION = "operation"
private const val WIDGET_ID = AppWidgetManager.EXTRA_APPWIDGET_ID

private fun Context.widgetPreferences() =
    getSharedPreferences("tapmypc_widgets", Context.MODE_PRIVATE)

private fun Context.ownsWidget(id: Int): Boolean =
    AppWidgetManager.getInstance(this).getAppWidgetInfo(id)?.provider ==
        ComponentName(this, PcWidgetProvider::class.java)

class PcWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) render(context, id)
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        val edit = context.widgetPreferences().edit()
        for (id in ids) {
            edit.remove("pc:$id").remove("name:$id").remove("message:$id").remove("time:$id")
        }
        edit.apply()
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != WIDGET_ACTION) {
            super.onReceive(context, intent)
            return
        }
        val id = intent.getIntExtra(WIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        val action = intent.getStringExtra(WIDGET_OPERATION)
        val prefs = context.widgetPreferences()
        val pc = prefs.getString("pc:$id", null)
        if (!context.ownsWidget(id) || pc == null || (action != "wake" && action != "refresh")) return
        val work = goAsync()
        val working = if (action == "wake") "Sending wake packet…" else "Checking PC…"
        try {
            render(context, id, working)
            HomeActionRunner.run(context, action, pc) { result ->
                try {
                    if (context.ownsWidget(id) && prefs.getString("pc:$id", null) == pc) {
                        val edit = prefs.edit()
                        (result["name"] as? String)?.let { edit.putString("name:$id", it) }
                        edit.putString("message:$id", result["message"] as? String ?: "Action unavailable")
                            .putLong("time:$id", System.currentTimeMillis()).apply()
                        render(context, id)
                    }
                } finally {
                    work.finish()
                }
            }
        } catch (_: Exception) {
            work.finish()
        }
    }

    companion object {
        fun render(context: Context, id: Int, working: String? = null) {
            val prefs = context.widgetPreferences()
            val pc = prefs.getString("pc:$id", null)
            val name = prefs.getString("name:$id", null)
            val message = prefs.getString("message:$id", null)
            val time = prefs.getLong("time:$id", 0)
            val status = when {
                working != null -> working
                pc == null -> "Tap to choose a paired PC"
                time > 0 && message != null ->
                    "$message · ${DateFormat.getTimeFormat(context).format(Date(time))}"
                else -> "Tap Refresh to check status"
            }
            val views = RemoteViews(context.packageName, R.layout.pc_widget)
            views.setTextViewText(R.id.widget_name, name ?: "TapMyPC")
            views.setTextViewText(R.id.widget_status, status)
            views.setViewVisibility(R.id.widget_actions, if (pc == null) View.GONE else View.VISIBLE)
            val config = Intent(context, PcWidgetConfigActivity::class.java)
                .putExtra(WIDGET_ID, id)
            views.setOnClickPendingIntent(R.id.widget_header, activity(context, id, "config", config))
            if (pc != null) {
                views.setOnClickPendingIntent(R.id.widget_desktop,
                    activity(context, id, "desktop", HomeScreenActions.intent(context, "desktop", pc)))
                for ((view, operation) in listOf(R.id.widget_wake to "wake", R.id.widget_refresh to "refresh")) {
                    val action = Intent(WIDGET_ACTION, uri(id, operation), context, PcWidgetProvider::class.java)
                        .putExtra(WIDGET_ID, id).putExtra(WIDGET_OPERATION, operation)
                    views.setOnClickPendingIntent(view, PendingIntent.getBroadcast(
                        context, id, action, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                    ))
                }
            }
            AppWidgetManager.getInstance(context).updateAppWidget(id, views)
        }

        private fun uri(id: Int, action: String) = Uri.parse("tapmypc-widget://$id/$action")

        private fun activity(context: Context, id: Int, action: String, intent: Intent) =
            PendingIntent.getActivity(context, id, intent.setData(uri(id, action)),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }
}

class PcWidgetConfigActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val id = intent.getIntExtra(WIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        val result = Intent().putExtra(WIDGET_ID, id)
        setResult(RESULT_CANCELED, result)
        if (!ownsWidget(id)) {
            finish()
            return
        }
        val loading = AlertDialog.Builder(this).setTitle("TapMyPC widget")
            .setMessage("Loading paired PCs…").setOnCancelListener { finish() }.show()
        HomeActionRunner.run(this, "profiles") { data ->
            if (isFinishing || isDestroyed) return@run
            loading.dismiss()
            val pcs = (data["profiles"] as? List<*>).orEmpty().mapNotNull { item ->
                val fields = item as? Map<*, *> ?: return@mapNotNull null
                val pc = fields["id"] as? String ?: return@mapNotNull null
                val name = fields["name"] as? String ?: return@mapNotNull null
                if (homePcIdPattern.matches(pc)) pc to name else null
            }
            val dialog = AlertDialog.Builder(this).setTitle("Choose a PC")
                .setNegativeButton(android.R.string.cancel) { _, _ -> finish() }
                .setOnCancelListener { finish() }
            if (pcs.isEmpty()) {
                dialog.setMessage(data["message"] as? String ?: "Pair a PC in TapMyPC before adding a widget.")
            } else {
                dialog.setItems(pcs.map { it.second }.toTypedArray()) { _, position ->
                    if (ownsWidget(id)) {
                        val (pc, name) = pcs[position]
                        widgetPreferences().edit().putString("pc:$id", pc).putString("name:$id", name)
                            .remove("message:$id").remove("time:$id").apply()
                        PcWidgetProvider.render(this, id)
                        setResult(RESULT_OK, result)
                    }
                    finish()
                }
            }
            dialog.show()
        }
    }
}
