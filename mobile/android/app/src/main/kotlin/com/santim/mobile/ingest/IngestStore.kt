package com.santim.mobile.ingest

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/** One captured message waiting to be delivered. */
data class QueuedMessage(
    val id: Long,
    val sender: String,
    val body: String,
    val receivedAt: Long,
    val attempts: Int,
)

/**
 * The on-device outbox.
 *
 * A broadcast receiver has roughly ten seconds before Android may kill the
 * process, so `onReceive` does exactly one thing: append here. Delivery is the
 * upload worker's problem, and until it succeeds the message survives reboots,
 * dead zones, and force-stops.
 *
 * Deliberately raw SQLite rather than Room: this is a single append-and-drain
 * table, and Room's annotation processor would add a KSP toolchain to the build
 * for no behaviour we would actually use.
 */
class IngestStore(context: Context) : SQLiteOpenHelper(context, DB_NAME, null, DB_VERSION) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE $TABLE (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              sender TEXT NOT NULL,
              body TEXT NOT NULL,
              receivedAt INTEGER NOT NULL,
              attempts INTEGER NOT NULL DEFAULT 0,
              createdAt INTEGER NOT NULL,
              UNIQUE(sender, body, receivedAt) ON CONFLICT IGNORE
            )
            """.trimIndent(),
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        db.execSQL("DROP TABLE IF EXISTS $TABLE")
        onCreate(db)
    }

    /**
     * Appends a message. The UNIQUE..ON CONFLICT IGNORE above makes this safe to
     * call twice for the same text - which happens when a history backfill
     * overlaps messages the receiver already caught live.
     */
    fun enqueue(sender: String, body: String, receivedAt: Long) {
        val values = ContentValues().apply {
            put("sender", sender)
            put("body", body)
            put("receivedAt", receivedAt)
            put("createdAt", System.currentTimeMillis())
        }
        writableDatabase.insertWithOnConflict(TABLE, null, values, SQLiteDatabase.CONFLICT_IGNORE)
    }

    fun peek(limit: Int): List<QueuedMessage> {
        val out = mutableListOf<QueuedMessage>()
        readableDatabase.query(
            TABLE,
            arrayOf("id", "sender", "body", "receivedAt", "attempts"),
            null, null, null, null,
            "receivedAt ASC",
            limit.toString(),
        ).use { c ->
            while (c.moveToNext()) {
                out += QueuedMessage(
                    id = c.getLong(0),
                    sender = c.getString(1),
                    body = c.getString(2),
                    receivedAt = c.getLong(3),
                    attempts = c.getInt(4),
                )
            }
        }
        return out
    }

    fun delete(ids: List<Long>) {
        if (ids.isEmpty()) return
        val placeholders = ids.joinToString(",") { "?" }
        writableDatabase.delete(TABLE, "id IN ($placeholders)", ids.map { it.toString() }.toTypedArray())
    }

    fun markAttempted(ids: List<Long>) {
        if (ids.isEmpty()) return
        val placeholders = ids.joinToString(",") { "?" }
        writableDatabase.execSQL(
            "UPDATE $TABLE SET attempts = attempts + 1 WHERE id IN ($placeholders)",
            ids.map { it.toString() }.toTypedArray(),
        )
    }

    /**
     * Drops messages the server has rejected over and over. Without this a
     * single permanently-bad row would block the queue forever, since the
     * worker drains oldest-first.
     */
    fun dropExhausted(maxAttempts: Int): Int =
        writableDatabase.delete(TABLE, "attempts >= ?", arrayOf(maxAttempts.toString()))

    fun count(): Int =
        readableDatabase.rawQuery("SELECT COUNT(*) FROM $TABLE", null).use { c ->
            if (c.moveToFirst()) c.getInt(0) else 0
        }

    fun clear() {
        writableDatabase.delete(TABLE, null, null)
    }

    companion object {
        private const val DB_NAME = "santim_ingest.db"
        private const val DB_VERSION = 1
        private const val TABLE = "outbox"
    }
}
