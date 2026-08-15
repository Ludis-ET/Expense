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

  /// History behind the monthly outlook — completed months, the surprise
  /// buffer, and repeating payees. Scoped to the active currency, so switching
  /// currency refetches.
  Future<void> loadOutlookHistory({bool force = false}) =>
      _load<OutlookHistory>(
        () => outlookHistory,
        (v) => outlookHistory = v,
        () async {
          final json = await api.get<Map<String, dynamic>>(
            '/analytics/outlook-history',
            query: {'currency': activeCurrency, 'months': '6'},
          );
          await sync?.cacheOutlookHistory({
            ...json,
            '_cacheCurrency': activeCurrency,
          });
          return OutlookHistory.fromJson(json);
        },
        force: force,
        fromCache: () async {
          final json = await sync?.readCachedOutlookHistory();
          if (json == null) return null;
          final cachedCurrency = json['_cacheCurrency'] as String?;
          if (cachedCurrency != null && cachedCurrency != activeCurrency) {
            return null;
          }
          return OutlookHistory.fromJson(json);
        },
      );

  Future<void> loadRecurring({bool force = false}) =>
      _load<List<RecurringRule>>(
        () => recurring,
        (v) => recurring = v,
        () async {
          final items =
              mapItemsList(await api.get('/recurring'), RecurringRule.fromJson);
          await sync?.cacheRecurring(items);
          return items;
        },
        force: force,
        fromCache: () async {
          if (sync == null) return null;
          return sync!.readCachedRecurring();
        },
      );

  Future<void> loadNotifications({bool force = false}) =>
      _load<List<AppNotification>>(
        () => notifications,
        (v) => notifications = v,
        () async {
          final items = mapItemsList(
            await api.get('/notifications'),
            AppNotification.fromJson,
          );
          await sync?.cacheNotifications(items);
          return items;
        },
        force: force,
        fromCache: () async {
          if (sync == null) return null;
          return sync!.readCachedNotifications();
        },
      );

  /// Everything the app shell needs before the first frame of the dashboard.
  Future<void> primeAll() => Future.wait([
        loadDashboard(),
        loadAccounts(),
        loadCategories(),
        loadNotifications(),
        loadRecurring(),
        loadBudgets(),
        loadSpendSources(),
      ]);

  /// Called after any write, so balances and plan pots never go stale.
  /// Reload everything a write can have changed.
  ///
  /// This used to fan out into five parallel requests, and each of those
  /// handlers independently rebuilt the server's money snapshot - five
  /// aggregate queries apiece. Saving one transaction cost six round trips and
  /// about twenty-five aggregates, which is what made the app feel slow on
  /// mobile data.
  ///
  /// `/sync` returns the same five payloads from one snapshot. The fan-out
  /// stays as the fallback: an older server without the route 404s, and there
  /// is no reason to make the app unusable over a deployment ordering.
  Future<void> refreshAfterWrite() async {
    try {
      final json = await api.get<Map<String, dynamic>>(
        '/sync',
        query: {'currency': _activeCurrency},
      );
      await _applySync(json);
      return;
    } on ApiError catch (e) {
      if (e.status != 404) rethrow;
    }
    await _refreshIndividually();
  }

  Future<void> _refreshIndividually() => Future.wait([
        loadDashboard(force: true),
        loadAccounts(force: true),
        loadBudgets(force: true),
        loadSpendSources(force: true),
        loadRecurring(force: true),
      ]);

  /// Unpacks a `/sync` body into the five slots, caching each exactly as its
  /// own loader would so offline reads keep working.
  Future<void> _applySync(Map<String, dynamic> json) async {
    final dashboardJson = asMap(json['dashboard']);
    final accountsJson = json['accounts'];
    final budgetsJson = asMap(json['budgets']);
    final sourcesJson = asMap(json['sources']);
    final recurringJson = json['recurring'];

    final dashboardData = DashboardData.fromJson(dashboardJson);
    final accountItems = mapItemsList(accountsJson, Account.fromJson);
    final budgetsData = BudgetsResponse.fromJson(budgetsJson);
    final sourceItems = mapList(sourcesJson['items'], BudgetSpendSource.fromJson);
    final recurringItems = mapItemsList(recurringJson, RecurringRule.fromJson);

    dashboard = Async.data(dashboardData);
    accounts = Async.data(accountItems);
    budgets = Async.data(budgetsData);
    spendSources = Async.data(sourceItems);
    recurring = Async.data(recurringItems);

    _syncCurrencyFromDashboard(dashboardData);
    _publishHomeWidget(dashboardData);
    notifyListeners();

    await Future.wait([
      sync?.cacheDashboard(dashboardJson) ?? Future.value(),
      sync?.cacheAccounts(accountItems) ?? Future.value(),
      sync?.cacheBudgets(budgetsJson) ?? Future.value(),
      sync?.cacheSpendSources(sourcesJson) ?? Future.value(),
      sync?.cacheRecurring(recurringItems) ?? Future.value(),
    ]);
  }

  Future<void> markNotificationRead(String id) async {
    final current = notifications.data;
    if (current != null) {
      final next = [
        for (final n in current)
          if (n.id == id)
            AppNotification(
              id: n.id,
              type: n.type,
              message: n.message,
              link: n.link,
              readFlag: true,
              createdAt: n.createdAt,
            )
          else
            n,
      ];
      notifications = Async.data(next);
      notifyListeners();
      await sync?.cacheNotifications(next);
    }
    try {
      await api.post('/notifications/$id/read');
    } on ApiError catch (e) {
      if (!e.isNetwork) rethrow;
      // Stay optimistic offline; server will catch up next online load.
    }
  }

  Future<void> markAllNotificationsRead() async {
    final current = notifications.data;
    if (current != null) {
      final next = [
        for (final n in current)
          AppNotification(
            id: n.id,
            type: n.type,
            message: n.message,
            link: n.link,
            readFlag: true,
            createdAt: n.createdAt,
          ),
      ];
      notifications = Async.data(next);
      notifyListeners();
      await sync?.cacheNotifications(next);
    }
    try {
      await api.post('/notifications/read-all');
    } on ApiError catch (e) {
      if (!e.isNetwork) rethrow;
    }
  }

  /// Accounts filtered to the active currency   what every picker should show.
  List<Account> get scopedAccounts => (accounts.data ?? const <Account>[])
      .where((a) => !a.archived && a.currency == _activeCurrency)
      .toList();

  /// Every live wallet, whatever it holds.
  ///
  /// Only the transfer sheet wants this. Moving your own money between a birr
  /// wallet and a dollar one is an ordinary thing to do and the server has
  /// always recorded both figures   but a picker scoped to one currency could
  /// never offer the other side, so the flow was unreachable from the app.
  List<Account> get transferableAccounts =>
      (accounts.data ?? const <Account>[]).where((a) => !a.archived).toList();

  List<TxCategory> categoriesOfKind(TxKind kind) =>
      (categories.data ?? const <TxCategory>[])
          .where(
            (c) =>
                !c.archived &&
                c.kind == (kind == TxKind.income ? 'INCOME' : 'EXPENSE'),
          )
          .toList();
}
