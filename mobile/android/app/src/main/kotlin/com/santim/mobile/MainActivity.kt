package com.santim.mobile

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import com.santim.mobile.ingest.IngestPrefs
import com.santim.mobile.ingest.IngestStore
import com.santim.mobile.ingest.SmsHistoryReader
import com.santim.mobile.ingest.UploadWorker
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The Dart <-> native seam.
 *
 * Everything on the capture path lives in Kotlin and runs whether or not a
 * Flutter engine exists. Dart's role is to configure it and to read back state
 * for the UI - it is never in the delivery path, which is what keeps ingest
 * working while the app is closed.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    handle(call.method, call, result)
                } catch (t: Throwable) {
                    result.error("NATIVE_ERROR", t.message, null)
                }
            }
    }

    private fun handle(method: String, call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val prefs = IngestPrefs(applicationContext)

        when (method) {
            /** Hands the native side its credential and sender allowlist. */
            "configure" -> {
                call.argument<String>("deviceToken")?.let { prefs.deviceToken = it }
                call.argument<String>("baseUrl")?.let { prefs.baseUrl = it }
                call.argument<Boolean>("captureEnabled")?.let { prefs.captureEnabled = it }
                call.argument<List<String>>("senders")?.let { list ->
                    prefs.allowedSenders = list.map(IngestPrefs::normalizeSender).toSet()
                }
                // Fixes the boundary between "history" and live capture the
                // first time capture is set up, and never moves it again.
                if (prefs.isConfigured()) prefs.markInstalledIfUnset()
                UploadWorker.enqueuePeriodic(applicationContext)
                result.success(true)
            }

            "getStatus" -> {
                val store = IngestStore(applicationContext)
                val pending = store.count()
                store.close()
                result.success(
                    mapOf(
                        "configured" to prefs.isConfigured(),
                        "captureEnabled" to prefs.captureEnabled,
                        "queued" to pending,
                        "senderCount" to prefs.allowedSenders.size,
                        "batteryUnrestricted" to isIgnoringBatteryOptimizations(),
                        "installedAt" to prefs.installedAt,
                        "lastImportedAt" to prefs.lastImportedAt,
                    ),
                )
            }

            "setCaptureEnabled" -> {
                prefs.captureEnabled = call.argument<Boolean>("enabled") ?: true
                result.success(prefs.captureEnabled)
            }

            /** Real sender ids off this phone, so setup is a pick-list not a guess. */
            "listInboxSenders" -> {
                val senders = SmsHistoryReader.recentSenders(applicationContext)
                result.success(
                    senders.map {
                        mapOf(
                            "sender" to it.sender,
                            "messageCount" to it.messageCount,
                            "lastMessageAt" to it.lastMessageAt,
                            "samples" to it.samples,
                        )
                    },
                )
            }

            /**
             * Imports a date range the user chose. Re-importing an overlapping
             * range is harmless: the outbox de-duplicates locally and the
             * server fingerprints every message, so nothing lands twice.
             */
            "backfill" -> {
                val from = call.argument<Long>("fromMillis")
                    ?: (System.currentTimeMillis() - 90L * 24 * 60 * 60 * 1000)
                val to = call.argument<Long>("toMillis") ?: System.currentTimeMillis()
                result.success(
                    SmsHistoryReader.backfill(applicationContext, prefs.allowedSenders, from, to),
                )
            }

            /** How many messages a range holds, so the user can see before importing. */
            "countInRange" -> {
                val from = call.argument<Long>("fromMillis") ?: 0L
                val to = call.argument<Long>("toMillis") ?: System.currentTimeMillis()
                result.success(
                    SmsHistoryReader.countInRange(applicationContext, prefs.allowedSenders, from, to),
                )
            }

            "syncNow" -> {
                UploadWorker.enqueueNow(applicationContext)
                result.success(true)
            }

            /**
             * The single biggest cause of "it stopped working after a few days"
             * on Xiaomi/Oppo/Vivo hardware, so setup asks for it explicitly.
             */
            "requestBatteryExemption" -> {
                if (isIgnoringBatteryOptimizations()) {
                    result.success(true)
                } else {
                    startActivity(
                        Intent(
                            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                    result.success(false)
                }
            }

            /** Unpairing: forget the credential and drop anything still queued. */
            "clear" -> {
                val store = IngestStore(applicationContext)
                store.clear()
                store.close()
                prefs.clear()
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    companion object {
        private const val CHANNEL = "com.santim.mobile/ingest"
    }
}
