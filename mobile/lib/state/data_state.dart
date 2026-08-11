import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/home_widget.dart';
import '../core/utils/format.dart';
import '../models/models.dart';
import '../models/outlook_history.dart';
import 'sync_state.dart';

/// A single fetch's lifecycle. The UI branches on `hasData` first so a refresh
/// never blanks a screen that already has content   the same behaviour SWR
/// gives the web app.
class Async<T> {
  const Async._({this.data, this.error, this.loading = false});

  const Async.idle() : this._();
  const Async.loading({T? previous}) : this._(data: previous, loading: true);
  const Async.data(T value) : this._(data: value);
  const Async.failed(Object err, {T? previous})
    : this._(data: previous, error: err);

  final T? data;
  final Object? error;
  final bool loading;

  bool get hasData => data != null;
  bool get hasError => error != null;

  String get errorMessage =>
      error is ApiError ? (error as ApiError).message : 'Something went wrong.';
}

/// Shared cache for the reference data almost every screen needs (accounts,
/// categories, budget spend sources) plus the dashboard payload. Screens with
/// their own paging   transactions, wishlist, ledger   fetch directly instead.
class DataState extends ChangeNotifier {
  DataState(this.api, {this.sync});

  final ApiClient api;
  final SyncState? sync;

  Async<DashboardData> dashboard = const Async.idle();
  Async<List<Account>> accounts = const Async.idle();
  Async<List<TxCategory>> categories = const Async.idle();
  Async<BudgetsResponse> budgets = const Async.idle();
  Async<List<BudgetSpendSource>> spendSources = const Async.idle();
  Async<List<RecurringRule>> recurring = const Async.idle();
  Async<List<AppNotification>> notifications = const Async.idle();
  Async<OutlookHistory> outlookHistory = const Async.idle();

  /// The currency the whole UI is scoped to. Multi-currency users switch it
  /// from the topbar badge; totals never mix currencies.
  String _activeCurrency = 'ETB';
  String get activeCurrency => _activeCurrency;

  List<String> get currencies {
    final list = dashboard.data?.currencies ?? const <String>[];
    return list.isEmpty ? [_activeCurrency] : list;
  }

  CurrencyBreakdown? get activeBreakdown {
    final all =
        dashboard.data?.currencyBreakdown ?? const <CurrencyBreakdown>[];
    if (all.length < 2) return null;
    for (final b in all) {
      if (b.currency == _activeCurrency) return b;
    }
    return null;
  }

  void setActiveCurrency(String currency) {
    if (_activeCurrency == currency) return;
    _activeCurrency = currency;
    notifyListeners();
  }

  /// Adopts the server's display currency the first time a dashboard lands.
  void _syncCurrencyFromDashboard(DashboardData d) {
    final list = d.currencies;
    if (list.isNotEmpty && !list.contains(_activeCurrency)) {
      _activeCurrency = d.displayCurrency ?? list.first;
    } else if (list.isEmpty && d.displayCurrency != null) {
      _activeCurrency = d.displayCurrency!;
    }
  }

  int get unreadCount =>
      notifications.data?.where((n) => !n.readFlag).length ?? 0;

  bool _isNetwork(Object e) => e is ApiError && e.isNetwork;

  Future<void> _load<T>(
    Async<T> Function() read,
    void Function(Async<T>) write,
    Future<T> Function() fetch, {
    bool force = false,
    Future<T?> Function()? fromCache,
  }) async {
    final current = read();
    if (!force && current.hasData) return;
    write(Async<T>.loading(previous: current.data));
    notifyListeners();

    // Seed from disk while the network round-trip is in flight.
    if (!current.hasData && fromCache != null) {
      try {
        final cached = await fromCache();
        if (cached != null && read().data == null) {
          write(Async<T>.loading(previous: cached));
          notifyListeners();
        }
      } catch (_) {}
    }

    try {
      final value = await fetch();
      write(Async<T>.data(value));
    } catch (e) {
      if (_isNetwork(e) && fromCache != null) {
        try {
          final cached = await fromCache();
          if (cached != null) {
            write(Async<T>.data(cached));
            notifyListeners();
            return;
          }
        } catch (_) {}
      }
      write(Async<T>.failed(e, previous: read().data ?? current.data));
    }
    notifyListeners();
  }

  Future<void> loadDashboard({bool force = false}) => _load<DashboardData>(
    () => dashboard,
    (v) {
      dashboard = v;
      if (v.data != null) {
        _syncCurrencyFromDashboard(v.data!);
        _publishHomeWidget(v.data!);
      }
    },
    () async {
      final json = await api.get<Map<String, dynamic>>('/dashboard');
      await sync?.cacheDashboard(json);
      return DashboardData.fromJson(json);
    },
    force: force,
    fromCache: () async {
      final json = await sync?.readCachedDashboard();
      if (json == null) return null;
      return DashboardData.fromJson(json);
    },
  );

  /// Feeds the home-screen widget from the dashboard payload.
  ///
  /// "Left to spend today" is the available balance   already net of what
  /// budget plans hold   spread evenly over the days left in the month. It is
  /// deliberately the simple figure rather than the outlook's projection: a
  /// widget has one line to be understood in.
  void _publishHomeWidget(DashboardData data) {
    final currency = data.displayCurrency ?? activeCurrency;
    final slice = data.currencyBreakdown
        .where((b) => b.currency == currency)
        .firstOrNull;

    final available = toNum(slice?.totalBalance ?? data.totalBalance);
    final month = slice?.month ?? data.month;

    final now = DateTime.now();
    final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day + 1;
    final perDay = daysLeft <= 0 ? available : available / daysLeft;

    HomeWidget.publish(
      remaining: formatMoney(perDay, currency: currency),
      caption: 'Left to spend today',
      spent:
          '${formatMoney(month.expense, currency: currency)} spent this month',
    );
  }

  Future<void> loadAccounts({bool force = false}) => _load<List<Account>>(
    () => accounts,
    (v) => accounts = v,
    () async {
      final items = mapItemsList(await api.get('/accounts'), Account.fromJson);
      await sync?.cacheAccounts(items);
      return items;
    },
    force: force,
    fromCache: () async {
      if (sync == null) return null;
      return sync!.readCachedAccounts();
    },
  );

  Future<void> loadCategories({bool force = false}) => _load<List<TxCategory>>(
    () => categories,
    (v) => categories = v,
    () async {
      final items = mapItemsList(
        await api.get('/categories'),
        TxCategory.fromJson,
      );
      await sync?.cacheCategories(items);
      return items;
    },
    force: force,
    fromCache: () async {
      if (sync == null) return null;
      return sync!.readCachedCategories();
    },
  );

  Future<void> loadBudgets({bool force = false, bool includeClosed = false}) =>
      _load<BudgetsResponse>(
        () => budgets,
        (v) => budgets = v,
        () async {
          final json = await api.get<Map<String, dynamic>>(
            '/budgets',
            query: includeClosed ? {'includeClosed': 'true'} : null,
          );
          await sync?.cacheBudgets(json);
          return BudgetsResponse.fromJson(json);
        },
        force: force,
        fromCache: () async {
          final json = await sync?.readCachedBudgets();
          if (json == null) return null;
          return BudgetsResponse.fromJson(json);
        },
      );

  Future<void> loadSpendSources({bool force = false}) =>
      _load<List<BudgetSpendSource>>(
        () => spendSources,
        (v) => spendSources = v,
        () async {
          final json = await api.get<Map<String, dynamic>>('/budgets/sources');
          await sync?.cacheSpendSources(json);
          return mapList(json['items'], BudgetSpendSource.fromJson);
        },
        force: force,
        fromCache: () async {
          final json = await sync?.readCachedSpendSources();
          if (json == null) return null;
          return mapList(json['items'], BudgetSpendSource.fromJson);
        },
      );

  /// History behind the monthly outlook   completed months, the surprise
  /// buffer, and repeating payees. Scoped to the active currency, so switching
  /// currency refetches.
  Future<void> loadOutlookHistory({bool force = false}) =>
      _load<OutlookHistory>(
        () => outlookHistory,
        (v) => outlookHistory = v,
        () async => OutlookHistory.fromJson(
          await api.get<Map<String, dynamic>>(
            '/analytics/outlook-history',
            query: {'currency': activeCurrency, 'months': '6'},
          ),
        ),
        force: force,
      );

  Future<void> loadRecurring({bool force = false}) =>
      _load<List<RecurringRule>>(
        () => recurring,
        (v) => recurring = v,
        () async =>
            mapItemsList(await api.get('/recurring'), RecurringRule.fromJson),
        force: force,
      );

  Future<void> loadNotifications({bool force = false}) =>
      _load<List<AppNotification>>(
        () => notifications,
        (v) => notifications = v,
        () async => mapItemsList(
          await api.get('/notifications'),
          AppNotification.fromJson,
        ),
        force: force,
      );

  /// Everything the app shell needs before the first frame of the dashboard.
  Future<void> primeAll() => Future.wait([
    loadDashboard(),
    loadAccounts(),
    loadCategories(),
    loadNotifications(),
    loadRecurring(),
    loadBudgets(),
  ]);

  /// Called after any write, so balances and plan pots never go stale.
  Future<void> refreshAfterWrite() => Future.wait([
    loadDashboard(force: true),
    loadAccounts(force: true),
    loadBudgets(force: true),
    loadSpendSources(force: true),
    loadRecurring(force: true),
  ]);

  Future<void> markNotificationRead(String id) async {
    await api.post('/notifications/$id/read');
    await loadNotifications(force: true);
  }

  Future<void> markAllNotificationsRead() async {
    await api.post('/notifications/read-all');
    await loadNotifications(force: true);
  }

  /// Accounts filtered to the active currency   what every picker should show.
  List<Account> get scopedAccounts => (accounts.data ?? const <Account>[])
      .where((a) => !a.archived && a.currency == _activeCurrency)
      .toList();

  List<TxCategory> categoriesOfKind(TxKind kind) =>
      (categories.data ?? const <TxCategory>[])
          .where(
            (c) =>
                !c.archived &&
                c.kind == (kind == TxKind.income ? 'INCOME' : 'EXPENSE'),
          )
          .toList();
}
