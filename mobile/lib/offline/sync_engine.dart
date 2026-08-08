import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import 'local_db.dart';

/// Kinds of queued write. Kept as constants rather than an enum so an entry
/// written by an older build still replays after an update.
class OutboxKind {
  static const transactionCreate = 'transaction.create';
  static const transactionDelete = 'transaction.delete';
  static const inboxConfirm = 'inbox.confirm';
  static const inboxReject = 'inbox.reject';
  static const senderUpsert = 'sender.upsert';
  static const senderDelete = 'sender.delete';
  static const cashAccount = 'user.cashAccount';
  static const accountNumber = 'account.number';
}

enum SyncPhase { idle, syncing, offline }

/// Drains the outbox whenever there is a connection, and tells the UI what is
/// going on.
///
/// The rules that matter:
///  - a server rejection (4xx) is permanent, so the entry is dropped and
///    reported rather than retried forever;
///  - a network failure is temporary, so the entry stays queued;
///  - replay is strictly oldest-first and stops at the first network failure,
///    because later entries may depend on earlier ones.
class SyncEngine extends ChangeNotifier {
  SyncEngine({required this.api, required this.db});

  final ApiClient api;
  final LocalDb db;

  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _watch;
  Timer? _retryTimer;

  SyncPhase phase = SyncPhase.idle;
  bool online = true;
  int pending = 0;
  DateTime? lastSyncedAt;
  DateTime? lastCachedAt;

  /// Entries the server refused. Surfaced so a rejected edit is not silently
  /// swallowed - the user needs to know their offline change did not stick.
  final List<String> rejected = [];

  bool get hasPending => pending > 0;
  bool get isSyncing => phase == SyncPhase.syncing;

  Future<void> start() async {
    await refreshCounts();

    final initial = await _connectivity.checkConnectivity();
    online = _isOnline(initial);

    _watch = _connectivity.onConnectivityChanged.listen((results) {
      final wasOffline = !online;
      online = _isOnline(results);
      notifyListeners();

      // Coming back from a dead zone is the whole reason this exists.
      if (online && wasOffline) unawaited(sync());
    });

    if (online) unawaited(sync());
  }

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.isNotEmpty && !results.every((r) => r == ConnectivityResult.none);

  Future<void> refreshCounts() async {
    pending = await db.pendingCount();
    lastCachedAt = await db.lastCachedAt();
    notifyListeners();
  }

  /// Queues a write and tries to send it immediately.
  ///
  /// Returns true when it went through there and then, false when it was
  /// parked for later. Throws [ApiException] when the server refuses the
  /// entry that was just queued (e.g. overdraw) so the caller can undo its
  /// optimistic UI and show the real reason.
  Future<bool> enqueue(String kind, Map<String, dynamic> payload, {String? localId}) async {
    final id = await db.enqueue(kind, payload, localId: localId);
    await refreshCounts();

    if (!online) return false;
    return _drain(focusId: id);
  }

  /// Replays everything queued.
  Future<void> sync() async {
    await _drain();
  }

  Future<void>? _inFlight;

  /// Returns true when [focusId] (or the whole queue) reached the server.
  Future<bool> _drain({int? focusId}) async {
    // Serialize drains so an enqueue during an in-flight sync does not replay
    // the same row twice.
    while (_inFlight != null) {
      await _inFlight;
    }
    final gate = Completer<void>();
    _inFlight = gate.future;

    phase = SyncPhase.syncing;
    notifyListeners();

    var focusSent = focusId == null;
    try {
      final entries = await db.pending();
      for (final entry in entries) {
        try {
          await replay(entry);
          await db.remove(entry.id);
          if (focusId != null && entry.id == focusId) focusSent = true;
        } on NetworkException {
          phase = SyncPhase.offline;
          online = false;
          _scheduleRetry();
          return false;
        } on ApiException catch (e) {
          await db.remove(entry.id);
          rejected.add(_describe(entry.kind, e.message));
          if (focusId != null && entry.id == focusId) rethrow;
        }
      }
      lastSyncedAt = DateTime.now();
      online = true;
      phase = SyncPhase.idle;
      return focusSent || focusId == null;
    } finally {
      await refreshCounts();
      if (phase == SyncPhase.syncing) phase = SyncPhase.idle;
      notifyListeners();
      gate.complete();
      _inFlight = null;
    }
  }

  /// A backstop for the case connectivity events miss - captive portals and
  /// some OEM network stacks report "connected" before traffic actually flows.
  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 45), () {
      if (pending > 0) unawaited(sync());
    });
  }

  String _describe(String kind, String message) => switch (kind) {
        OutboxKind.transactionCreate => 'Transaction not saved: $message',
        OutboxKind.transactionDelete => 'Delete failed: $message',
        OutboxKind.inboxConfirm => 'Message not recorded: $message',
        OutboxKind.inboxReject => 'Dismiss failed: $message',
        OutboxKind.senderUpsert || OutboxKind.senderDelete => 'Sender change failed: $message',
        OutboxKind.cashAccount => 'Cash wallet not saved: $message',
        OutboxKind.accountNumber => 'Account number not saved: $message',
        _ => message,
      };

  /// Maps a queued entry back onto the API call it stands for.
  @visibleForTesting
  Future<void> replay(OutboxEntry entry) async {
    final body = entry.payload;

    switch (entry.kind) {
      case OutboxKind.transactionCreate:
        await api.post('/transactions', body: body);
        return;
      case OutboxKind.transactionDelete:
        await api.delete('/transactions/${body['id']}');
        return;
      case OutboxKind.inboxConfirm:
        await api.post('/ingest/inbox/${body['id']}/confirm', body: body['data']);
        return;
      case OutboxKind.inboxReject:
        await api.post('/ingest/inbox/${body['id']}/reject');
        return;
      case OutboxKind.senderUpsert:
        await api.put('/ingest/senders', body: body);
        return;
      case OutboxKind.senderDelete:
        await api.delete('/ingest/senders/${body['id']}');
        return;
      case OutboxKind.cashAccount:
        await api.put('/users/me', body: {'cashAccountId': body['cashAccountId']});
        return;
      case OutboxKind.accountNumber:
        await api.put('/accounts/${body['id']}', body: {'accountNumber': body['accountNumber']});
        return;
      default:
        // An entry from a build that knew a kind this one does not. Dropping it
        // is better than blocking the queue forever.
        return;
    }
  }

  void clearRejected() {
    rejected.clear();
    notifyListeners();
  }

  /// Throws away unsent work. Only offered behind a confirmation.
  Future<void> discardPending() async {
    await db.clearOutbox();
    await refreshCounts();
  }

  @override
  void dispose() {
    _watch?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
}
