import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../models/models.dart';
import '../models/money.dart';
import '../data/local_db.dart';
import '../data/outbox_store.dart';

class QueueResult {
  const QueueResult({required this.queued});
  final bool queued;
}

/// Online/offline sync brain   ports the web `OfflineProvider`.
class SyncState extends ChangeNotifier {
  SyncState({required this.api, LocalDb? db})
    : _db = db ?? LocalDb.instance,
      _outbox = OutboxStore(db ?? LocalDb.instance);

  final ApiClient api;
  final LocalDb _db;
  final OutboxStore _outbox;

  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _retryTimer;
  Timer? _syncedTimer;
  bool _flushing = false;

  /// Bumped when an offline queue flush successfully syncs anything, so
  /// screens that merged optimistic rows can refetch the server page.
  int flushEpoch = 0;
  bool _started = false;

  bool online = true;
  bool syncing = false;
  bool justSynced = false;
  DateTime? lastSyncedAt;
  List<OutboxOp> ops = const [];

  int get pendingCount =>
      ops.where((o) => o.status != OutboxStatus.error).length;
  int get errorCount => ops.where((o) => o.status == OutboxStatus.error).length;

  List<Transaction> get pendingCreates {
    final out = <Transaction>[];
    for (final o in ops) {
      if (o.entity == OutboxEntity.transaction &&
          (o.action == OutboxAction.create ||
              o.action == OutboxAction.transfer) &&
          o.optimistic != null) {
        out.add(
          _withPending(
            o.optimistic!,
            o.status == OutboxStatus.syncing
                ? PendingState.syncing
                : o.status == OutboxStatus.error
                ? PendingState.error
                : PendingState.pending,
          ),
        );
      }
    }
    return out;
  }

  Map<String, Transaction> get pendingPatches {
    final map = <String, Transaction>{};
    for (final o in ops) {
      if (o.entity == OutboxEntity.transaction &&
          o.action == OutboxAction.update &&
          o.targetId != null &&
          o.optimistic != null) {
        map[o.targetId!] = _withPending(
          o.optimistic!,
          o.status == OutboxStatus.error
              ? PendingState.error
              : PendingState.pending,
        );
      }
    }
    return map;
  }

  Set<String> get deletedIds => ops
      .where(
        (o) =>
            o.entity == OutboxEntity.transaction &&
            o.action == OutboxAction.delete &&
            o.targetId != null,
      )
      .map((o) => o.targetId!)
      .toSet();

  /// Merge server page with optimistic outbox rows for the Activity list.
  List<Transaction> mergeTransactions(List<Transaction> server) {
    final deleted = deletedIds;
    final patches = pendingPatches;
    final creates = pendingCreates;

    final merged = <Transaction>[
      for (final tx in server)
        if (!deleted.contains(tx.id)) patches[tx.id] ?? tx,
    ];

    // Local creates sit at the top when sorted by newest.
    for (final c in creates.reversed) {
      if (!merged.any((t) => t.id == c.id)) merged.insert(0, c);
    }
    return merged;
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await _db.database;
      await _refreshOps();
    } catch (e, st) {
      debugPrint('SyncState start failed: $e\n$st');
    }

    try {
      final initial = await _connectivity.checkConnectivity();
      online = _isOnline(initial);
    } catch (_) {
      online = true;
    }
    notifyListeners();

    try {
      _sub = _connectivity.onConnectivityChanged.listen((results) {
        final next = _isOnline(results);
        final wasOffline = !online;
        online = next;
        notifyListeners();
        if (wasOffline && online) unawaited(flush());
      });
    } catch (e) {
      debugPrint('Connectivity listen failed: $e');
    }

    _retryTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (online) unawaited(flush());
    });

    if (online) unawaited(flush());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _retryTimer?.cancel();
    _syncedTimer?.cancel();
    super.dispose();
  }

  bool _isOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<void> _refreshOps() async {
    try {
      ops = await _outbox.all();
    } catch (e) {
      debugPrint('Outbox refresh failed: $e');
      ops = const [];
    }
    notifyListeners();
  }

  void _markSynced() {
    lastSyncedAt = DateTime.now();
    justSynced = true;
    notifyListeners();
    _syncedTimer?.cancel();
    _syncedTimer = Timer(const Duration(milliseconds: 2800), () {
      justSynced = false;
      notifyListeners();
    });
    unawaited(_db.setMeta('lastSyncedAt', lastSyncedAt!.toIso8601String()));
  }

  Future<void> _send(OutboxOp op) async {
    switch (op.method.toUpperCase()) {
      case 'POST':
        await api.post(op.path, body: withOpKey(op, op.payload));
      case 'PUT':
        await api.put(op.path, body: op.payload);
      case 'PATCH':
        await api.patch(op.path, body: op.payload);
      case 'DELETE':
        await api.delete(op.path);
      default:
        throw ApiError(0, 'Unknown outbox method ${op.method}');
    }
  }

  Future<void> flush() async {
    if (_flushing || !online) return;
    final queue = (await _outbox.all())
        .where((o) => o.status != OutboxStatus.error)
        .toList();
    if (queue.isEmpty) return;

    _flushing = true;
    syncing = true;
    notifyListeners();
    var anySynced = false;

    try {
      for (final op in queue) {
        if (!online) break;
        await _outbox.put(op.copyWith(status: OutboxStatus.syncing));
        await _refreshOps();
        try {
          await _send(op);
          await _outbox.delete(op.id);
          anySynced = true;
        } catch (err) {
          if (err is ApiError && err.isNetwork) {
            await _outbox.put(
              op.copyWith(status: OutboxStatus.pending, error: null),
            );
            break;
          }
          final message = err is ApiError ? err.message : 'Failed to sync';
          await _outbox.put(
            op.copyWith(
              status: OutboxStatus.error,
              attempts: op.attempts + 1,
              error: message,
            ),
          );
        }
        await _refreshOps();
      }
    } finally {
      _flushing = false;
      syncing = false;
      await _refreshOps();
      if (anySynced) {
        flushEpoch++;
        _markSynced();
      }
    }
  }

  /// Send now if we can, queue durably if we cannot.
  ///
  /// The op is the single description of the request - method, path, body - and
  /// both paths send it through `_send`. Callers used to pass a closure that
  /// restated the same call, which is how the online attempt ended up without
  /// the replay key the queued retry carried: two descriptions of one request,
  /// drifting apart.
  Future<QueueResult> attemptOrQueue(OutboxOp op) async {
    if (online) {
      try {
        await _send(op);
        return const QueueResult(queued: false);
      } catch (err) {
        if (err is ApiError && !err.isNetwork) rethrow;
        // The attempt may have reached the server before the connection
        // dropped. It carried the same op key, so the queued retry is a replay
        // the server recognises rather than a second movement.
      }
    }
    await _db.database;
    if (!_db.ready) {
      throw ApiError(
        0,
        'Could not reach the server, and offline storage is unavailable on this device.',
      );
    }
    try {
      await _outbox.put(op);
    } catch (_) {
      throw ApiError(
        0,
        'Could not reach the server, and offline storage is unavailable on this device.',
      );
    }
    await _refreshOps();
    if (online) unawaited(flush());
    return const QueueResult(queued: true);
  }

  OutboxOp _op({
    required OutboxEntity entity,
    required OutboxAction action,
    required String method,
    required String path,
    required String label,
    String? detail,
    String? id,
    String? targetId,
    Map<String, dynamic>? payload,
    Transaction? optimistic,
  }) => OutboxOp(
    id: id ?? newLocalId(),
    entity: entity,
    action: action,
    method: method,
    path: path,
    label: label,
    detail: detail,
    payload: payload,
    targetId: targetId,
    optimistic: optimistic,
    status: OutboxStatus.pending,
    attempts: 0,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  );

  // ── Transactions ─────────────────────────────────────────────────────────

  Future<QueueResult> saveTransaction(
    Map<String, dynamic> body,
    Transaction optimistic,
  ) {
    final transfer = optimistic.kind == TxKind.transfer;
    return attemptOrQueue(
      _op(
        id: optimistic.id,
        entity: OutboxEntity.transaction,
        action: transfer ? OutboxAction.transfer : OutboxAction.create,
        method: 'POST',
        path: '/transactions',
        label: transfer ? 'Transfer' : 'Create transaction',
        detail: optimistic.title,
        payload: body,
        optimistic: optimistic,
      ),
    );
  }

  Future<QueueResult> updateTransaction(
    String id,
    Map<String, dynamic> body,
    Transaction optimistic,
  ) async {
    if (isLocalId(id)) {
      final existing = await _outbox.get(id);
      if (existing != null) {
        await _outbox.put(
          existing.copyWith(
            payload: body,
            optimistic: optimistic,
            status: OutboxStatus.pending,
            error: null,
            detail: optimistic.title,
          ),
        );
        await _refreshOps();
        if (online) unawaited(flush());
        return const QueueResult(queued: true);
      }
    }
    return attemptOrQueue(
      _op(
        entity: OutboxEntity.transaction,
        action: OutboxAction.update,
        method: 'PUT',
        path: '/transactions/$id',
        label: 'Update transaction',
        detail: optimistic.title,
        targetId: id,
        payload: body,
        optimistic: optimistic,
      ),
    );
  }

  Future<QueueResult> deleteTransaction(String id) async {
    if (isLocalId(id)) {
      await _outbox.delete(id);
      await _refreshOps();
      return const QueueResult(queued: true);
    }
    return attemptOrQueue(
      _op(
        entity: OutboxEntity.transaction,
        action: OutboxAction.delete,
        method: 'DELETE',
        path: '/transactions/$id',
        label: 'Delete transaction',
        targetId: id,
      ),
    );
  }

  // ── Accounts ─────────────────────────────────────────────────────────────

  Future<QueueResult> saveAccount({
    required Map<String, dynamic> body,
    String? id,
    required String name,
  }) {
    if (id != null) {
      return attemptOrQueue(
        _op(
          entity: OutboxEntity.account,
          action: OutboxAction.update,
          method: 'PUT',
          path: '/accounts/$id',
          label: 'Update wallet',
          detail: name,
          targetId: id,
          payload: body,
        ),
      );
    }
    return attemptOrQueue(
      _op(
        entity: OutboxEntity.account,
        action: OutboxAction.create,
        method: 'POST',
        path: '/accounts',
        label: 'Create wallet',
        detail: name,
        payload: body,
      ),
    );
  }

  Future<QueueResult> deleteAccount(String id, {required String name}) {
    return attemptOrQueue(
      _op(
        entity: OutboxEntity.account,
        action: OutboxAction.delete,
        method: 'DELETE',
        path: '/accounts/$id',
        label: 'Delete wallet',
        detail: name,
        targetId: id,
      ),
    );
  }

  // ── Categories ───────────────────────────────────────────────────────────

  Future<QueueResult> saveCategory({
    required Map<String, dynamic> body,
    String? id,
    required String name,
  }) {
    if (id != null) {
      return attemptOrQueue(
        _op(
          entity: OutboxEntity.category,
          action: OutboxAction.update,
          method: 'PUT',
          path: '/categories/$id',
          label: 'Update category',
          detail: name,
          targetId: id,
          payload: body,
        ),
      );
    }
    return attemptOrQueue(
      _op(
        entity: OutboxEntity.category,
        action: OutboxAction.create,
        method: 'POST',
        path: '/categories',
        label: 'Create category',
        detail: name,
        payload: body,
      ),
    );
  }

  // ── Budgets / plans ──────────────────────────────────────────────────────

  Future<QueueResult> saveBudget({
    required Map<String, dynamic> body,
    String? id,
    required String name,
  }) {
    if (id != null) {
      return attemptOrQueue(
        _op(
          entity: OutboxEntity.budget,
          action: OutboxAction.update,
          method: 'PUT',
          path: '/budgets/$id',
          label: 'Update plan',
          detail: name,
          targetId: id,
          payload: body,
        ),
      );
    }
    return attemptOrQueue(
      _op(
        entity: OutboxEntity.budget,
        action: OutboxAction.create,
        method: 'POST',
        path: '/budgets',
        label: 'Create plan',
        detail: name,
        payload: body,
      ),
    );
  }

  Future<QueueResult> budgetAction({
    required String budgetId,
    required OutboxAction action,
    required String label,
    String? detail,
    Map<String, dynamic>? body,
  }) {
    final path = switch (action) {
      OutboxAction.fund => '/budgets/$budgetId/fund',
      OutboxAction.release => '/budgets/$budgetId/release',
      OutboxAction.adjust => '/budgets/$budgetId/adjust',
      OutboxAction.close => '/budgets/$budgetId/close',
      OutboxAction.reopen => '/budgets/$budgetId/reopen',
      OutboxAction.delete => '/budgets/$budgetId',
      _ => throw ArgumentError('Unsupported budget action $action'),
    };
    final method = action == OutboxAction.delete ? 'DELETE' : 'POST';
    return attemptOrQueue(
      _op(
        entity: OutboxEntity.budget,
        action: action,
        method: method,
        path: path,
        label: label,
        detail: detail,
        targetId: budgetId,
        payload: body,
      ),
    );
  }

  // ── Ledger ───────────────────────────────────────────────────────────────

  Future<QueueResult> saveLedger({
    required Map<String, dynamic> body,
    String? id,
    required String label,
  }) {
    if (id != null) {
      return attemptOrQueue(
        _op(
          entity: OutboxEntity.ledger,
          action: OutboxAction.update,
          method: 'PUT',
          path: '/ledger/$id',
          label: 'Update IOU',
          detail: label,
          targetId: id,
          payload: body,
        ),
      );
    }
    return attemptOrQueue(
      _op(
        entity: OutboxEntity.ledger,
        action: OutboxAction.create,
        method: 'POST',
        path: '/ledger',
        label: 'Create IOU',
        detail: label,
        payload: body,
      ),
    );
  }

  Future<QueueResult> ledgerPayment({
    required String entryId,
    required Map<String, dynamic> body,
    required String label,
  }) {
    return attemptOrQueue(
      _op(
        entity: OutboxEntity.ledger,
        action: OutboxAction.payment,
        method: 'POST',
        path: '/ledger/$entryId/payments',
        label: 'Record payment',
        detail: label,
        targetId: entryId,
        payload: body,
      ),
    );
  }

  Future<QueueResult> ledgerCancel(String id, {required String label}) {
    return attemptOrQueue(
      _op(
        entity: OutboxEntity.ledger,
        action: OutboxAction.cancel,
        method: 'POST',
        path: '/ledger/$id/cancel',
        label: 'Cancel IOU',
        detail: label,
        targetId: id,
        payload: const {},
      ),
    );
  }

  Future<QueueResult> deleteLedger(String id, {required String label}) {
    return attemptOrQueue(
      _op(
        entity: OutboxEntity.ledger,
        action: OutboxAction.delete,
        method: 'DELETE',
        path: '/ledger/$id',
        label: 'Delete IOU',
        detail: label,
        targetId: id,
      ),
    );
  }

  // ── Wishlist ─────────────────────────────────────────────────────────────

  Future<QueueResult> saveWishlist({
    required Map<String, dynamic> body,
    String? id,
    required String name,
  }) {
    if (id != null) {
      return attemptOrQueue(
        _op(
          entity: OutboxEntity.wishlist,
          action: OutboxAction.update,
          method: 'PUT',
          path: '/wishlist/$id',
          label: 'Update wishlist item',
          detail: name,
          targetId: id,
          payload: body,
        ),
      );
    }
    return attemptOrQueue(
      _op(
        entity: OutboxEntity.wishlist,
        action: OutboxAction.create,
        method: 'POST',
        path: '/wishlist',
        label: 'Add wishlist item',
        detail: name,
        payload: body,
      ),
    );
  }

  Future<QueueResult> wishlistBought(String id, {required String name}) {
    return attemptOrQueue(
      _op(
        entity: OutboxEntity.wishlist,
        action: OutboxAction.bought,
        method: 'POST',
        path: '/wishlist/$id/bought',
        label: 'Mark bought',
        detail: name,
        targetId: id,
        payload: const {},
      ),
    );
  }

  Future<QueueResult> wishlistPlan({
    required String id,
    required String name,
    required Map<String, dynamic> body,
  }) {
    return attemptOrQueue(
      _op(
        entity: OutboxEntity.wishlist,
        action: OutboxAction.plan,
        method: 'POST',
        path: '/wishlist/$id/plan',
        label: 'Turn wish into plan',
        detail: name,
        targetId: id,
        payload: body,
      ),
    );
  }

  Future<QueueResult> deleteWishlist(String id, {required String name}) {
    return attemptOrQueue(
      _op(
        entity: OutboxEntity.wishlist,
        action: OutboxAction.delete,
        method: 'DELETE',
        path: '/wishlist/$id',
        label: 'Delete wishlist item',
        detail: name,
        targetId: id,
      ),
    );
  }

  Future<void> retry(String id) async {
    final op = await _outbox.get(id);
    if (op == null) return;
    await _outbox.put(op.copyWith(status: OutboxStatus.pending, error: null));
    await _refreshOps();
    await flush();
  }

  Future<void> discard(String id) async {
    await _outbox.delete(id);
    await _refreshOps();
  }

  // ── Movements, undo, and the Money Doctor ────────────────────────────────
  //
  // Deliberately online-only. Undo removes a movement and the server re-proves
  // the books afterwards; queueing that would mean guessing at an outcome only
  // the server can work out, and showing a take-back that might not hold.

  Future<MovementsResponse> movements({int limit = 25}) async {
    final json = await api.get('/money/movements?limit=$limit');
    return MovementsResponse.fromJson(asMap(json));
  }

  /// Take a movement back. Removed, not reversed - a mistake leaves no trace.
  Future<String> undoMovement(String movementId) async {
    final json = await api.post(
      '/money/movements/${Uri.encodeComponent(movementId)}/undo',
      body: const {},
    );
    return asStr(asMap(json)['message'], 'Undone');
  }

  Future<MoneyHealth> moneyHealth({String? currency}) async {
    final json = await api.get(
      '/money/health${currency == null ? '' : '?currency=$currency'}',
    );
    return MoneyHealth.fromJson(asMap(json));
  }

  Future<MoneyHealth> repairMoney() async {
    await api.post('/money/health/fix', body: const {});
    return moneyHealth();
  }

  /// Record the gap between our figure and the bank's as a real movement.
  Future<void> settleDrift({
    required String accountId,
    required String categoryId,
  }) async {
    await api.post(
      '/money/drift/settle',
      body: {'accountId': accountId, 'categoryId': categoryId},
    );
  }

  // ── Payday rules ─────────────────────────────────────────────────────────

  Future<List<FundingRule>> fundingRules() async {
    final json = await api.get('/funding');
    return mapList(asMap(json)['items'], FundingRule.fromJson);
  }

  Future<FundingPreview> previewPayday(String ruleId, {String? accountId}) async {
    final json = await api.get(
      '/funding/$ruleId/preview${accountId == null ? '' : '?accountId=$accountId'}',
    );
    return FundingPreview.fromJson(asMap(json));
  }

  Future<FundingPreview> runPayday(String ruleId, {String? accountId}) async {
    final json = await api.post(
      '/funding/$ruleId/run',
      body: {'accountId': ?accountId},
    );
    return FundingPreview.fromJson(asMap(json));
  }

  Future<QueueResult> saveFundingRule({
    required Map<String, dynamic> body,
    String? id,
    required String name,
  }) {
    return attemptOrQueue(
      _op(
        entity: OutboxEntity.budget,
        action: id == null ? OutboxAction.create : OutboxAction.update,
        method: id == null ? 'POST' : 'PUT',
        path: id == null ? '/funding' : '/funding/$id',
        label: id == null ? 'Create payday rule' : 'Update payday rule',
        detail: name,
        targetId: id,
        payload: body,
      ),
    );
  }

  Future<QueueResult> deleteFundingRule(String id, {required String name}) {
    return attemptOrQueue(
      _op(
        entity: OutboxEntity.budget,
        action: OutboxAction.delete,
        method: 'DELETE',
        path: '/funding/$id',
        label: 'Delete payday rule',
        detail: name,
        targetId: id,
      ),
    );
  }

  /// Move a plan's reservation to another wallet, so the envelope follows the
  /// cash. There was no way to do this at all before.
  Future<QueueResult> movePlanHolding({
    required String budgetId,
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    required String planName,
  }) {
    return attemptOrQueue(
      _op(
        entity: OutboxEntity.budget,
        action: OutboxAction.fund,
        method: 'POST',
        path: '/budgets/$budgetId/move-holding',
        label: 'Move where money is held',
        detail: planName,
        targetId: budgetId,
        payload: {
          'fromAccountId': fromAccountId,
          'toAccountId': toAccountId,
          'amount': amount,
        },
      ),
    );
  }

  /// Move money straight from one plan to another, in one step.
  Future<QueueResult> movePlanMoney({
    required String fromBudgetId,
    required String toBudgetId,
    required double amount,
    required String label,
    bool raiseTarget = false,
  }) {
    return attemptOrQueue(
      _op(
        entity: OutboxEntity.budget,
        action: OutboxAction.fund,
        method: 'POST',
        path: '/budgets/$fromBudgetId/move',
        label: 'Move money between plans',
        detail: label,
        targetId: fromBudgetId,
        payload: {
          'toBudgetId': toBudgetId,
          'amount': amount,
          'raiseTarget': raiseTarget,
        },
      ),
    );
  }

  // ── Cache helpers used by DataState ──────────────────────────────────────

  Future<void> cacheAccounts(List<Account> accounts) async {
    try {
      await _db.putBlobList(
        CacheKeys.accounts,
        accounts.map(_accountJson).toList(),
      );
    } catch (e) {
      debugPrint('cacheAccounts failed: $e');
    }
  }

  Future<List<Account>?> readCachedAccounts() async {
    try {
      final list = await _db.getBlobList(CacheKeys.accounts);
      if (list == null) return null;
      return list
          .whereType<Map>()
          .map((m) => Account.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      debugPrint('readCachedAccounts failed: $e');
      return null;
    }
  }

  Future<void> cacheCategories(List<TxCategory> cats) async {
    try {
      await _db.putBlobList(
        CacheKeys.categories,
        cats.map(_categoryJson).toList(),
      );
    } catch (e) {
      debugPrint('cacheCategories failed: $e');
    }
  }

  Future<List<TxCategory>?> readCachedCategories() async {
    try {
      final list = await _db.getBlobList(CacheKeys.categories);
      if (list == null) return null;
      return list
          .whereType<Map>()
          .map((m) => TxCategory.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      debugPrint('readCachedCategories failed: $e');
      return null;
    }
  }

  Future<void> cacheDashboard(Map<String, dynamic> json) async {
    try {
      await _db.putBlob(CacheKeys.dashboard, json);
    } catch (e) {
      debugPrint('cacheDashboard failed: $e');
    }
  }

  Future<Map<String, dynamic>?> readCachedDashboard() async {
    try {
      return await _db.getBlob(CacheKeys.dashboard);
    } catch (e) {
      debugPrint('readCachedDashboard failed: $e');
      return null;
    }
  }

  Future<void> cacheTransactionPage(Map<String, dynamic> json) async {
    try {
      await _db.putBlob(CacheKeys.transactionsRecent, json);
    } catch (e) {
      debugPrint('cacheTransactionPage failed: $e');
    }
  }

  Future<Map<String, dynamic>?> readCachedTransactionPage() async {
    try {
      return await _db.getBlob(CacheKeys.transactionsRecent);
    } catch (e) {
      debugPrint('readCachedTransactionPage failed: $e');
      return null;
    }
  }

  Future<void> cacheBudgets(Map<String, dynamic> json) async {
    try {
      await _db.putBlob(CacheKeys.budgets, json);
    } catch (e) {
      debugPrint('cacheBudgets failed: $e');
    }
  }

  Future<Map<String, dynamic>?> readCachedBudgets() async {
    try {
      return await _db.getBlob(CacheKeys.budgets);
    } catch (e) {
      debugPrint('readCachedBudgets failed: $e');
      return null;
    }
  }

  Future<void> cacheSpendSources(Map<String, dynamic> json) async {
    try {
      await _db.putBlob(CacheKeys.spendSources, json);
    } catch (e) {
      debugPrint('cacheSpendSources failed: $e');
    }
  }

  Future<Map<String, dynamic>?> readCachedSpendSources() async {
    try {
      return await _db.getBlob(CacheKeys.spendSources);
    } catch (e) {
      debugPrint('readCachedSpendSources failed: $e');
      return null;
    }
  }

  Future<void> cacheNotifications(List<AppNotification> items) async {
    try {
      await _db.putBlobList(
        CacheKeys.notifications,
        items.map(_notificationJson).toList(),
      );
    } catch (e) {
      debugPrint('cacheNotifications failed: $e');
    }
  }

  Future<List<AppNotification>?> readCachedNotifications() async {
    try {
      final list = await _db.getBlobList(CacheKeys.notifications);
      if (list == null) return null;
      return list
          .whereType<Map>()
          .map((m) => AppNotification.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      debugPrint('readCachedNotifications failed: $e');
      return null;
    }
  }

  Future<void> cacheRecurring(List<RecurringRule> items) async {
    try {
      await _db.putBlobList(
        CacheKeys.recurring,
        items.map(_recurringJson).toList(),
      );
    } catch (e) {
      debugPrint('cacheRecurring failed: $e');
    }
  }

  Future<List<RecurringRule>?> readCachedRecurring() async {
    try {
      final list = await _db.getBlobList(CacheKeys.recurring);
      if (list == null) return null;
      return list
          .whereType<Map>()
          .map((m) => RecurringRule.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      debugPrint('readCachedRecurring failed: $e');
      return null;
    }
  }

  Future<void> cacheOutlookHistory(Map<String, dynamic> json) async {
    try {
      await _db.putBlob(CacheKeys.outlookHistory, json);
    } catch (e) {
      debugPrint('cacheOutlookHistory failed: $e');
    }
  }

  Future<Map<String, dynamic>?> readCachedOutlookHistory() async {
    try {
      return await _db.getBlob(CacheKeys.outlookHistory);
    } catch (e) {
      debugPrint('readCachedOutlookHistory failed: $e');
      return null;
    }
  }

  Future<void> cacheWishlist(Map<String, dynamic> json) async {
    try {
      await _db.putBlob(CacheKeys.wishlist, json);
    } catch (e) {
      debugPrint('cacheWishlist failed: $e');
    }
  }

  Future<Map<String, dynamic>?> readCachedWishlist() async {
    try {
      return await _db.getBlob(CacheKeys.wishlist);
    } catch (e) {
      debugPrint('readCachedWishlist failed: $e');
      return null;
    }
  }

  Future<void> cacheLedger(Map<String, dynamic> json) async {
    try {
      await _db.putBlob(CacheKeys.ledger, json);
    } catch (e) {
      debugPrint('cacheLedger failed: $e');
    }
  }

  Future<Map<String, dynamic>?> readCachedLedger() async {
    try {
      return await _db.getBlob(CacheKeys.ledger);
    } catch (e) {
      debugPrint('readCachedLedger failed: $e');
      return null;
    }
  }

  Future<DateTime?> cacheTime(String key) async {
    try {
      final ms = await _db.blobUpdatedAt(key);
      if (ms == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }
}

Transaction _withPending(Transaction tx, PendingState pending) => Transaction(
  id: tx.id,
  kind: tx.kind,
  amount: tx.amount,
  currency: tx.currency,
  date: tx.date,
  accountId: tx.accountId,
  tags: tx.tags,
  account: tx.account,
  transferAccountId: tx.transferAccountId,
  transferAccount: tx.transferAccount,
  categoryId: tx.categoryId,
  category: tx.category,
  budgetId: tx.budgetId,
  budget: tx.budget,
  budgetCycle: tx.budgetCycle,
  budgetSourceAccountId: tx.budgetSourceAccountId,
  budgetSourceAccount: tx.budgetSourceAccount,
  note: tx.note,
  payee: tx.payee,
  recurringRuleId: tx.recurringRuleId,
  pending: pending,
);

Map<String, dynamic> _accountJson(Account a) => {
  'id': a.id,
  'name': a.name,
  'type': a.type.wire,
  'currency': a.currency,
  'openingBalance': a.openingBalance,
  'balance': a.balance,
  'realBalance': a.realBalance,
  'lockedAmount': a.lockedAmount,
  'isDefault': a.isDefault,
  'archived': a.archived,
  if (a.icon != null) 'icon': a.icon,
  if (a.color != null) 'color': a.color,
  'isShared': a.isShared,
  if (a.householdId != null) 'householdId': a.householdId,
  if (a.accountNumber != null) 'accountNumber': a.accountNumber,
};

Map<String, dynamic> _categoryJson(TxCategory c) => {
  'id': c.id,
  'name': c.name,
  'kind': c.kind,
  'icon': c.icon,
  'color': c.color,
  'isDefault': c.isDefault,
  'archived': c.archived,
  if (c.transactionCount != null) 'transactionCount': c.transactionCount,
};

Map<String, dynamic>? _refJson(Ref? r) {
  if (r == null) return null;
  return {
    'id': r.id,
    'name': r.name,
    if (r.icon != null) 'icon': r.icon,
    if (r.color != null) 'color': r.color,
    if (r.currency != null) 'currency': r.currency,
    if (r.type != null) 'type': r.type,
  };
}

Map<String, dynamic> _notificationJson(AppNotification n) => {
  'id': n.id,
  'type': n.type,
  'message': n.message,
  if (n.link != null) 'link': n.link,
  'readFlag': n.readFlag,
  'createdAt': n.createdAt.toIso8601String(),
};

Map<String, dynamic> _recurringJson(RecurringRule r) => {
  'id': r.id,
  'name': r.name,
  'kind': r.kind.wire,
  'amount': r.amount,
  'currency': r.currency,
  'accountId': r.accountId,
  if (r.account != null) 'account': _refJson(r.account),
  if (r.categoryId != null) 'categoryId': r.categoryId,
  if (r.category != null) 'category': _refJson(r.category),
  if (r.budgetId != null) 'budgetId': r.budgetId,
  if (r.budget != null) 'budget': _refJson(r.budget),
  if (r.payee != null) 'payee': r.payee,
  if (r.note != null) 'note': r.note,
  'frequency': r.frequency.wire,
  'interval': r.interval,
  if (r.dayOfMonth != null) 'dayOfMonth': r.dayOfMonth,
  'nextRun': r.nextRun.toIso8601String(),
  if (r.endDate != null) 'endDate': r.endDate!.toIso8601String(),
  'autoPost': r.autoPost,
  'active': r.active,
  'postedCount': r.postedCount,
};
