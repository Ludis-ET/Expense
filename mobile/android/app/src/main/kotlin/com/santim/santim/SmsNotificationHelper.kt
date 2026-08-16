package com.santim.santim

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * System tray ping when a bank SMS lands while Santim is not in the foreground.
 *
 * The Dart side already surfaces API alerts via flutter_local_notifications;
 * this path covers the case where no Flutter engine is alive — the same
 * situation [SmsCaptureReceiver] was built for.
 */
object SmsNotificationHelper {
    private const val CHANNEL_ID = "santim_sms"
    private const val CHANNEL_NAME = "Bank messages"

    /** Flutter shared_preferences store + key prefix (see SantimWidgetProvider). */
    private const val PREFS = "FlutterSharedPreferences"
    private const val PREFIX = "flutter."
    private const val KEY_ALLOWLIST = "${PREFIX}santim.sms.allowlist"
    private const val KEY_CAPTURE = "${PREFIX}santim.smsCaptureEnabled"
    private const val KEY_DEVICE_ID = "${PREFIX}santim.deviceId"

    fun maybeNotify(context: Context, sender: String, body: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val paired = !prefs.getString(KEY_DEVICE_ID, null).isNullOrBlank()
        val captureOn = prefs.getBoolean(KEY_CAPTURE, true)
        if (!paired || !captureOn) return

        val allowlist = prefs.getStringSet(KEY_ALLOWLIST, emptySet()) ?: emptySet()
        if (allowlist.isEmpty()) return
        val normalized = normalize(sender)
        if (allowlist.none { normalize(it) == normalized }) return

        ensureChannel(context)

        val open = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(SantimWidgetProvider.EXTRA_ACTION, ACTION_SMS_REVIEW)
        }
        val pending = PendingIntent.getActivity(
            context,
            42,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val preview = body.trim().replace("\n", " ").let {
            if (it.length <= 140) it else it.substring(0, 137) + "…"
        }

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Bank message received")
            .setContentText(preview.ifEmpty { sender })
            .setStyle(NotificationCompat.BigTextStyle().bigText(preview))
            .setContentIntent(pending)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .build()

        // Unique-ish per message so several SMS do not collapse into one.
        val id = (sender.hashCode() xor body.hashCode() xor
            System.currentTimeMillis().toInt()) and 0x7fffffff

        runCatching {
            NotificationManagerCompat.from(context).notify(id, notification)
        }
    }

    const val ACTION_SMS_REVIEW = "sms_review"

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "When a bank SMS needs review in Santim"
            },
        )
    }

    private fun normalize(sender: String): String =
        sender.lowercase().replace(Regex("[^a-z0-9]"), "")
}
