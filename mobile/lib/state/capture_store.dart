import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/native_ingest.dart';
import '../models/ingest.dart';
import '../offline/local_db.dart';
import '../offline/sync_engine.dart';

/// Everything about bank-message capture: the review inbox, the sender
/// allowlist, the paired device, and the native layer's health.
///
/// One store rather than three because they are genuinely one feature - the
/// setup flow touches all of them in a single pass, and the settings panel
/// shows them together.
class CaptureStore extends ChangeNotifier {
  CaptureStore({required this.api, required this.db, required this.sync});

  final ApiClient api;
  final LocalDb db;
  final SyncEngine sync;

  List<InboxMessage> inbox = const [];
  InboxStats stats = const InboxStats.empty();
  List<SenderRule> senderRules = const [];
  List<BankInfo> banks = const [];
  List<PairedDevice> devices = const [];

  IngestStatus native = const IngestStatus.unknown();

  bool loading = false;
  String? error;

  /// True once this phone holds a device token and has senders approved.
  bool get isPaired => native.configured;
  int get needsReview => stats.needsReview;

  Future<void> refresh() async {
    loading = true;
    notifyListeners();

    await Future.wait([
      loadInbox(),
      loadStats(),
      loadSenderRules(),
      loadDevices(),
      refreshNativeStatus(),
    ]);

    loading = false;
    notifyListeners();
  }

  Future<void> refreshNativeStatus() async {
    if (!Platform.isAndroid) return;
    try {
      native = await NativeIngest.status();
    } catch (_) {
      native = const IngestStatus.unknown();
    }
    notifyListeners();
  }

  /// Paints the last known inbox before any network call, so the review deck
  /// is usable offline - which is exactly when you have time to clear it.
  Future<void> hydrateFromCache() async {
    final cached = await db.get('inbox');
    if (cached?.data is List) {
      inbox = (cached!.data as List)
          .whereType<Map<String, dynamic>>()
          .map(InboxMessage.fromJson)
          .toList();
    }

    final rules = await db.get('senderRules');
    if (rules?.data is List) {
      senderRules = (rules!.data as List)
          .whereType<Map<String, dynamic>>()
          .map(SenderRule.fromJson)
          .toList();
    }
    notifyListeners();
  }

  Future<void> loadInbox({bool unresolvedOnly = true}) async {
    try {
      final data = await api.get('/ingest/inbox', query: {
        if (unresolvedOnly) 'unresolved': true,
        'pageSize': 50,
      }) as Map<String, dynamic>;

      inbox = (data['items'] as List)
          .whereType<Map<String, dynamic>>()
          .map(InboxMessage.fromJson)
          .toList();
      await db.put('inbox', data['items']);
      error = null;
    } on NetworkException {
      // Keep whatever is on screen; the sync bar already says we are offline.
    } on ApiException catch (e) {
      error = e.message;
    }
    notifyListeners();
  }

  Future<void> loadStats() async {
    try {
      final data = await api.get('/ingest/inbox/stats') as Map<String, dynamic>;
      stats = InboxStats.fromJson(data);
      notifyListeners();
    } catch (_) {
      /* badge just stays stale */
    }
  }

  Future<void> loadSenderRules() async {
    try {
      final data = await api.get('/ingest/senders') as Map<String, dynamic>;
      senderRules = (data['items'] as List)
          .whereType<Map<String, dynamic>>()
          .map(SenderRule.fromJson)
          .toList();
      await db.put('senderRules', data['items']);
      notifyListeners();
    } on NetworkException {
      final cached = await db.get('senderRules');
      if (cached?.data is List && senderRules.isEmpty) {
        senderRules = (cached!.data as List)
            .whereType<Map<String, dynamic>>()
            .map(SenderRule.fromJson)
            .toList();
        notifyListeners();
      }
    } catch (_) {
      /* non-fatal - the cached copy stays on screen */
    }
  }

  Future<void> loadBanks() async {
    if (banks.isNotEmpty) return;
    try {
      final data = await api.get('/ingest/banks') as Map<String, dynamic>;
      banks = (data['items'] as List)
          .map((e) => BankInfo.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (_) {
      /* non-fatal */
    }
  }

  Future<void> loadDevices() async {
    try {
      final data = await api.get('/devices') as Map<String, dynamic>;
      devices = (data['items'] as List)
          .map((e) => PairedDevice.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (_) {
      /* non-fatal */
    }
  }

  /// Guesses which bank a raw sender id belongs to, using the server catalog.
  String bankKeyForSender(String sender) {
    final normalized = _normalize(sender);
    for (final bank in banks) {
      if (bank.senders.any((s) => _normalize(s) == normalized)) return bank.key;
    }
    return 'generic';
  }

  String? bankLabelForSender(String sender) {
    final key = bankKeyForSender(sender);
    if (key == 'generic') return null;
    return banks.where((b) => b.key == key).firstOrNull?.label;
  }

  /// Mirrors `normalizeSender` on the server and in Kotlin.
  static String _normalize(String raw) => raw
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'^\+?251'), '')
      .replaceAll(RegExp(r'[\s_-]+'), '');

  // --- pairing --------------------------------------------------------------

  /// Registers this phone and hands the token to the native layer.
  ///
  /// The plaintext token is returned exactly once by the server, so it goes
  /// straight into Kotlin's encrypted prefs and is never held in Dart state.
  Future<void> pairThisDevice({required String name}) async {
    final data = await api.post('/devices', body: {
      'name': name,
      'platform': 'android',
      'appVersion': '1.0.0',
    }) as Map<String, dynamic>;

    await NativeIngest.configure(
      deviceToken: data['deviceToken'] as String,
      baseUrl: api.baseUrl,
      captureEnabled: true,
    );

    await Future.wait([loadDevices(), refreshNativeStatus()]);
  }

  Future<void> revokeDevice(String id) async {
    await api.post('/devices/$id/revoke');
    await loadDevices();
  }

  /// Pushes the approved sender list down to the device, which is what the
  /// receiver filters against before anything is stored or sent.
  Future<void> syncSendersToDevice() async {
    final senders = senderRules.where((r) => r.enabled).map((r) => r.sender).toList();
    await NativeIngest.configure(senders: senders);
    await refreshNativeStatus();
  }

  Future<void> upsertSenderRule({
    required String sender,
    required String bankKey,
    String? accountId,
    String? defaultCategoryId,
    bool enabled = true,
    bool autoCommit = false,
  }) async {
    final body = {
      'sender': sender,
      'bankKey': bankKey,
      'accountId': accountId,
      'defaultCategoryId': defaultCategoryId,
      'enabled': enabled,
      'autoCommit': autoCommit,
    };

    // Optimistic: keep the allowlist usable offline for the next SMS that
    // lands before the phone finds signal again.
    final existing = senderRules.where((r) => r.sender.toLowerCase() == sender.toLowerCase()).firstOrNull;
    if (existing != null) {
      senderRules = [
        for (final r in senderRules)
          if (r.id == existing.id)
            SenderRule(
              id: r.id,
              sender: sender,
              bankKey: bankKey,
              bankLabel: r.bankLabel,
              enabled: enabled,
              autoCommit: autoCommit,
              accountId: accountId,
              accountName: r.accountName,
              defaultCategoryId: defaultCategoryId,
            )
          else
            r,
      ];
    }
    notifyListeners();

    final sent = await sync.enqueue(OutboxKind.senderUpsert, body);
    if (sent) {
      await loadSenderRules();
      await syncSendersToDevice();
    }
  }

  Future<void> deleteSenderRule(String id) async {
    senderRules = senderRules.where((r) => r.id != id).toList();
    notifyListeners();

    final sent = await sync.enqueue(OutboxKind.senderDelete, {'id': id});
    if (sent) {
      await loadSenderRules();
      await syncSendersToDevice();
    }
  }

  // --- review ---------------------------------------------------------------

  /// Turns a message into a real transaction.
  ///
  /// Queued when offline, so the review deck works with no signal - which is
  /// often exactly when you have the patience to clear an inbox. Throws
  /// [ApiException] when the server refuses, so the caller can show its reason
  /// (usually the overdraw guard).
  ///
  /// Returns true when it reached the server, false when it was parked.
  Future<bool> confirm(String id, Map<String, dynamic> body) async {
    // Optimistic: drop it out of the review queue immediately so the deck
    // advances without waiting on the network.
    inbox = inbox.where((m) => m.id != id).toList();
    stats = stats.withOneFewerToReview();
    notifyListeners();

    final sent = await sync.enqueue(OutboxKind.inboxConfirm, {'id': id, 'data': body});
    if (sent) await Future.wait([loadInbox(), loadStats()]);
    return sent;
  }

  Future<bool> reject(String id) async {
    inbox = inbox.where((m) => m.id != id).toList();
    stats = stats.withOneFewerToReview();
    notifyListeners();

    final sent = await sync.enqueue(OutboxKind.inboxReject, {'id': id});
    if (sent) await Future.wait([loadInbox(), loadStats()]);
    return sent;
  }

  /// Replays the current parsers over unresolved messages, after patterns have
  /// been improved server-side.
  Future<int> reparse() async {
    final data = await api.post('/ingest/inbox/reparse') as Map<String, dynamic>;
    await Future.wait([loadInbox(), loadStats()]);
    return (data['updated'] as num?)?.toInt() ?? 0;
  }

  Future<ParsePreview> preview(String sender, String body) async {
    final data = await api.post('/ingest/preview', body: {'sender': sender, 'body': body})
        as Map<String, dynamic>;
    return ParsePreview.fromJson(data);
  }

  /// Imports a chosen date range from the phone's SMS history.
  Future<int> backfill({required DateTime from, DateTime? to}) async {
    final queued = await NativeIngest.backfill(from: from, to: to);
    await refreshNativeStatus();
    return queued;
  }

  /// How many messages a range would bring in, shown before committing to it.
  Future<int> countInRange({required DateTime from, DateTime? to}) =>
      NativeIngest.countInRange(from: from, to: to);

  Future<void> syncNow() async {
    await NativeIngest.syncNow();
    await refreshNativeStatus();
  }

  Future<void> setCaptureEnabled(bool enabled) async {
    await NativeIngest.setCaptureEnabled(enabled);
    await refreshNativeStatus();
  }
}
