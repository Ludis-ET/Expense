package com.santim.mobile.ingest

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/**
 * Drains the outbox to the Santim API.
 *
 * Runs under WorkManager so it survives process death and gets exponential
 * backoff for free. Two things make the retry loop safe:
 *
 *  - the server keys every message by fingerprint, so re-sending a batch whose
 *    response we never saw is a no-op rather than a double entry;
 *  - rows are only deleted after the server has acknowledged them by name.
 */
class UploadWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val prefs = IngestPrefs(applicationContext)
        val token = prefs.deviceToken
        val baseUrl = prefs.baseUrl

        if (token.isNullOrBlank() || baseUrl.isNullOrBlank()) return@withContext Result.success()

        val store = IngestStore(applicationContext)
        try {
            // A row the server keeps refusing would otherwise sit at the head of
            // the queue forever, blocking everything behind it.
            store.dropExhausted(MAX_ATTEMPTS)

            var sentAnything = false
            while (true) {
                val batch = store.peek(BATCH_SIZE)
                if (batch.isEmpty()) break

                val outcome = postBatch(baseUrl, token, batch)
                when (outcome) {
                    is Outcome.Accepted -> {
                        store.delete(batch.map { it.id })
                        sentAnything = true
                    }
                    Outcome.AuthFailed -> {
                        // The device was unpaired or revoked server-side. Keep
                        // the queue but stop hammering; re-pairing resumes it.
                        Log.w(TAG, "Device token rejected - pausing uploads")
                        return@withContext Result.success()
                    }
                    Outcome.Retry -> {
                        store.markAttempted(batch.map { it.id })
                        return@withContext Result.retry()
                    }
                }
            }

            if (sentAnything) Log.i(TAG, "Outbox drained")
            Result.success()
        } catch (t: Throwable) {
            Log.w(TAG, "Upload failed", t)
            Result.retry()
        } finally {
            store.close()
        }
    }

    private sealed interface Outcome {
        data class Accepted(val count: Int) : Outcome
        data object Retry : Outcome
        data object AuthFailed : Outcome
    }

    private fun postBatch(baseUrl: String, token: String, batch: List<QueuedMessage>): Outcome {
        val payload = JSONObject().apply {
            put(
                "messages",
                JSONArray().apply {
                    for (m in batch) {
                        put(
                            JSONObject().apply {
                                put("sender", m.sender)
                                put("body", m.body)
                                put("receivedAt", iso8601(m.receivedAt))
                                put("source", "SMS")
                            },
                        )
                    }
                },
            )
        }

        val url = URL("${baseUrl.trimEnd('/')}/ingest/sms")
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 20_000
            readTimeout = 30_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("X-Device-Token", token)
        }

        return try {
            conn.outputStream.use { it.write(payload.toString().toByteArray(Charsets.UTF_8)) }

            when (val code = conn.responseCode) {
                in 200..299 -> {
                    conn.inputStream.bufferedReader().use(BufferedReader::readText)
                    Outcome.Accepted(batch.size)
                }
                401, 403 -> Outcome.AuthFailed
                // A malformed batch will never succeed, but we still want the
                // attempt counter to climb so the bad rows eventually age out
                // instead of wedging the queue.
                in 400..499 -> Outcome.Retry
                else -> {
                    Log.w(TAG, "Server returned $code")
                    Outcome.Retry
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Network error posting batch", t)
            Outcome.Retry
        } finally {
            conn.disconnect()
        }
    }

    private fun iso8601(millis: Long): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
            .apply { timeZone = TimeZone.getTimeZone("UTC") }
            .format(Date(millis))

    companion object {
        private const val TAG = "SantimUpload"
        private const val BATCH_SIZE = 50
        private const val MAX_ATTEMPTS = 8
        private const val UNIQUE_NOW = "santim-upload-now"
        private const val UNIQUE_PERIODIC = "santim-upload-periodic"

        /** Kicked off by the SMS receiver the instant something is queued. */
        fun enqueueNow(context: Context) {
            val request = OneTimeWorkRequestBuilder<UploadWorker>()
                .setConstraints(
                    Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build(),
                )
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()

            WorkManager.getInstance(context)
                .enqueueUniqueWork(UNIQUE_NOW, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
        }

        /**
         * A safety net, not the main path.
         *
         * Aggressive OEM battery managers (Xiaomi, Oppo, Vivo, some Samsungs)
         * will happily kill a one-shot job. A periodic sweep means the worst
         * case is a delayed transaction rather than a lost one.
         */
        fun enqueuePeriodic(context: Context) {
            val request = PeriodicWorkRequestBuilder<UploadWorker>(1, TimeUnit.HOURS)
                .setConstraints(
                    Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build(),
                )
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 5, TimeUnit.MINUTES)
                .build()

            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork(UNIQUE_PERIODIC, ExistingPeriodicWorkPolicy.KEEP, request)
        }
    }
}
