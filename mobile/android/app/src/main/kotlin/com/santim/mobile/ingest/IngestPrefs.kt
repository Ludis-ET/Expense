package com.santim.mobile.ingest

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Configuration the native side needs while Dart is not running.
 *
 * The SMS receiver and the upload worker both start in a cold process with no
 * Flutter engine attached, so nothing here can live in Dart state. The device
 * token in particular is a long-lived credential to a finance account, so it
 * goes in EncryptedSharedPreferences rather than plain prefs.
 */
class IngestPrefs(context: Context) {

    private val prefs: SharedPreferences = try {
        val key = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            FILE_ENCRYPTED,
            key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    } catch (t: Throwable) {
        // A handful of devices ship a broken keystore and throw here. Falling
        // back keeps capture working rather than bricking the feature; the
        // token is still in app-private storage that no other app can read.
        context.getSharedPreferences(FILE_FALLBACK, Context.MODE_PRIVATE)
    }

    var deviceToken: String?
        get() = prefs.getString(KEY_TOKEN, null)
        set(value) = prefs.edit().putString(KEY_TOKEN, value).apply()

    /** Base API URL including the version prefix, e.g. https://host/api/v1 */
    var baseUrl: String?
        get() = prefs.getString(KEY_BASE_URL, null)
        set(value) = prefs.edit().putString(KEY_BASE_URL, value).apply()

    /** Master switch, so the user can pause capture without unpairing. */
    var captureEnabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, true)
        set(value) = prefs.edit().putBoolean(KEY_ENABLED, value).apply()

    /**
     * Normalized sender ids we are allowed to forward.
     *
     * This is the privacy boundary and it is enforced here, on the device:
     * a message from anyone not on this list is dropped inside `onReceive` and
     * never reaches storage, let alone the network.
     */
    var allowedSenders: Set<String>
        get() = prefs.getStringSet(KEY_SENDERS, emptySet()) ?: emptySet()
        set(value) = prefs.edit().putStringSet(KEY_SENDERS, value).apply()

    /**
     * When capture was first switched on.
     *
     * This is the line between "history" and "normal operation": anything from
     * this moment forward is picked up live by the receiver, and anything
     * before it only arrives if the user explicitly imports a date range. Set
     * once and never moved, so a re-pair does not silently re-import.
     */
    var installedAt: Long
        get() = prefs.getLong(KEY_INSTALLED_AT, 0L)
        set(value) = prefs.edit().putLong(KEY_INSTALLED_AT, value).apply()

    /** Records the install moment the first time capture is configured. */
    fun markInstalledIfUnset() {
        if (installedAt == 0L) installedAt = System.currentTimeMillis()
    }

    /** Newest message timestamp already imported, so a re-import can skip it. */
    var lastImportedAt: Long
        get() = prefs.getLong(KEY_LAST_IMPORT, 0L)
        set(value) = prefs.edit().putLong(KEY_LAST_IMPORT, value).apply()

    fun isConfigured(): Boolean = !deviceToken.isNullOrBlank() && !baseUrl.isNullOrBlank()

    fun clear() = prefs.edit().clear().apply()

    companion object {
        private const val FILE_ENCRYPTED = "santim_ingest_secure"
        private const val FILE_FALLBACK = "santim_ingest"
        private const val KEY_TOKEN = "device_token"
        private const val KEY_BASE_URL = "base_url"
        private const val KEY_ENABLED = "capture_enabled"
        private const val KEY_SENDERS = "allowed_senders"
        private const val KEY_INSTALLED_AT = "installed_at"
        private const val KEY_LAST_IMPORT = "last_imported_at"

        /** Must mirror `normalizeSender` in the backend parser registry. */
        fun normalizeSender(raw: String): String =
            raw.trim().lowercase()
                .removePrefix("+251")
                .removePrefix("251")
                .replace(Regex("[\\s_-]+"), "")
    }
}
