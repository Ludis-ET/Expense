import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'local_db.dart';

const Object _keep = Object();

/// What domain object this op touches.
enum OutboxEntity {
  transaction,
  account,
  category,
  budget,
  ledger,
  wishlist,
}

/// Verb within that entity.
enum OutboxAction {
  create,
  update,
  delete,
  transfer,
  fund,
  release,
  adjust,
  close,
  reopen,
  bought,
  cancel,
  payment,
  plan,
}

enum OutboxStatus { pending, syncing, error }

class OutboxOp {
  OutboxOp({
    required this.id,
    required this.entity,
    required this.action,
    required this.method,
    required this.path,
    required this.label,
    required this.status,
    required this.attempts,
    required this.createdAt,
    this.payload,
    this.targetId,
    this.detail,
    this.optimistic,
    this.error,
  });

  final String id;
  final OutboxEntity entity;
  final OutboxAction action;

  /// HTTP verb used when flushing: POST / PUT / DELETE.
  final String method;
  final String path;
  final String label;
  final String? detail;
  final Map<String, dynamic>? payload;
  final String? targetId;

  /// Transaction-shaped preview (transaction entity only).
  final Transaction? optimistic;
  final OutboxStatus status;
  final String? error;
  final int attempts;
  final int createdAt;

  OutboxOp copyWith({
    OutboxStatus? status,
    Object? error = _keep,
    int? attempts,
    Map<String, dynamic>? payload,
    Transaction? optimistic,
    String? detail,
  }) =>
      OutboxOp(
        id: id,
        entity: entity,
        action: action,
        method: method,
        path: path,
        label: label,
        detail: detail ?? this.detail,
        payload: payload ?? this.payload,
        targetId: targetId,
        optimistic: optimistic ?? this.optimistic,
        status: status ?? this.status,
        error: identical(error, _keep) ? this.error : error as String?,
        attempts: attempts ?? this.attempts,
        createdAt: createdAt,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'entity': entity.name,
        'action': action.name,
        'method': method,
        'path': path,
        'label': label,
        'detail': detail,
        'payload': payload == null ? null : jsonEncode(payload),
        'target_id': targetId,
        'optimistic': optimistic == null ? null : jsonEncode(txToJson(optimistic!)),
        'status': status.name,
        'error': error,
        'attempts': attempts,
        'created_at': createdAt,
      };

  factory OutboxOp.fromRow(Map<String, Object?> row) {
    final payloadRaw = row['payload'] as String?;
    final optimisticRaw = row['optimistic'] as String?;

    // Legacy v1 rows only had `kind` (create/transfer/update/delete).
    final legacyKind = row['kind'] as String?;
    final entityName = row['entity'] as String? ?? 'transaction';
    final actionName = row['action'] as String? ?? legacyKind ?? 'create';

    String method = row['method'] as String? ?? 'POST';
    String path = row['path'] as String? ?? '/transactions';
    String label = row['label'] as String? ?? 'Queued change';

    if (row['entity'] == null && legacyKind != null) {
      final target = row['target_id'] as String?;
      switch (legacyKind) {
        case 'create':
        case 'transfer':
          method = 'POST';
          path = '/transactions';
          label = legacyKind == 'transfer' ? 'Transfer' : 'Create transaction';
        case 'update':
          method = 'PUT';
          path = '/transactions/$target';
          label = 'Update transaction';
        case 'delete':
          method = 'DELETE';
          path = '/transactions/$target';
          label = 'Delete transaction';
      }
    }

    return OutboxOp(
      id: row['id'] as String,
      entity: OutboxEntity.values.byName(entityName),
      action: OutboxAction.values.byName(actionName),
      method: method,
      path: path,
      label: label,
      detail: row['detail'] as String?,
      payload: payloadRaw == null
          ? null
          : Map<String, dynamic>.from(jsonDecode(payloadRaw) as Map),
      targetId: row['target_id'] as String?,
      optimistic: optimisticRaw == null
          ? null
          : Transaction.fromJson(Map<String, dynamic>.from(jsonDecode(optimisticRaw) as Map)),
      status: OutboxStatus.values.byName(row['status'] as String),
      error: row['error'] as String?,
      attempts: row['attempts'] as int? ?? 0,
      createdAt: row['created_at'] as int? ?? 0,
    );
  }
}

bool isLocalId(String id) => id.startsWith('local:');

String newLocalId() => 'local:${const Uuid().v4()}';

/// Which queued operations create money rather than change or remove one.
///
/// Only these need replay protection: a lost reply to a create is
/// indistinguishable from the create never landing, so the retry books it a
/// second time. An update or a delete is naturally idempotent - applying it
/// twice reaches the same state.
const _creatingActions = {
  OutboxAction.create,
  OutboxAction.transfer,
  OutboxAction.fund,
  OutboxAction.release,
  OutboxAction.adjust,
  OutboxAction.payment,
};

/// Attach the op's own id so the server recognises a replay.
///
/// Sent on the first attempt too, not only on retries: the reply to the direct
/// call is exactly what goes missing when a connection drops mid-request.
Map<String, dynamic>? withOpKey(OutboxOp op, Map<String, dynamic>? body) {
  if (!_creatingActions.contains(op.action)) return body;
  return {...?body, 'clientOpId': '${op.action.name}:${op.id}'};
}

Map<String, dynamic> txToJson(Transaction tx) => {
      'id': tx.id,
      'kind': tx.kind.wire,
      'amount': tx.amount,
      'currency': tx.currency,
      'date': tx.date.toUtc().toIso8601String(),
      'accountId': tx.accountId,
      if (tx.account != null)
        'account': {
          'id': tx.account!.id,
          'name': tx.account!.name,
          if (tx.account!.icon != null) 'icon': tx.account!.icon,
          if (tx.account!.color != null) 'color': tx.account!.color,
        },
      if (tx.transferAccountId != null) 'transferAccountId': tx.transferAccountId,
      if (tx.transferAccount != null)
        'transferAccount': {
          'id': tx.transferAccount!.id,
          'name': tx.transferAccount!.name,
        },
      if (tx.categoryId != null) 'categoryId': tx.categoryId,
      if (tx.category != null)
        'category': {
          'id': tx.category!.id,
          'name': tx.category!.name,
          if (tx.category!.icon != null) 'icon': tx.category!.icon,
          if (tx.category!.color != null) 'color': tx.category!.color,
        },
      if (tx.budgetId != null) 'budgetId': tx.budgetId,
      if (tx.note != null) 'note': tx.note,
      if (tx.payee != null) 'payee': tx.payee,
      'tags': tx.tags,
      if (tx.budgetCycle != null) 'budgetCycle': tx.budgetCycle,
    };

class OutboxStore {
  OutboxStore(this._db);
  final LocalDb _db;

  Future<List<OutboxOp>> all() async {
    final db = await _db.database;
    if (db == null) return const [];
    final rows = await db.query('outbox', orderBy: 'created_at ASC');
    final out = <OutboxOp>[];
    for (final row in rows) {
      try {
        out.add(OutboxOp.fromRow(row));
      } catch (e) {
        debugPrint('Skipping corrupt outbox row ${row['id']}: $e');
      }
    }
    return out;
  }

  Future<OutboxOp?> get(String id) async {
    final db = await _db.database;
    if (db == null) return null;
    final rows = await db.query('outbox', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    try {
      return OutboxOp.fromRow(rows.first);
    } catch (e) {
      debugPrint('Corrupt outbox row $id: $e');
      return null;
    }
  }

  Future<void> put(OutboxOp op) async {
    final db = await _db.database;
    if (db == null) {
      throw StateError('Offline store unavailable');
    }
    await db.insert('outbox', op.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    if (db == null) return;
    await db.delete('outbox', where: 'id = ?', whereArgs: [id]);
  }
}
