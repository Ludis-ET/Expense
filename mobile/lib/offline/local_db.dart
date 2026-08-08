import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// One queued write, waiting for a connection.
class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.kind,
    required this.payload,
    required this.createdAt,
    required this.attempts,
    this.lastError,
    this.localId,
  });

  final int id;

  /// What to replay. See `SyncEngine.replay` for the mapping to endpoints.
  final String kind;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;

  /// Why the last attempt failed. Shown in the pending-changes list.
  final String? lastError;

  /// Ties the entry to the optimistic row shown in the UI, so a successful
  /// sync can replace that row rather than duplicating it.
  final String? localId;

  factory OutboxEntry.fromRow(Map<String, Object?> row) => OutboxEntry(
        id: row['id'] as int,
        kind: row['kind'] as String,
        payload: jsonDecode(row['payload'] as String) as Map<String, dynamic>,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['createdAt'] as int),
        attempts: row['attempts'] as int? ?? 0,
        lastError: row['lastError'] as String?,
        localId: row['localId'] as String?,
      );
}

/// A cached API response and when it was fetched.
class CachedPayload {
  const CachedPayload({required this.data, required this.fetchedAt});

  final Object? data;
  final DateTime fetchedAt;
}

/// On-device storage: a response cache so the app opens with real data while
/// offline, and an outbox so edits made offline are not lost.
///
/// Mirrors the web app's IndexedDB outbox, and deliberately uses the same
/// "queue the intent, replay it later" shape rather than trying to sync
/// database state - replaying a user's actions is far easier to reason about
/// than merging two divergent copies of a ledger.
class LocalDb {
  LocalDb._(this._db);

  final Database _db;
  static LocalDb? _instance;

  static Future<LocalDb> open() async {
    if (_instance != null) return _instance!;

    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'santim_offline.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE cache (
            key TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            fetchedAt INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            payload TEXT NOT NULL,
            localId TEXT,
            createdAt INTEGER NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            lastError TEXT
          )
        ''');
        await db.execute('CREATE INDEX outbox_created ON outbox(createdAt)');
      },
    );

    return _instance = LocalDb._(db);
  }

  // --- cache ----------------------------------------------------------------

  Future<void> put(String key, Object? data) async {
    await _db.insert(
      'cache',
      {
        'key': key,
        'payload': jsonEncode(data),
        'fetchedAt': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<CachedPayload?> get(String key) async {
    final rows = await _db.query('cache', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;

    try {
      return CachedPayload(
        data: jsonDecode(rows.first['payload'] as String),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(rows.first['fetchedAt'] as int),
      );
    } catch (_) {
      // A payload we can no longer parse is worse than none - drop it so the
      // next online load can replace it cleanly.
      await _db.delete('cache', where: 'key = ?', whereArgs: [key]);
      return null;
    }
  }

  /// Newest `fetchedAt` across everything cached - "last updated" for the UI.
  Future<DateTime?> lastCachedAt() async {
    final rows = await _db.rawQuery('SELECT MAX(fetchedAt) AS t FROM cache');
    final value = rows.first['t'] as int?;
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<void> clearCache() => _db.delete('cache');

  // --- outbox ---------------------------------------------------------------

  Future<int> enqueue(String kind, Map<String, dynamic> payload, {String? localId}) {
    return _db.insert('outbox', {
      'kind': kind,
      'payload': jsonEncode(payload),
      'localId': localId,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Oldest first: replaying out of order could, for instance, confirm a
  /// message before the account it references exists.
  Future<List<OutboxEntry>> pending({int limit = 100}) async {
    final rows = await _db.query('outbox', orderBy: 'createdAt ASC, id ASC', limit: limit);
    return rows.map(OutboxEntry.fromRow).toList();
  }

  Future<int> pendingCount() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS c FROM outbox');
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> remove(int id) => _db.delete('outbox', where: 'id = ?', whereArgs: [id]);

  Future<void> markFailed(int id, String error) async {
    await _db.rawUpdate(
      'UPDATE outbox SET attempts = attempts + 1, lastError = ? WHERE id = ?',
      [error, id],
    );
  }

  Future<void> clearOutbox() => _db.delete('outbox');

  /// Wipes everything. Used on sign-out: the next account must not inherit the
  /// previous one's cached balances or unsent edits.
  Future<void> wipe() async {
    await clearCache();
    await clearOutbox();
  }
}
