import 'package:sqflite/sqflite.dart';

import '../models/ingest.dart';
import 'local_db.dart';

enum SmsOutboxStatus { pending, syncing, done, error }

class SmsOutboxRow {
  SmsOutboxRow({
    required this.fingerprint,
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.error,
  });

  final String fingerprint;
  final String sender;
  final String body;
  final DateTime receivedAt;
  final SmsOutboxStatus status;
  final int attempts;
  final String? error;
  final int createdAt;

  CapturedSms toCaptured() => CapturedSms(
        sender: sender,
        body: body,
        receivedAt: receivedAt,
      );

  factory SmsOutboxRow.fromRow(Map<String, Object?> row) => SmsOutboxRow(
        fingerprint: row['fingerprint'] as String,
        sender: row['sender'] as String,
        body: row['body'] as String,
        receivedAt: DateTime.fromMillisecondsSinceEpoch(row['received_at'] as int),
        status: SmsOutboxStatus.values.byName(row['status'] as String? ?? 'pending'),
        attempts: row['attempts'] as int? ?? 0,
        error: row['error'] as String?,
        createdAt: row['created_at'] as int? ?? 0,
      );
}

class SmsOutboxStore {
  SmsOutboxStore(this._db);
  final LocalDb _db;

  Future<bool> enqueue(CapturedSms sms) async {
    final db = await _db.database;
    if (db == null) return false;
    final fp = smsLocalFingerprint(sms.sender, sms.body, sms.receivedAt);
    final existing = await db.query(
      'sms_outbox',
      where: 'fingerprint = ?',
      whereArgs: [fp],
      limit: 1,
    );
    if (existing.isNotEmpty) return false;
    await db.insert(
      'sms_outbox',
      {
        'fingerprint': fp,
        'sender': sms.sender,
        'body': sms.body,
        'received_at': sms.receivedAt.millisecondsSinceEpoch,
        'status': SmsOutboxStatus.pending.name,
        'attempts': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return true;
  }

  Future<List<SmsOutboxRow>> pending({int limit = 100}) async {
    final db = await _db.database;
    if (db == null) return const [];
    final rows = await db.query(
      'sms_outbox',
      where: "status IN ('pending', 'error')",
      orderBy: 'received_at ASC',
      limit: limit,
    );
    return rows.map(SmsOutboxRow.fromRow).toList();
  }

  Future<int> pendingCount() async {
    final db = await _db.database;
    if (db == null) return 0;
    final r = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM sms_outbox WHERE status IN ('pending', 'error')",
    );
    return (r.first['c'] as int?) ?? 0;
  }

  Future<void> markDone(Iterable<String> fingerprints) async {
    final db = await _db.database;
    if (db == null) return;
    final batch = db.batch();
    for (final fp in fingerprints) {
      batch.delete('sms_outbox', where: 'fingerprint = ?', whereArgs: [fp]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> markError(String fingerprint, String error) async {
    final db = await _db.database;
    if (db == null) return;
    await db.update(
      'sms_outbox',
      {
        'status': SmsOutboxStatus.error.name,
        'error': error,
        'attempts': 1,
      },
      where: 'fingerprint = ?',
      whereArgs: [fingerprint],
    );
  }

  Future<void> clearAll() async {
    final db = await _db.database;
    if (db == null) return;
    await db.delete('sms_outbox');
  }
}
