import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/api_client.dart';
import '../data/device_store.dart';
import '../data/local_db.dart';
import '../data/sms_outbox.dart';
import '../models/ingest.dart';
import '../models/models.dart';
import '../services/sms_bridge.dart';
import 'sync_state.dart';

/// Bank SMS capture + inbox review brain.
class SmsState extends ChangeNotifier {
  SmsState({
    required this.api,
    required SharedPreferences prefs,
    SyncState? sync,
    LocalDb? db,
  })  : devices = DeviceStore(prefs),
        _sync = sync,
        _outbox = SmsOutboxStore(db ?? LocalDb.instance);

  final ApiClient api;
  final DeviceStore devices;
  final SyncState? _sync;
  final SmsOutboxStore _outbox;
  final SmsBridge _bridge = SmsBridge.instance;

  StreamSubscription? _incomingSub;
  StreamSubscription? _onlineSub;
  Timer? _flushTimer;
  bool _started = false;
  bool _flushing = false;

  InboxStats stats = InboxStats.empty();
  List<InboxMessage> unresolved = const [];
  List<SenderRule> senderRules = const [];
  List<BankCatalogItem> banks = const [];
  List<PairedDevice> pairedDevices = const [];
  List<String> allowlist = const [];
  int localPendingUploads = 0;
  bool loadingInbox = false;
  bool loadingDevices = false;
  Object? inboxError;

  bool get isAndroid => !kIsWeb && Platform.isAndroid;
  bool get isPaired => devices.isPaired;
  bool get captureEnabled => devices.captureEnabled;
  bool get setupDone => devices.setupDone;
  int get needsReview => stats.needsReview;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await refreshStats();
    await _refreshPendingCount();
    if (isAndroid && isPaired && captureEnabled) {
      await _ensureListening();
    }
    _flushTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      unawaited(flushUploads());
    });
    if (_sync != null) {
      // Flush when connectivity returns.
      _sync.addListener(_onSyncChanged);
    }
    unawaited(flushUploads());
  }

  void _onSyncChanged() {
    if (_sync?.online == true) unawaited(flushUploads());
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _onlineSub?.cancel();
    _flushTimer?.cancel();
    _sync?.removeListener(_onSyncChanged);
    unawaited(_bridge.stopListening());
    super.dispose();
  }

  Future<void> _ensureListening() async {
    if (!isAndroid) return;
    final ok = await _bridge.hasPermissions();
    if (!ok) return;
    await _bridge.startListening();
    await _incomingSub?.cancel();
    _incomingSub = _bridge.incoming.listen((sms) {
      unawaited(_onIncoming(sms));
    });
    // Anything the manifest receiver caught while the app was closed. Drained
    // after the listener is attached so a message arriving in between is not
    // missed by both paths.
    await _drainPending();
  }

  /// Take delivery of whatever the native receiver queued while we were gone.
  ///
  /// Each goes through the same allowlist and outbox as a live capture, and the
  /// outbox is keyed by content, so a message that also turns up in a later
  /// inbox backfill does not enqueue twice.
  Future<void> _drainPending() async {
    if (!isAndroid || !captureEnabled) return;
    final pending = await _bridge.drainPending();
    if (pending.isEmpty) return;
    for (final sms in pending) {
      await _onIncoming(sms);
    }
  }

  Future<void> _onIncoming(CapturedSms sms) async {
    if (!captureEnabled) return;
    if (!_senderAllowed(sms.sender)) return;
    final added = await _outbox.enqueue(sms);
    if (added) {
      await _refreshPendingCount();
      unawaited(flushUploads());
    }
  }

  bool _senderAllowed(String sender) {
    final n = _normalizeSender(sender);
    if (allowlist.isEmpty) {
      // Until rules sync, fall back to known bank short codes from catalog.
      for (final b in banks) {
        for (final s in b.senders) {
          if (_normalizeSender(s) == n) return true;
        }
      }
      return false;
    }
    return allowlist.any((s) => _normalizeSender(s) == n);
  }

  String _normalizeSender(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  Future<void> _refreshPendingCount() async {
    localPendingUploads = await _outbox.pendingCount();
    notifyListeners();
  }

  Future<bool> requestSmsPermission() => _bridge.requestPermissions();

  Future<bool> hasSmsPermission() => _bridge.hasPermissions();

  Future<void> requestBatteryExemption() =>
      _bridge.requestIgnoreBatteryOptimizations();

  Future<bool> isBatteryExempt() => _bridge.isIgnoringBatteryOptimizations();

  Future<PairedDevice> pairDevice({required String name}) async {
    final json = await api.post<Map<String, dynamic>>(
      '/devices',
      body: {
        'name': name,
        'platform': 'android',
        'appVersion': '1.0.0',
      },
    );
    final device = PairedDevice.fromJson(asMap(json['device']));
    final token = asStr(json['deviceToken'], '');
    if (token.isEmpty) throw ApiError(500, 'Server did not return a device token');
    await devices.savePairing(
      deviceId: device.id,
      deviceName: device.name,
      deviceToken: token,
    );
    notifyListeners();
    await refreshManifest();
    await _ensureListening();
    unawaited(loadDevices(force: true));
    return device;
  }

  Future<void> revokeAndClear() async {
    final id = devices.deviceId;
    if (id != null) {
      try {
        await api.post('/devices/$id/revoke');
      } catch (_) {}
    }
    await devices.clearPairing();
    await _bridge.stopListening();
    await _incomingSub?.cancel();
    _incomingSub = null;
    await loadDevices();
    notifyListeners();
  }

  Future<void> setCaptureEnabled(bool enabled) async {
    await devices.setCaptureEnabled(enabled);
    if (enabled) {
      await _ensureListening();
    } else {
      await _bridge.stopListening();
    }
    notifyListeners();
  }

  Future<List<PairedDevice>> listDevices() async {
    final json = await api.get('/devices');
    return mapItemsList(json, PairedDevice.fromJson);
  }

  Future<void> loadDevices({bool force = false}) async {
    if (loadingDevices && !force) return;
    loadingDevices = true;
    notifyListeners();
    try {
      pairedDevices = await listDevices();
    } catch (e) {
      debugPrint('loadDevices failed: $e');
    } finally {
      loadingDevices = false;
      notifyListeners();
    }
  }

  /// Revoke any household phone. If it is *this* handset, also clear local pairing.
  Future<void> revokeDevice(String id) async {
    await api.post('/devices/$id/revoke');
    if (id == devices.deviceId) {
      await devices.clearPairing();
      await _bridge.stopListening();
      await _incomingSub?.cancel();
      _incomingSub = null;
    }
    await loadDevices(force: true);
    notifyListeners();
  }

  Future<void> loadBanks() async {
    final json = await api.get('/ingest/banks');
    banks = mapItemsList(json, BankCatalogItem.fromJson);
    notifyListeners();
  }

  Future<void> loadSenderRules() async {
    final json = await api.get('/ingest/senders');
    senderRules = mapItemsList(json, SenderRule.fromJson);
    notifyListeners();
  }

  Future<SenderRule> upsertSenderRule(Map<String, dynamic> body) async {
    final json = await api.put<Map<String, dynamic>>('/ingest/senders', body: body);
    final rule = SenderRule.fromJson(json);
    final i = senderRules.indexWhere((r) => r.sender == rule.sender);
    if (i >= 0) {
      senderRules = [...senderRules]..[i] = rule;
    } else {
      senderRules = [...senderRules, rule];
    }
    await refreshManifest();
    notifyListeners();
    return rule;
  }

  Future<void> deleteSenderRule(String id) async {
    await api.delete('/ingest/senders/$id');
    senderRules = senderRules.where((r) => r.id != id).toList();
    await refreshManifest();
    notifyListeners();
  }

  Future<void> refreshManifest() async {
    final token = await devices.deviceToken;
    if (token == null) return;
    try {
      final json = await api.deviceRequest<Map<String, dynamic>>(
        'GET',
        '/ingest/manifest',
        deviceToken: token,
      );
      allowlist = [
        ...asStrList(json['senders']),
        ...asStrList(json['knownSenders']),
      ];
      notifyListeners();
    } catch (e) {
      debugPrint('manifest refresh failed: $e');
    }
  }

  Future<void> refreshStats() async {
    try {
      final json = await api.get<Map<String, dynamic>>('/ingest/inbox/stats');
      stats = InboxStats.fromJson(json);
      notifyListeners();
    } catch (e) {
      debugPrint('inbox stats failed: $e');
    }
  }

  Future<void> loadUnresolved({bool force = false}) async {
    if (loadingInbox && !force) return;
    loadingInbox = true;
    inboxError = null;
    notifyListeners();
    try {
      final json = await api.get<Map<String, dynamic>>(
        '/ingest/inbox',
        query: {'unresolved': true, 'pageSize': 50},
      );
      unresolved = mapList(json['items'], InboxMessage.fromJson);
      await LocalDb.instance.putBlob(CacheKeys.inboxUnresolved, json);
      await refreshStats();
    } catch (e) {
      inboxError = e;
      try {
        final cached = await LocalDb.instance.getBlob(CacheKeys.inboxUnresolved);
        if (cached != null) {
          unresolved = mapList(cached['items'], InboxMessage.fromJson);
        }
      } catch (_) {}
    } finally {
      loadingInbox = false;
      notifyListeners();
    }
  }

  Future<List<InboxMessage>> loadInbox({
    String? status,
    bool unresolvedOnly = false,
  }) async {
    final json = await api.get<Map<String, dynamic>>(
      '/ingest/inbox',
      query: {
        'status': ?status,
        if (unresolvedOnly) 'unresolved': true,
        'pageSize': 50,
      },
    );
    return mapList(json['items'], InboxMessage.fromJson);
  }

  Future<void> confirm(String id, Map<String, dynamic> body) async {
    await api.post('/ingest/inbox/$id/confirm', body: body);
    unresolved = unresolved.where((m) => m.id != id).toList();
    await refreshStats();
    notifyListeners();
  }

  Future<void> reject(String id) async {
    await api.post('/ingest/inbox/$id/reject');
    unresolved = unresolved.where((m) => m.id != id).toList();
    await refreshStats();
    notifyListeners();
  }

  Future<void> deleteMessage(String id) async {
    await api.delete('/ingest/inbox/$id');
    unresolved = unresolved.where((m) => m.id != id).toList();
    await refreshStats();
    notifyListeners();
  }

  Future<Map<String, dynamic>> reparse() async {
    final json = await api.post<Map<String, dynamic>>('/ingest/inbox/reparse');
    await loadUnresolved(force: true);
    return json;
  }

  /// Latest SMS-reported balances vs Santim wallet balances.
  Future<List<BalanceDrift>> loadBalanceReconciliation({
    double threshold = 1.0,
  }) async {
    await loadSenderRules();
    final accounts = <String, Account>{};
    try {
      final items = mapItemsList(await api.get('/accounts'), Account.fromJson);
      for (final a in items) {
        accounts[a.id] = a;
      }
    } catch (_) {}

    final confirmed = await loadInbox(status: 'CONFIRMED');
    final pending = await loadInbox(unresolvedOnly: true);
    final all = [...pending, ...confirmed];

    // Newest message with a balance per mapped wallet.
    final latestByAccount = <String, InboxMessage>{};
    for (final m in all) {
      final bal = double.tryParse(m.parsedBalance ?? '');
      if (bal == null) continue;
      final accountId = m.account?.id ??
          senderRules
              .where((r) => r.sender.toLowerCase() == m.sender.toLowerCase())
              .map((r) => r.accountId)
              .firstOrNull;
      if (accountId == null) continue;
      final prev = latestByAccount[accountId];
      if (prev == null || m.receivedAt.isAfter(prev.receivedAt)) {
        latestByAccount[accountId] = m;
      }
    }

    final drifts = <BalanceDrift>[];
    for (final entry in latestByAccount.entries) {
      final account = accounts[entry.key];
      if (account == null) continue;
      final smsBal = double.tryParse(entry.value.parsedBalance ?? '') ?? 0;
      final walletBal = double.tryParse(account.realBalance) ??
          double.tryParse(account.balance) ??
          0;
      final drift = (smsBal - walletBal).abs();
      if (drift < threshold) continue;
      drifts.add(
        BalanceDrift(
          account: account,
          smsBalance: smsBal,
          walletBalance: walletBal,
          drift: drift,
          message: entry.value,
        ),
      );
    }
    drifts.sort((a, b) => b.drift.compareTo(a.drift));
    return drifts;
  }

  /// Per-sender parse confidence trend (recent vs older).
  Future<List<SenderHealth>> loadSenderHealth() async {
    await loadSenderRules();
    final confirmed = await loadInbox(status: 'CONFIRMED');
    final pending = await loadInbox(unresolvedOnly: true);
    final all = [...pending, ...confirmed];

    final bySender = <String, List<InboxMessage>>{};
    for (final m in all) {
      bySender.putIfAbsent(m.sender, () => []).add(m);
    }

    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    final out = <SenderHealth>[];

    for (final entry in bySender.entries) {
      final msgs = entry.value..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
      if (msgs.isEmpty) continue;
      final recent = msgs.where((m) => m.receivedAt.isAfter(weekAgo)).toList();
      final older = msgs.where((m) => !m.receivedAt.isAfter(weekAgo)).toList();
      double avg(List<InboxMessage> list) {
        if (list.isEmpty) return 0;
        return list.map((m) => m.confidence).fold<int>(0, (a, b) => a + b) /
            list.length;
      }

      final recentAvg = avg(recent.isEmpty ? msgs.take(5).toList() : recent);
      final olderAvg = avg(older.isEmpty ? msgs.skip(5).toList() : older);
      final drop = olderAvg > 0 ? olderAvg - recentAvg : 0.0;
      final unparsed = msgs.where((m) => m.status == 'UNPARSED').length;
      final rule = senderRules
          .where((r) => r.sender.toLowerCase() == entry.key.toLowerCase())
          .firstOrNull;

      out.add(
        SenderHealth(
          sender: entry.key,
          bankLabel: rule?.bankLabel ?? msgs.first.bankLabel,
          sampleCount: msgs.length,
          recentAvgConfidence: recentAvg,
          olderAvgConfidence: olderAvg,
          confidenceDrop: drop,
          unparsedCount: unparsed,
          unhealthy: drop >= 15 || (recentAvg > 0 && recentAvg < 50) || unparsed >= 3,
          rule: rule,
        ),
      );
    }

    out.sort((a, b) {
      if (a.unhealthy != b.unhealthy) return a.unhealthy ? -1 : 1;
      return b.confidenceDrop.compareTo(a.confidenceDrop);
    });
    return out;
  }

  Future<Map<String, dynamic>> preview({
    required String sender,
    required String body,
  }) {
    return api.post<Map<String, dynamic>>(
      '/ingest/preview',
      body: {'sender': sender, 'body': body},
    );
  }

  /// Scan device SMS for candidate sender addresses.
  Future<List<({String sender, String sample, int count})>> scanCandidateSenders({
    Duration lookback = const Duration(days: 90),
  }) async {
    final min = DateTime.now().subtract(lookback);
    final messages = await _bridge.getInbox(min: min);
    final map = <String, ({String sample, int count})>{};
    for (final m in messages) {
      final key = m.sender.trim();
      if (key.isEmpty) continue;
      final prev = map[key];
      map[key] = (sample: prev?.sample ?? m.body, count: (prev?.count ?? 0) + 1);
    }
    final list = map.entries
        .map((e) => (sender: e.key, sample: e.value.sample, count: e.value.count))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return list;
  }

  Future<int> countHistory({required DateTime min, DateTime? max}) {
    return _bridge.countInbox(min: min, max: max);
  }

  Future<int> importHistory({required DateTime min, DateTime? max}) async {
    final messages = await _bridge.getInbox(min: min, max: max);
    var added = 0;
    for (final m in messages) {
      if (!_senderAllowed(m.sender) && allowlist.isNotEmpty) {
        // Still enqueue known-looking bank traffic during first import.
        final looksBank = banks.any(
          (b) => b.senders.any((s) => _normalizeSender(s) == _normalizeSender(m.sender)),
        );
        if (!looksBank) continue;
      }
      if (await _outbox.enqueue(m)) added++;
    }
    await _refreshPendingCount();
    unawaited(flushUploads());
    return added;
  }

  Future<void> clearLocalSmsOutbox() async {
    await _outbox.clearAll();
    await _refreshPendingCount();
  }

  Future<void> flushUploads() async {
    if (_flushing) return;
    if (_sync != null && !_sync.online) return;
    final token = await devices.deviceToken;
    if (token == null) return;

    final batch = await _outbox.pending(limit: 100);
    if (batch.isEmpty) return;

    _flushing = true;
    try {
      final payload = {
        'messages': batch.map((r) => r.toCaptured().toIngestJson()).toList(),
      };
      final json = await api.deviceRequest<Map<String, dynamic>>(
        'POST',
        '/ingest/sms',
        deviceToken: token,
        body: payload,
      );
      final results = (json['results'] is List) ? json['results'] as List : const [];
      final done = <String>[];
      for (var i = 0; i < batch.length; i++) {
        final row = batch[i];
        final res = i < results.length && results[i] is Map
            ? Map<String, dynamic>.from(results[i] as Map)
            : null;
        // Treat accepted, duplicate, and ignored as done so we stop retrying.
        if (res == null || res['status'] != null || res['duplicate'] == true) {
          done.add(row.fingerprint);
        }
      }
      if (done.isEmpty) {
        // Fallback: if server shape unexpected but 2xx, drop the batch.
        done.addAll(batch.map((b) => b.fingerprint));
      }
      await _outbox.markDone(done);
      await _refreshPendingCount();
      await refreshStats();
      unawaited(loadUnresolved(force: true));
    } on ApiError catch (e) {
      if (!e.isNetwork) {
        for (final row in batch) {
          await _outbox.markError(row.fingerprint, e.message);
        }
      }
    } catch (e) {
      debugPrint('SMS flush failed: $e');
    } finally {
      _flushing = false;
      await _refreshPendingCount();
    }
  }

  Future<void> completeSetup() async {
    await devices.setSetupDone(true);
    notifyListeners();
  }
}

class BalanceDrift {
  BalanceDrift({
    required this.account,
    required this.smsBalance,
    required this.walletBalance,
    required this.drift,
    required this.message,
  });

  final Account account;
  final double smsBalance;
  final double walletBalance;
  final double drift;
  final InboxMessage message;
}

class SenderHealth {
  SenderHealth({
    required this.sender,
    required this.sampleCount,
    required this.recentAvgConfidence,
    required this.olderAvgConfidence,
    required this.confidenceDrop,
    required this.unparsedCount,
    required this.unhealthy,
    this.bankLabel,
    this.rule,
  });

  final String sender;
  final String? bankLabel;
  final int sampleCount;
  final double recentAvgConfidence;
  final double olderAvgConfidence;
  final double confidenceDrop;
  final int unparsedCount;
  final bool unhealthy;
  final SenderRule? rule;
}
