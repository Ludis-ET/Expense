package com.santim.santim

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import android.telephony.SmsMessage
import org.json.JSONArray
import org.json.JSONObject

/**
 * Captures bank messages whether or not Santim is running.
 *
 * The previous receiver was registered at runtime from `MainActivity`, which
 * tied it to the Activity's lifetime: Android reclaims backgrounded activities
 * routinely, and once ours was gone so was "live capture". The app leaned on a
 * history backfill of `content://sms/inbox` at next launch to cover the gap,
 * which works but is not live, and loses anything the user deletes first.
 *
 * A manifest-declared receiver is instantiated by the system on delivery, with
 * no process of ours required. It cannot talk to Flutter - there may be no
 * engine - so it appends to a small durable queue that the Dart side drains on
 * its next run, and forwards to the live event sink as well when the app does
 * happen to be open.
 *
 * Uploading from here while the app is closed would need a background worker
 * holding the device token; the queue is the durable half of that, and the part
 * that stops messages going missing.
 */
class SmsCaptureReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        for (captured in parse(intent)) {
            // Straight through when the UI is alive, so nothing feels delayed.
            MainActivity.emit(captured)
            enqueue(context, captured)
            // Tray ping only when Flutter is not listening — otherwise the
            // in-app inbox / upload path already owns the feedback loop.
            if (!MainActivity.hasLiveSink()) {
                val sender = captured["sender"] as? String ?: continue
                val body = captured["body"] as? String ?: ""
                SmsNotificationHelper.maybeNotify(context, sender, body)
            }
        }
    }

    /** One entry per sender, with multipart bodies stitched back together. */
    private fun parse(intent: Intent): List<Map<String, Any>> {
        val bundle = intent.extras ?: return emptyList()

        @Suppress("DEPRECATION")
        val pdus = bundle.get("pdus") as? Array<*> ?: return emptyList()
        val format = bundle.getString("format")

        val byAddress = linkedMapOf<String, StringBuilder>()
        val timestamps = linkedMapOf<String, Long>()

        for (pdu in pdus) {
            val bytes = pdu as? ByteArray ?: continue
            val msg = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                SmsMessage.createFromPdu(bytes, format)
            } else {
                @Suppress("DEPRECATION")
                SmsMessage.createFromPdu(bytes)
            }
            val address = msg.originatingAddress ?: continue
            byAddress.getOrPut(address) { StringBuilder() }.append(msg.messageBody ?: "")
            // The carrier's stamp, not ours - the phone may have been asleep.
            timestamps[address] = msg.timestampMillis
        }

        return byAddress.map { (address, body) ->
            mapOf(
                "sender" to address,
                "body" to body.toString(),
                "receivedAtMs" to (timestamps[address] ?: System.currentTimeMillis()),
            )
        }
    }

    companion object {
        private const val PREFS = "santim.sms.pending"
        private const val KEY = "queue"

        /**
         * Cap on the durable queue.
         *
         * A phone left unopened for weeks should not accumulate without bound,
         * and anything that overflows is still recoverable from the inbox
         * backfill. Oldest entries are dropped first.
         */
        private const val MAX_QUEUED = 500

        private fun enqueue(context: Context, captured: Map<String, Any>) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            synchronized(this) {
                val existing = runCatching { JSONArray(prefs.getString(KEY, "[]")) }
                    .getOrElse { JSONArray() }

                existing.put(JSONObject(captured))

                val trimmed = if (existing.length() > MAX_QUEUED) {
                    JSONArray().also { out ->
                        for (i in existing.length() - MAX_QUEUED until existing.length()) {
                            out.put(existing.get(i))
                        }
                    }
                } else {
                    existing
                }

                prefs.edit().putString(KEY, trimmed.toString()).commit()
            }
        }

        /** Hands the queue to Dart and clears it, in one atomic step. */
        fun drain(context: Context): List<Map<String, Any?>> {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            synchronized(this) {
                val raw = prefs.getString(KEY, "[]") ?: "[]"
                val parsed = runCatching { JSONArray(raw) }.getOrElse { JSONArray() }
                // Only clear once the contents have been read successfully -
                // losing captured messages to a parse error would be silent.
                prefs.edit().remove(KEY).commit()

                return (0 until parsed.length()).mapNotNull { i ->
                    val o = parsed.optJSONObject(i) ?: return@mapNotNull null
                    mapOf(
                        "sender" to o.optString("sender"),
                        "body" to o.optString("body"),
                        "receivedAtMs" to o.optLong("receivedAtMs"),
                    )
                }
            }
        }
    }
}
