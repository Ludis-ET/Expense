package com.santim.mobile.ingest

import android.content.Context
import android.provider.Telephony

/** A sender seen in the phone's inbox, with enough context to recognise it. */
data class SenderSummary(
    val sender: String,
    val messageCount: Int,
    val lastMessageAt: Long,
    val samples: List<String>,
)

/**
 * Reads the existing SMS inbox.
 *
 * Two jobs, both setup-time only:
 *
 *  - listing the senders actually present on this phone, so the user picks
 *    their banks from a real list instead of guessing at sender ids;
 *  - backfilling history, so pairing imports months of past transactions
 *    rather than starting from an empty ledger.
 *
 * Requires READ_SMS. The live capture path does not use this at all.
 */
object SmsHistoryReader {

    private val PROJECTION = arrayOf(
        Telephony.Sms.ADDRESS,
        Telephony.Sms.BODY,
        Telephony.Sms.DATE,
    )

    /**
     * Distinct senders, most active first.
     *
     * Aggregated in memory over a bounded scan rather than with a GROUP BY:
     * the SMS provider is an OEM-patched surface and grouped queries behave
     * inconsistently across vendors, while a plain ordered scan does not.
     */
    fun recentSenders(context: Context, scanLimit: Int = 2000): List<SenderSummary> {
        val counts = LinkedHashMap<String, MutableList<Pair<String, Long>>>()

        context.contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            PROJECTION,
            null,
            null,
            "${Telephony.Sms.DATE} DESC LIMIT $scanLimit",
        )?.use { c ->
            val iAddress = c.getColumnIndex(Telephony.Sms.ADDRESS)
            val iBody = c.getColumnIndex(Telephony.Sms.BODY)
            val iDate = c.getColumnIndex(Telephony.Sms.DATE)

            while (c.moveToNext()) {
                val address = c.getString(iAddress) ?: continue
                val body = c.getString(iBody) ?: ""
                val date = if (iDate >= 0) c.getLong(iDate) else 0L
                counts.getOrPut(address) { mutableListOf() }.add(body to date)
            }
        }

        return counts.map { (sender, rows) ->
            SenderSummary(
                sender = sender,
                messageCount = rows.size,
                lastMessageAt = rows.maxOfOrNull { it.second } ?: 0L,
                // Two samples is enough for the user to recognise a bank, and
                // keeps the payload crossing the method channel small.
                samples = rows.take(2).map { it.first.take(300) },
            )
        }.sortedByDescending { it.messageCount }
    }

    /**
     * Queues past messages from the given senders within a date range.
     *
     * Everything goes through the same outbox and the same server fingerprint
     * check as live capture, so overlapping with messages already forwarded is
     * harmless - they collapse into the rows that are already there. That is
     * what makes it safe to let the user re-import any range they like.
     */
    fun backfill(
        context: Context,
        allowedSenders: Set<String>,
        fromMillis: Long,
        toMillis: Long = System.currentTimeMillis(),
        limit: Int = 2000,
    ): Int {
        if (allowedSenders.isEmpty()) return 0
        if (fromMillis > toMillis) return 0

        val store = IngestStore(context)
        var queued = 0
        var newest = 0L

        try {
            context.contentResolver.query(
                Telephony.Sms.Inbox.CONTENT_URI,
                PROJECTION,
                "${Telephony.Sms.DATE} >= ? AND ${Telephony.Sms.DATE} <= ?",
                arrayOf(fromMillis.toString(), toMillis.toString()),
                "${Telephony.Sms.DATE} DESC LIMIT $limit",
            )?.use { c ->
                val iAddress = c.getColumnIndex(Telephony.Sms.ADDRESS)
                val iBody = c.getColumnIndex(Telephony.Sms.BODY)
                val iDate = c.getColumnIndex(Telephony.Sms.DATE)

                while (c.moveToNext()) {
                    val address = c.getString(iAddress) ?: continue
                    if (IngestPrefs.normalizeSender(address) !in allowedSenders) continue

                    val body = c.getString(iBody)?.trim().orEmpty()
                    if (body.isEmpty()) continue

                    val date = if (iDate >= 0) c.getLong(iDate) else fromMillis
                    store.enqueue(address, body, date)
                    if (date > newest) newest = date
                    queued++
                }
            }
        } finally {
            store.close()
        }

        if (queued > 0) {
            val prefs = IngestPrefs(context)
            if (newest > prefs.lastImportedAt) prefs.lastImportedAt = newest
            UploadWorker.enqueueNow(context)
        }
        return queued
    }

    /** How many messages a range would import, without queueing anything. */
    fun countInRange(
        context: Context,
        allowedSenders: Set<String>,
        fromMillis: Long,
        toMillis: Long,
    ): Int {
        if (allowedSenders.isEmpty() || fromMillis > toMillis) return 0
        var count = 0

        context.contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms.ADDRESS),
            "${Telephony.Sms.DATE} >= ? AND ${Telephony.Sms.DATE} <= ?",
            arrayOf(fromMillis.toString(), toMillis.toString()),
            null,
        )?.use { c ->
            val iAddress = c.getColumnIndex(Telephony.Sms.ADDRESS)
            while (c.moveToNext()) {
                val address = c.getString(iAddress) ?: continue
                if (IngestPrefs.normalizeSender(address) in allowedSenders) count++
            }
        }
        return count
    }
}
