package com.santim.santim

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Home-screen widget: today's remaining spend plus a one-tap add button.
 *
 * For a daily-use finance app the home screen is the highest-value surface
 * outside the app itself   logging an expense should not require opening
 * Santim, finding the tab and hitting the FAB.
 *
 * The widget renders whatever Flutter last wrote into shared preferences, so it
 * paints instantly and works offline; it never talks to the API itself. Dart
 * refreshes those values after each dashboard load and then asks this provider
 * to redraw (see `lib/core/home_widget.dart`).
 */
class SantimWidgetProvider : AppWidgetProvider() {

    companion object {
        /** Flutter's shared_preferences store, and its key prefix. */
        private const val PREFS = "FlutterSharedPreferences"
        private const val PREFIX = "flutter."

        const val KEY_REMAINING = "${PREFIX}santim.widget.remaining"
        const val KEY_CAPTION = "${PREFIX}santim.widget.caption"
        const val KEY_SPENT = "${PREFIX}santim.widget.spent"

        /** Extra read by MainActivity to jump straight to the add sheet. */
        const val EXTRA_ACTION = "santim.action"
        const val ACTION_ADD = "add"

        fun redraw(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, SantimWidgetProvider::class.java),
            )
            if (ids.isEmpty()) return
            SantimWidgetProvider().onUpdate(context, manager, ids)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        // Before the first dashboard load there is nothing to show, so the
        // widget says so rather than showing a misleading zero.
        val remaining = prefs.getString(KEY_REMAINING, null) ?: " "
        val caption = prefs.getString(KEY_CAPTION, null) ?: "Open Santim to sync"
        val spent = prefs.getString(KEY_SPENT, null) ?: ""

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_santim).apply {
                setTextViewText(R.id.widget_remaining, remaining)
                setTextViewText(R.id.widget_caption, caption)
                setTextViewText(R.id.widget_spent, spent)
                setOnClickPendingIntent(R.id.widget_root, launchIntent(context, null))
                setOnClickPendingIntent(R.id.widget_add, launchIntent(context, ACTION_ADD))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun launchIntent(context: Context, action: String?): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (action != null) putExtra(EXTRA_ACTION, action)
        }
        return PendingIntent.getActivity(
            context,
            // Distinct request codes, otherwise the two taps share one intent
            // and the add button just opens the dashboard.
            if (action == null) 0 else 1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
