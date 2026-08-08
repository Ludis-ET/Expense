import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/dashboard.dart';
import '../models/finance.dart';
import '../offline/local_db.dart';
import '../offline/sync_engine.dart';

/// Accounts, categories, budgets, the dashboard and the transaction list.
///
/// Every read is cache-backed: a successful fetch is written to sqflite, and a
/// network failure falls back to whatever was stored. That makes a cold start
/// on a train show real numbers instead of an error, at the cost of them being
/// a little stale - which the sync bar says out loud.
///
/// Every write goes through the outbox. When there is a connection that is
/// indistinguishable from a direct call; when there is not, the change is
/// applied locally and replayed later.
class DataStore extends ChangeNotifier {
  DataStore({required this.api, required this.db, required this.sync});

  final ApiClient api;
  final LocalDb db;
  final SyncEngine sync;

  List<Account> accounts = const [];
  List<TxCategory> categories = const [];
  List<Budget> budgets = const [];
  DashboardData dashboard = const DashboardData.empty();

  List<Transaction> transactions = const [];
  int _page = 1;
  int _total = 0;
  bool loadingMore = false;

  /// Active ledger filters (website parity).
  String? txFrom;
  String? txTo;
  String? txKind;
  String? txCategoryId;
  String? txBudgetId;
  String? txQuery;
  String? txAccountId;

  void setTransactionFilters({
    String? from,
    String? to,
    String? kind,
    String? categoryId,
    String? budgetId,
    String? q,
    String? accountId,
    bool clearKind = false,
    bool clearCategory = false,
    bool clearBudget = false,
    bool clearQuery = false,
    bool clearAccount = false,
  }) {
    if (from != null) txFrom = from;
    if (to != null) txTo = to;
    if (clearKind) {
      txKind = null;
    } else if (kind != null) {
      txKind = kind.isEmpty ? null : kind;
    }
    if (clearCategory) {
      txCategoryId = null;
    } else if (categoryId != null) {
      txCategoryId = categoryId.isEmpty ? null : categoryId;
    }
    if (clearBudget) {
      txBudgetId = null;
    } else if (budgetId != null) {
      txBudgetId = budgetId.isEmpty ? null : budgetId;
    }
    if (clearQuery) {
      txQuery = null;
    } else if (q != null) {
      txQuery = q.isEmpty ? null : q;
    }
    if (clearAccount) {
      txAccountId = null;
    } else if (accountId != null) {
      txAccountId = accountId.isEmpty ? null : accountId;
    }
  }

  /// The wallet the user nominated as holding physical cash.
  String? cashAccountId;

  bool loading = false;
  String? error;

  /// True when the figures on screen came from the cache rather than the
  /// server. Drives the "showing saved data" note.
  bool servingFromCache = false;

  Iterable<TxCategory> get expenseCategories =>
      categories.where((c) => c.kind == 'EXPENSE' && !c.archived);
  Iterable<TxCategory> get incomeCategories =>
      categories.where((c) => c.kind == 'INCOME' && !c.archived);
  Iterable<Account> get activeAccounts => accounts.where((a) => !a.archived);
  Iterable<Budget> get spendableBudgets =>
      budgets.where((b) => b.state == 'ACTIVE' && b.started);

  bool get hasMoreTransactions => transactions.length < _total;

  Account? get cashAccount => accountById(cashAccountId);

  Account? accountById(String? id) =>
      id == null ? null : accounts.where((a) => a.id == id).firstOrNull;

  TxCategory? categoryById(String? id) =>
      id == null ? null : categories.where((c) => c.id == id).firstOrNull;

  // --- reads ----------------------------------------------------------------

  /// Paints the last known state before any network call.
  ///
  /// Called on sign-in so the first frame after the splash has real content;
  /// without it the app would show empty lists for as long as the API takes,
  /// which on a bad connection is the entire session.
  Future<void> hydrateFromCache() async {
    final results = await Future.wait([
      db.get('accounts'),
      db.get('categories'),
      db.get('budgets'),
      db.get('dashboard'),
      db.get('transactions'),
      db.get('profile'),
    ]);

    accounts = _decodeList(results[0], Account.fromJson) ?? accounts;
    categories = _decodeList(results[1], TxCategory.fromJson) ?? categories;
    budgets = _decodeList(results[2], Budget.fromJson) ?? budgets;

    final dash = results[3]?.data;
    if (dash is Map<String, dynamic>) dashboard = DashboardData.fromJson(dash);

    final txs = _decodeList(results[4], Transaction.fromJson);
    if (txs != null) {
      transactions = txs;
      _total = txs.length;
    }

    final profile = results[5]?.data;
    if (profile is Map<String, dynamic>) cashAccountId = profile['cashAccountId'] as String?;

    servingFromCache = accounts.isNotEmpty || transactions.isNotEmpty;
    notifyListeners();
  }

  List<T>? _decodeList<T>(CachedPayload? cached, T Function(Map<String, dynamic>) parse) {
    final data = cached?.data;
    if (data is! List) return null;
    return data.whereType<Map<String, dynamic>>().map(parse).toList();
  }

  Future<void> refreshAll() async {
    loading = true;
    error = null;
    notifyListeners();

    await Future.wait([
      _loadAccounts(),
      _loadCategories(),
      _loadBudgets(),
      loadDashboard(),
      loadProfile(),
      loadTransactions(reset: true),
    ]);

    loading = false;
    notifyListeners();
  }

  /// Fetch, cache on success, fall back to cache on a network failure.
  ///
  /// An [ApiException] is deliberately *not* caught here: a 403 or a 500 is a
  /// real answer from the server, and quietly showing stale data instead would
  /// hide a genuine problem.
  Future<void> _cached(
    String key,
    Future<Object?> Function() fetch,
    void Function(Object? data) apply,
  ) async {
    try {
      final data = await fetch();
      await db.put(key, data);
      apply(data);
      servingFromCache = false;
    } on NetworkException {
      final cached = await db.get(key);
      if (cached != null) {
        apply(cached.data);
        servingFromCache = true;
      }
    } on ApiException catch (e) {
      error ??= e.message;
    }
  }

  Future<void> _loadAccounts() => _cached(
        'accounts',
        () async => (await api.get('/accounts') as Map<String, dynamic>)['items'],
        (data) {
          if (data is List) {
            accounts = data
                .whereType<Map<String, dynamic>>()
                .map(Account.fromJson)
                .toList();
          }
        },
      );

  Future<void> _loadCategories() => _cached(
        'categories',
        () async => (await api.get('/categories') as Map<String, dynamic>)['items'],
        (data) {
          if (data is List) {
            categories = data
                .whereType<Map<String, dynamic>>()
                .map(TxCategory.fromJson)
                .toList();
          }
        },
      );

  Future<void> _loadBudgets() => _cached(
        'budgets',
        () async => (await api.get('/budgets') as Map<String, dynamic>)['items'],
        (data) {
          if (data is List) {
            budgets =
                data.whereType<Map<String, dynamic>>().map(Budget.fromJson).toList();
          }
        },
      );

  Future<void> loadDashboard() => _cached(
        'dashboard',
        () => api.get('/dashboard'),
        (data) {
          if (data is Map<String, dynamic>) dashboard = DashboardData.fromJson(data);
        },
      );

  Future<void> loadProfile() => _cached(
        'profile',
        () => api.get('/users/me'),
        (data) {
          if (data is Map<String, dynamic>) cashAccountId = data['cashAccountId'] as String?;
        },
      );

  Future<void> loadTransactions({bool reset = false}) async {
    if (reset) {
      _page = 1;
    } else {
      if (loadingMore || !hasMoreTransactions) return;
      loadingMore = true;
      notifyListeners();
      _page += 1;
    }

    try {
      final query = <String, dynamic>{
        'page': _page,
        'pageSize': 25,
        'sort': 'date_desc',
      };
      // Scope by profile currency when available (website currency view).
      // The API accepts currency; omitting it returns mixed wallets.
      if (txFrom != null) query['from'] = txFrom;
      if (txTo != null) query['to'] = txTo;
      if (txKind != null) query['kind'] = txKind;
      if (txCategoryId != null) query['categoryId'] = txCategoryId;
      if (txBudgetId != null) query['budgetId'] = txBudgetId;
      if (txQuery != null) query['q'] = txQuery;
      if (txAccountId != null) query['accountId'] = txAccountId;

      final data = await api.get('/transactions', query: query) as Map<String, dynamic>;

      final items = (data['items'] as List)
          .whereType<Map<String, dynamic>>()
          .map(Transaction.fromJson)
          .toList();

      _total = (data['total'] as num?)?.toInt() ?? items.length;
      transactions = reset ? items : [...transactions, ...items];
      servingFromCache = false;

      // Only the first page is cached: it is what an offline cold start needs,
      // and storing every page would grow without bound.
      if (reset) await db.put('transactions', data['items']);
    } on NetworkException {
      if (reset) {
        final cached = await db.get('transactions');
        if (cached?.data is List) {
          transactions = (cached!.data as List)
              .whereType<Map<String, dynamic>>()
              .map(Transaction.fromJson)
              .toList();
          _total = transactions.length;
          servingFromCache = true;
        }
      } else {
        _page -= 1;
      }
    } on ApiException catch (e) {
      error = e.message;
      if (!reset) _page -= 1;
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  Future<BudgetDetail?> fetchBudgetDetail(String id) async {
    try {
      final data = await api.get('/budgets/$id') as Map<String, dynamic>;
      return BudgetDetail.fromJson(data);
    } on NetworkException {
      return null;
    }
  }

  Future<BudgetDetail> fundBudget({
    required String budgetId,
    required String accountId,
    required double amount,
    required String date,
    String? note,
  }) async {
    final data = await api.post(
      '/budgets/$budgetId/fund',
      body: {
        'accountId': accountId,
        'amount': amount,
        'date': date,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    ) as Map<String, dynamic>;
    await _loadBudgets();
    await _loadAccounts();
    return BudgetDetail.fromJson(data);
  }

  Future<BudgetDetail> releaseBudget({
    required String budgetId,
    required String accountId,
    required double amount,
    required String date,
    String? note,
  }) async {
    final data = await api.post(
      '/budgets/$budgetId/release',
      body: {
        'accountId': accountId,
        'amount': amount,
        'date': date,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    ) as Map<String, dynamic>;
    await _loadBudgets();
    await _loadAccounts();
    return BudgetDetail.fromJson(data);
  }

  Future<void> closeBudget(String id) async {
    await api.post('/budgets/$id/close', body: {});
    await _loadBudgets();
  }

  Future<void> reopenBudget(String id) async {
    await api.post('/budgets/$id/reopen', body: {});
    await _loadBudgets();
  }

  Future<void> deleteBudget(String id) async {
    await api.delete('/budgets/$id');
    await _loadBudgets();
  }

  Future<bool> createTransfer({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    required String currency,
    required String date,
    String? note,
  }) {
    return createTransaction({
      'kind': 'TRANSFER',
      'amount': amount,
      'currency': currency,
      'accountId': fromAccountId,
      'transferAccountId': toAccountId,
      'date': date,
      if (note != null && note.isNotEmpty) 'note': note,
    });
  }

  Future<List<Transaction>> fetchTransactions({
    String? accountId,
    String? budgetId,
    int pageSize = 40,
    String sort = 'date_desc',
  }) async {
    final query = <String, dynamic>{
      'page': 1,
      'pageSize': pageSize,
      'sort': sort,
    };
    if (accountId != null) query['accountId'] = accountId;
    if (budgetId != null) query['budgetId'] = budgetId;
    try {
      final data = await api.get('/transactions', query: query) as Map<String, dynamic>;
      return (data['items'] as List)
          .whereType<Map<String, dynamic>>()
          .map(Transaction.fromJson)
          .toList();
    } on NetworkException {
      return const [];
    }
  }

  Future<Map<String, dynamic>> fetchWishlist({
    String? status,
    String? q,
    String sort = 'priority',
  }) async {
    final query = <String, dynamic>{'sort': sort};
    if (status != null && status != 'all') query['status'] = status;
    if (q != null && q.isNotEmpty) query['q'] = q;
    final data = await api.get('/wishlist', query: query) as Map<String, dynamic>;
    return data;
  }

  Future<Map<String, dynamic>> fetchLedger({String? kind, String status = 'open'}) async {
    final query = <String, dynamic>{'status': status};
    if (kind != null && kind != 'all') query['kind'] = kind;
    final data = await api.get('/ledger', query: query) as Map<String, dynamic>;
    return data;
  }

  Future<Map<String, dynamic>> fetchLedgerSummary() async {
    return await api.get('/ledger/summary') as Map<String, dynamic>;
  }

  // --- writes ---------------------------------------------------------------

  /// Records a transaction, queueing it if there is no connection.
  ///
  /// Returns true when it reached the server. False means it is saved locally
  /// and will go up on the next sync - the caller says so rather than claiming
  /// success outright.
  Future<bool> createTransaction(Map<String, dynamic> body) async {
    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}';

    // Optimistic row, so the ledger updates the instant you hit save whether
    // or not there is signal.
    _insertOptimistic(localId, body);

    try {
      final sent = await sync.enqueue(OutboxKind.transactionCreate, body, localId: localId);
      if (sent) await refreshAfterLedgerChange();
      return sent;
    } on ApiException {
      transactions = transactions.where((t) => t.id != localId).toList();
      if (_total > 0) _total -= 1;
      notifyListeners();
      rethrow;
    }
  }

  void _insertOptimistic(String localId, Map<String, dynamic> body) {
    final kind = body['kind'] as String? ?? 'EXPENSE';
    final category = categoryById(body['categoryId'] as String?);
    final account = accountById(body['accountId'] as String?);

    transactions = [
      Transaction(
        id: localId,
        kind: kind,
        amount: '${body['amount']}',
        currency: body['currency'] as String? ?? 'ETB',
        date: DateTime.tryParse('${body['date']}')?.toLocal() ?? DateTime.now(),
        payee: body['payee'] as String?,
        note: body['note'] as String?,
        accountName: account?.name,
        categoryName: category?.name,
        categoryColor: category?.color,
        tags: const ['pending'],
        pendingSync: true,
      ),
      ...transactions,
    ];
    _total += 1;
    notifyListeners();
  }

  Future<bool> deleteTransaction(String id) async {
    // A row that never reached the server can just disappear locally.
    if (id.startsWith('local-')) {
      transactions = transactions.where((t) => t.id != id).toList();
      notifyListeners();
      return true;
    }

    transactions = transactions.where((t) => t.id != id).toList();
    notifyListeners();

    final sent = await sync.enqueue(OutboxKind.transactionDelete, {'id': id});
    if (sent) await refreshAfterLedgerChange();
    return sent;
  }

  Future<bool> setCashAccount(String? accountId) async {
    cashAccountId = accountId;
    notifyListeners();
    return sync.enqueue(OutboxKind.cashAccount, {'cashAccountId': accountId});
  }

  Future<bool> setAccountNumber(String accountId, String? accountNumber) async {
    final sent = await sync.enqueue(
      OutboxKind.accountNumber,
      {'id': accountId, 'accountNumber': accountNumber},
    );
    if (sent) await _loadAccounts();
    notifyListeners();
    return sent;
  }

  /// Anything that moves money invalidates balances, plan pots and the home
  /// figures at once - they are all derived from the same ledger.
  Future<void> refreshAfterLedgerChange() async {
    await Future.wait([
      _loadAccounts(),
      _loadBudgets(),
      loadDashboard(),
      loadTransactions(reset: true),
    ]);
    notifyListeners();
  }

  /// Drops everything held for the signed-out account.
  void reset() {
    accounts = const [];
    categories = const [];
    budgets = const [];
    transactions = const [];
    dashboard = const DashboardData.empty();
    cashAccountId = null;
    servingFromCache = false;
    _page = 1;
    _total = 0;
    notifyListeners();
  }
}
