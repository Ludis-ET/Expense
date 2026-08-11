import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Local SQLite handle for the offline cache + outbox.
///
/// Failures never take down online mode: if the store cannot open (web,
/// missing plugin, bad migration), [ready] stays false and helpers no-op.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;
  bool _ready = false;
  bool? _webSkipped;

  bool get ready => _ready;

  Future<Database?> get database async {
    if (_ready && _db != null) return _db;
    if (kIsWeb) {
      _webSkipped ??= true;
      _ready = false;
      return null;
    }
    try {
      _db = await _open();
      _ready = true;
      return _db;
    } catch (e, st) {
      debugPrint('LocalDb unavailable: $e\n$st');
      _ready = false;
      _db = null;
      return null;
    }
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'santim_offline.db');

    Future<Database> openFresh() => openDatabase(
          path,
          version: 2,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        );

    try {
      final db = await openFresh();
      // Touch the schema so a half-migrated file fails here, not mid-write.
      await db.rawQuery('SELECT entity, action, method, path, label FROM outbox LIMIT 0');
      return db;
    } catch (e) {
      debugPrint('LocalDb open/migrate failed, recreating: $e');
      try {
        await deleteDatabase(path);
      } catch (_) {}
      return openFresh();
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE outbox (
        id TEXT PRIMARY KEY NOT NULL,
        entity TEXT NOT NULL DEFAULT 'transaction',
        action TEXT NOT NULL,
        method TEXT NOT NULL DEFAULT 'POST',
        path TEXT NOT NULL DEFAULT '/transactions',
        label TEXT NOT NULL DEFAULT 'Queued change',
        detail TEXT,
        kind TEXT,
        payload TEXT,
        target_id TEXT,
        optimistic TEXT,
        status TEXT NOT NULL,
        error TEXT,
        attempts INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE cache_blob (
        key TEXT PRIMARY KEY NOT NULL,
        json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE meta (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      Future<void> add(String sql) async {
        try {
          await db.execute(sql);
        } catch (e) {
          debugPrint('LocalDb migration skip: $e');
        }
      }

      await add("ALTER TABLE outbox ADD COLUMN entity TEXT NOT NULL DEFAULT 'transaction'");
      await add('ALTER TABLE outbox ADD COLUMN action TEXT');
      await add("ALTER TABLE outbox ADD COLUMN method TEXT NOT NULL DEFAULT 'POST'");
      await add("ALTER TABLE outbox ADD COLUMN path TEXT NOT NULL DEFAULT '/transactions'");
      await add("ALTER TABLE outbox ADD COLUMN label TEXT NOT NULL DEFAULT 'Queued change'");
      await add('ALTER TABLE outbox ADD COLUMN detail TEXT');
      try {
        await db.execute(
          'UPDATE outbox SET action = kind WHERE action IS NULL AND kind IS NOT NULL',
        );
      } catch (_) {}
    }
  }

  Future<void> putBlob(String key, Object json) async {
    final db = await database;
    if (db == null) return;
    await db.insert(
      'cache_blob',
      {
        'key': key,
        'json': jsonEncode(json),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getBlob(String key) async {
    final db = await database;
    if (db == null) return null;
    final rows = await db.query('cache_blob', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    final raw = rows.first['json'] as String;
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }

  Future<List<dynamic>?> getBlobList(String key) async {
    final db = await database;
    if (db == null) return null;
    final rows = await db.query('cache_blob', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    final decoded = jsonDecode(rows.first['json'] as String);
    if (decoded is List) return decoded;
    return null;
  }

  Future<void> putBlobList(String key, List<dynamic> json) async {
    final db = await database;
    if (db == null) return;
    await db.insert(
      'cache_blob',
      {
        'key': key,
        'json': jsonEncode(json),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int?> blobUpdatedAt(String key) async {
    final db = await database;
    if (db == null) return null;
    final rows = await db.query(
      'cache_blob',
      columns: ['updated_at'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['updated_at'] as int?;
  }

  Future<void> setMeta(String key, String value) async {
    final db = await database;
    if (db == null) return;
    await db.insert(
      'meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getMeta(String key) async {
    final db = await database;
    if (db == null) return null;
    final rows = await db.query('meta', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }
}

/// Cache key helpers.
abstract final class CacheKeys {
  static const accounts = 'accounts';
  static const categories = 'categories';
  static const dashboard = 'dashboard';
  static const budgets = 'budgets';
  static const spendSources = 'spend_sources';
  static const notifications = 'notifications';
  static const transactionsRecent = 'transactions_recent';
}
