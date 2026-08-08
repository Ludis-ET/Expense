package com.santim.mobile.ingest

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log

/**
 * Catches bank SMS the moment it arrives.
 *
 * Registered in the manifest rather than at runtime, so it fires with the app
 * closed, swiped away, or the phone locked - `SMS_RECEIVED` is exempt from the
 * Android 8+ implicit-broadcast restrictions, which is exactly why this design
 * works without a foreground service.
 *
 * The hard rule here is speed: Android gives `onReceive` about ten seconds
 * before the process becomes killable, and there is no way to hold it open for
 * a network round trip. So this does the minimum - filter, append, hand off -
 * and lets [UploadWorker] deal with delivery.
 */
class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val prefs = IngestPrefs(context)
        if (!prefs.captureEnabled || !prefs.isConfigured()) return

        val allowed = prefs.allowedSenders
        // An empty allowlist means "nothing has been approved yet", not "allow
        // everything". Setup populates it; until then we forward nothing.
        if (allowed.isEmpty()) return

        val messages = try {
            Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        } catch (t: Throwable) {
            Log.w(TAG, "Could not read SMS from intent", t)
            return
        }
        if (messages.isEmpty()) return

        // Bank alerts routinely run past 160 characters, so they arrive split
        // into parts within a single broadcast. Joining them by sender is what
        // turns three fragments back into one parseable message.
        val bySender = LinkedHashMap<String, StringBuilder>()
        var timestamp = System.currentTimeMillis()

        for (m in messages) {
            val from = m.originatingAddress ?: continue
            bySender.getOrPut(from) { StringBuilder() }.append(m.messageBody ?: "")
            if (m.timestampMillis > 0) timestamp = m.timestampMillis
        }

        val store = IngestStore(context)
        var queued = 0

        for ((sender, builder) in bySender) {
            if (IngestPrefs.normalizeSender(sender) !in allowed) continue

            val body = builder.toString().trim()
            if (body.isEmpty()) continue

            store.enqueue(sender, body, timestamp)
            queued++
        }
        store.close()

        if (queued > 0) UploadWorker.enqueueNow(context)
    }

    companion object {
        private const val TAG = "SantimSmsReceiver"
    }
}
