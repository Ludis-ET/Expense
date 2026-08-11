package com.santim.santim

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.provider.Telephony
import android.telephony.SmsMessage
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val methodChannelName = "santim/sms"
    private val eventChannelName = "santim/sms_events"
    private val widgetChannelName = "santim/widget"

    private var eventSink: EventChannel.EventSink? = null
    private var smsReceiver: BroadcastReceiver? = null

    /**
     * Set when the activity was started by the widget's add button. Dart reads
     * it once on startup, so a cold launch from the widget still lands on the
     * add sheet.
     */
    private var pendingAction: String? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        pendingAction = intent?.getStringExtra(SantimWidgetProvider.EXTRA_ACTION)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingAction = intent.getStringExtra(SantimWidgetProvider.EXTRA_ACTION)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Dart has written fresh values into shared preferences and
                    // wants the widget repainted.
                    "refresh" -> {
                        SantimWidgetProvider.redraw(applicationContext)
                        result.success(true)
                    }
                    // Consumed once — a later launch should not reopen the sheet.
                    "consumeLaunchAction" -> {
                        val action = pendingAction
                        pendingAction = null
                        result.success(action)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    registerSmsReceiver()
                }

                override fun onCancel(arguments: Any?) {
                    unregisterSmsReceiver()
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInbox" -> {
                        val minMs = (call.argument<Number>("minMs")?.toLong()) ?: 0L
                        val maxMs = (call.argument<Number>("maxMs")?.toLong())
                            ?: System.currentTimeMillis()
                        try {
                            result.success(queryInbox(minMs, maxMs))
                        } catch (e: SecurityException) {
                            result.error("permission", "SMS permission denied", null)
                        } catch (e: Exception) {
                            result.error("inbox", e.message, null)
                        }
                    }
                    "countInbox" -> {
                        val minMs = (call.argument<Number>("minMs")?.toLong()) ?: 0L
                        val maxMs = (call.argument<Number>("maxMs")?.toLong())
                            ?: System.currentTimeMillis()
                        try {
                            result.success(countInbox(minMs, maxMs))
                        } catch (e: SecurityException) {
                            result.error("permission", "SMS permission denied", null)
                        } catch (e: Exception) {
                            result.error("inbox", e.message, null)
                        }
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBatteryOptimizations())
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBatteryOptimizations()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun registerSmsReceiver() {
        if (smsReceiver != null) return
        smsReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
                val bundle = intent.extras ?: return
                @Suppress("DEPRECATION")
                val pdus = bundle.get("pdus") as? Array<*> ?: return
                val format = bundle.getString("format")
                val byAddress = linkedMapOf<String, StringBuilder>()
                var latestTs = System.currentTimeMillis()
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
                    latestTs = msg.timestampMillis
                }
                for ((address, body) in byAddress) {
                    eventSink?.success(
                        mapOf(
                            "sender" to address,
                            "body" to body.toString(),
                            "receivedAtMs" to latestTs,
                        ),
                    )
                }
            }
        }
        val filter = IntentFilter(Telephony.Sms.Intents.SMS_RECEIVED_ACTION)
        filter.priority = IntentFilter.SYSTEM_HIGH_PRIORITY
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(smsReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(smsReceiver, filter)
        }
    }

    private fun unregisterSmsReceiver() {
        smsReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        smsReceiver = null
    }

    private fun queryInbox(minMs: Long, maxMs: Long): List<Map<String, Any?>> {
        val uri = Uri.parse("content://sms/inbox")
        val projection = arrayOf("address", "body", "date")
        val selection = "date >= ? AND date <= ?"
        val args = arrayOf(minMs.toString(), maxMs.toString())
        val out = mutableListOf<Map<String, Any?>>()
        contentResolver.query(uri, projection, selection, args, "date DESC")?.use { cursor ->
            val iAddr = cursor.getColumnIndex("address")
            val iBody = cursor.getColumnIndex("body")
            val iDate = cursor.getColumnIndex("date")
            while (cursor.moveToNext()) {
                out.add(
                    mapOf(
                        "sender" to cursor.getString(iAddr),
                        "body" to cursor.getString(iBody),
                        "receivedAtMs" to cursor.getLong(iDate),
                    ),
                )
            }
        }
        return out
    }

    private fun countInbox(minMs: Long, maxMs: Long): Int {
        val uri = Uri.parse("content://sms/inbox")
        val selection = "date >= ? AND date <= ?"
        val args = arrayOf(minMs.toString(), maxMs.toString())
        contentResolver.query(uri, arrayOf("_id"), selection, args, null)?.use { cursor ->
            return cursor.count
        }
        return 0
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestIgnoreBatteryOptimizations() {
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:$packageName")
        }
        startActivity(intent)
    }

    override fun onDestroy() {
        unregisterSmsReceiver()
        super.onDestroy()
    }
}
