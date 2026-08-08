import 'dart:convert';

import 'package:flutter/foundation.dart';
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
  final String kind;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;
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

class CachedPayload {
  const CachedPayload({required this.data, required this.fetchedAt});

  final Object? data;
  final DateTime fetchedAt;
}

/// On-device storage. Uses sqflite on mobile; an in-memory store on web so the
/// UI can be previewed in Chrome without a native SQLite plugin.
class LocalDb {
  LocalDb._sqflite(this._db) : _memory = false;
  LocalDb._memory()
      : _db = null,
        _memory = true;

  final Database? _db;
  final bool _memory;
  final Map<String, CachedPayload> _memCache = {};
  final List<_MemOutbox> _memOutbox = [];
  int _memOutboxId = 1;

  static LocalDb? _instance;

  static Future<LocalDb> open() async {
    if (_instance != null) return _instance!;

    if (kIsWeb) {
      return _instance = LocalDb._memory();
    }

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

    return _instance = LocalDb._sqflite(db);
  }

  Future<void> put(String key, Object? data) async {
    final payload = CachedPayload(data: data, fetchedAt: DateTime.now());
    if (_memory) {
      _memCache[key] = payload;
      return;
    }
    await _db!.insert(
      'cache',
      {
        'key': key,
        'payload': jsonEncode(data),
        'fetchedAt': payload.fetchedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<CachedPayload?> get(String key) async {
    if (_memory) return _memCache[key];

    final rows = await _db!.query('cache', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;

    try {
      return CachedPayload(
        data: jsonDecode(rows.first['payload'] as String),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(rows.first['fetchedAt'] as int),
      );
    } catch (_) {
      await _db!.delete('cache', where: 'key = ?', whereArgs: [key]);
      return null;
    }
  }

  Future<DateTime?> lastCachedAt() async {
    if (_memory) {
      if (_memCache.isEmpty) return null;
      return _memCache.values.map((e) => e.fetchedAt).reduce((a, b) => a.isAfter(b) ? a : b);
    }
    final rows = await _db!.rawQuery('SELECT MAX(fetchedAt) AS t FROM cache');
    final value = rows.first['t'] as int?;
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<void> clearCache() async {
    if (_memory) {
      _memCache.clear();
      return;
    }
    await _db!.delete('cache');
  }

  Future<int> enqueue(String kind, Map<String, dynamic> payload, {String? localId}) async {
    if (_memory) {
      final id = _memOutboxId++;
      _memOutbox.add(_MemOutbox(
        id: id,
        kind: kind,
        payload: payload,
        localId: localId,
        createdAt: DateTime.now(),
      ));
      return id;
    }
    return _db!.insert('outbox', {
      'kind': kind,
      'payload': jsonEncode(payload),
      'localId': localId,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<OutboxEntry>> pending({int limit = 100}) async {
    if (_memory) {
      final sorted = [..._memOutbox]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return sorted.take(limit).map((e) => e.toEntry()).toList();
    }
    final rows = await _db!.query('outbox', orderBy: 'createdAt ASC, id ASC', limit: limit);
    return rows.map(OutboxEntry.fromRow).toList();
  }

  Future<int> pendingCount() async {
    if (_memory) return _memOutbox.length;
    final rows = await _db!.rawQuery('SELECT COUNT(*) AS c FROM outbox');
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> remove(int id) async {
    if (_memory) {
      _memOutbox.removeWhere((e) => e.id == id);
      return;
    }
    await _db!.delete('outbox', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markFailed(int id, String error) async {
    if (_memory) {
      final i = _memOutbox.indexWhere((e) => e.id == id);
      if (i >= 0) {
        final e = _memOutbox[i];
        _memOutbox[i] = e.copy(attempts: e.attempts + 1, lastError: error);
      }
      return;
    }
    await _db!.rawUpdate(
      'UPDATE outbox SET attempts = attempts + 1, lastError = ? WHERE id = ?',
      [error, id],
    );
  }

  Future<void> clearOutbox() async {
    if (_memory) {
      _memOutbox.clear();
      return;
    }
    await _db!.delete('outbox');
  }

  Future<void> wipe() async {
    await clearCache();
    await clearOutbox();
  }
}

class _MemOutbox {
  const _MemOutbox({
    required this.id,
    required this.kind,
    required this.payload,
    required this.createdAt,
    this.localId,
    this.attempts = 0,
    this.lastError,
  });

  final int id;
  final String kind;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final String? localId;
  final int attempts;
  final String? lastError;

  _MemOutbox copy({int? attempts, String? lastError}) => _MemOutbox(
        id: id,
        kind: kind,
        payload: payload,
        createdAt: createdAt,
        localId: localId,
        attempts: attempts ?? this.attempts,
        lastError: lastError ?? this.lastError,
      );

  OutboxEntry toEntry() => OutboxEntry(
        id: id,
        kind: kind,
        payload: payload,
        createdAt: createdAt,
        attempts: attempts,
        lastError: lastError,
        localId: localId,
      );
}
