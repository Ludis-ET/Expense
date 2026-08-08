package com.santim.mobile.ingest

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Re-arms the periodic upload sweep after a reboot or an app update.
 *
 * WorkManager restores its own scheduled work across reboots, but only once
 * something touches it - and anything queued while the phone was off would
 * otherwise wait for the next SMS to trigger a drain.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) return

        val prefs = IngestPrefs(context)
        if (!prefs.captureEnabled || !prefs.isConfigured()) return

        UploadWorker.enqueuePeriodic(context)
        UploadWorker.enqueueNow(context)
    }
}
