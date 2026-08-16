import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/layout.dart';
import '../../core/utils/format.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../state/sync_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/sync_ui.dart';
import '../../widgets/ui.dart';
import '../recurring/recurring_screen.dart';
import '../shell/app_shell.dart';
import 'export_sheet.dart';
import 'transaction_detail.dart';
import 'transaction_list.dart';

/// Sort options offered by `listTransactionsQuery`.
enum TxSort {
  dateDesc('date_desc', 'Newest first'),
  dateAsc('date_asc', 'Oldest first'),
  amountDesc('amount_desc', 'Largest first'),
  amountAsc('amount_asc', 'Smallest first');

  const TxSort(this.wire, this.label);
  final String wire;
  final String label;
}

/// The activity screen: search, filters, day-grouped rows, endless scroll.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _scroll = ScrollController();
  final _searchController = TextEditingController();

  final List<Transaction> _items = [];
  int _page = 1;
  int _total = 0;

  /// Per-day spend and income for the filter currently on screen.
  ///
  /// Comes down with the page rather than from its own request: a separate
  /// fetch could answer for a different filter than the list, which is the one
  /// thing these figures must never do.
  RangeAverages? _averages;
  bool _loading = false;
  bool _initialised = false;
  Object? _error;
  Timer? _debounce;

  /// Combined write/flush epoch last handled by `_reload`.
  int _seenEpoch = -1;

  // Filters — Activity opens on the current calendar month by default.
  String _query = '';
  TxKind? _kind;
  String? _accountId;
  String? _categoryId;
  DateTime? _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime? _to = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  TxSort _sort = TxSort.dateDesc;

  static const _pageSize = 25;

  void _applyDefaultMonth() {
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);
  }

  bool get _isDefaultMonthRange {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month, now.day);
    return _from != null &&
        _to != null &&
        _from!.year == start.year &&
        _from!.month == start.month &&
        _from!.day == start.day &&
        _to!.year == end.year &&
        _to!.month == end.month &&
        _to!.day == end.day;
  }

  int get _activeFilterCount => [
    _kind != null,
    _accountId != null,
    _categoryId != null,
    (_from != null || _to != null) && !_isDefaultMonthRange,
    _sort != TxSort.dateDesc,
  ].where((x) => x).length;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 500) {
        _loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final data = context.read<DataState>();
      data.loadAccounts();
      data.loadCategories();
      _reload();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _query4(int page) => {
    'page': page,
    'pageSize': _pageSize,
    'sort': _sort.wire,
    'currency': context.read<DataState>().activeCurrency,
    if (_query.trim().isNotEmpty) 'q': _query.trim(),
    if (_kind != null) 'kind': _kind!.wire,
    if (_accountId != null) 'accountId': _accountId,
    if (_categoryId != null) 'categoryId': _categoryId,
    if (_from != null) 'from': isoDate(_from!),
    if (_to != null) 'to': isoDate(_to!),
  };

  /// The active filters, minus paging and minus the range.
  ///
  /// The export sheet picks its own span - that is the one thing it asks - so
  /// `from`/`to` are deliberately left out here and everything else carries
  /// across untouched.
  Map<String, dynamic> _exportFilters() => {
    'currency': context.read<DataState>().activeCurrency,
    if (_query.trim().isNotEmpty) 'q': _query.trim(),
    if (_kind != null) 'kind': _kind!.wire,
    if (_accountId != null) 'accountId': _accountId,
    if (_categoryId != null) 'categoryId': _categoryId,
  };

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
    });
    final sync = context.read<SyncState>();
    try {
      final json = await context.read<ApiClient>().get<Map<String, dynamic>>(
        '/transactions',
        query: _query4(1),
      );
      await sync.cacheTransactionPage(json);
      final page = TransactionPage.fromJson(json);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _total = page.total;
        _averages = page.averages;
        _loading = false;
        _initialised = true;
      });
    } catch (e) {
      if (!mounted) return;
      // Fall back to cached page + outbox when offline.
      if (e is ApiError && e.isNetwork) {
        final cached = await sync.readCachedTransactionPage();
        if (cached != null) {
          final page = TransactionPage.fromJson(cached);
          setState(() {
            _items
              ..clear()
              ..addAll(page.items);
            _total = page.total;
            _averages = page.averages;
            _loading = false;
            _initialised = true;
            _error = null;
          });
          return;
        }
      }
      setState(() {
        _error = e;
        _loading = false;
        _initialised = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _items.length >= _total) return;
    setState(() => _loading = true);
    try {
      final json = await context.read<ApiClient>().get<Map<String, dynamic>>(
        '/transactions',
        query: _query4(_page + 1),
      );
      final page = TransactionPage.fromJson(json);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _total = page.total;
        _page += 1;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _query = value);
      _reload();
    });
  }

  void _clearFilters() {
    setState(() {
      _kind = null;
      _accountId = null;
      _categoryId = null;
      _applyDefaultMonth();
      _sort = TxSort.dateDesc;
    });
    _reload();
  }

  /// Groups rows under "Today" / "Yesterday" / a date, like the web list.
  List<(String, List<Transaction>)> _groupedOf(List<Transaction> items) {
    final out = <(String, List<Transaction>)>[];
    for (final tx in items) {
      final label = dayLabel(tx.date);
      if (out.isNotEmpty && out.last.$1 == label) {
        out.last.$2.add(tx);
      } else {
        out.add((label, [tx]));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final prefs = context.watch<PrefsState>();
    final data = context.watch<DataState>();
    final sync = context.watch<SyncState>();
    final shell = AppShell.of(context);
    final items = sync.mergeTransactions(_items);

    final epoch = data.writeEpoch + sync.flushEpoch;
    if (_initialised && epoch != _seenEpoch) {
      _seenEpoch = epoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    } else if (!_initialised || _seenEpoch < 0) {
      _seenEpoch = epoch;
    }

    String money(Object? v, String c) => prefs.money(v, currency: c);

    final groups = _groupedOf(items);
    final income = items
        .where((x) => x.kind == TxKind.income)
        .fold<double>(0, (s, x) => s + x.value);
    final expense = items
        .where((x) => x.kind == TxKind.expense)
        .fold<double>(0, (s, x) => s + x.value);

    return RefreshIndicator(
      onRefresh: _reload,
      color: t.primary,
      backgroundColor: t.surface,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                PageHeader(
                  title: 'Activity',
                  description:
                      'Every income, expense and transfer in '
                      '${data.activeCurrency}. Filters narrow the list without '
                      'changing your balances.',
                  action: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HeaderAction(
                        icon: Icons.ios_share_rounded,
                        label: 'Export',
                        iconOnly: true,
                        primary: false,
                        // The sheet inherits whatever is filtered right now, so
                        // the file matches the list rather than guessing.
                        onTap: () => showExportSheet(
                          context,
                          filters: _exportFilters(),
                        ),
                      ),
                      const GapX(S.xs),
                      HeaderAction(
                        icon: Icons.repeat_rounded,
                        label: 'Recurring',
                        primary: false,
                        onTap: () => shell.push(const RecurringScreen()),
                      ),
                    ],
                  ),
                ),
                const OfflineBanner(),
                AppTextField(
                  controller: _searchController,
                  placeholder: 'Search payee, note or tag',
                  prefixIcon: Icons.search,
                  textCapitalization: TextCapitalization.none,
                  onChanged: _onSearch,
                  suffix: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close, size: 17, color: t.mutedForeground),
                          onPressed: () {
                            _searchController.clear();
                            _onSearch('');
                          },
                        ),
                ),
                const Gap(S.md),
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _FilterChip(
                              label: _kind?.label ?? 'All kinds',
                              active: _kind != null,
                              icon: Icons.filter_alt_outlined,
                              onTap: _pickKind,
                            ),
                            const GapX(S.sm),
                            _FilterChip(
                              label: _accountId == null
                                  ? 'Account'
                                  : data.scopedAccounts
                                            .where((a) => a.id == _accountId)
                                            .firstOrNull
                                            ?.name ??
                                        'Account',
                              active: _accountId != null,
                              icon: Icons.account_balance_wallet_outlined,
                              onTap: _pickAccount,
                            ),
                            const GapX(S.sm),
                            _FilterChip(
                              label: _categoryId == null
                                  ? 'Category'
                                  : (data.categories.data ?? const <TxCategory>[])
                                            .where((c) => c.id == _categoryId)
                                            .firstOrNull
                                            ?.name ??
                                        'Category',
                              active: _categoryId != null,
                              icon: Icons.sell_outlined,
                              onTap: _pickCategory,
                            ),
                            const GapX(S.sm),
                            _FilterChip(
                              label: _from == null && _to == null
                                  ? 'Dates'
                                  : '${_from == null ? '…' : formatDayMonth(_from)} → '
                                        '${_to == null ? '…' : formatDayMonth(_to)}',
                              active: _from != null || _to != null,
                              icon: Icons.date_range_outlined,
                              onTap: _pickDates,
                            ),
                            const GapX(S.sm),
                            _FilterChip(
                              label: _sort.label,
                              active: _sort != TxSort.dateDesc,
                              icon: Icons.sort,
                              onTap: _pickSort,
                            ),
                            if (_activeFilterCount > 0) ...[
                              const GapX(S.sm),
                              _FilterChip(
                                label: 'Clear',
                                active: false,
                                icon: Icons.close,
                                onTap: _clearFilters,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(S.md),
                if (items.isNotEmpty)
                  Row(
                    children: [
                      Expanded(
                        child: _Totals(
                          label: 'In',
                          value: money(income, data.activeCurrency),
                          color: t.success,
                          icon: Icons.south_west_rounded,
                        ),
                      ),
                      const GapX(S.sm),
                      Expanded(
                        child: _Totals(
                          label: 'Out',
                          value: money(expense, data.activeCurrency),
                          color: t.danger,
                          icon: Icons.north_east_rounded,
                        ),
                      ),
                      const GapX(S.sm),
                      Expanded(
                        child: _Totals(
                          label: 'Shown',
                          value: '${items.length}/$_total',
                          color: t.mutedForeground,
                          icon: Icons.list_alt_outlined,
                        ),
                      ),
                    ],
                  ),

                // Per day, for exactly the filter above. One line, no card -
                // the chips already say which range it covers.
                if (_averages != null) ...[
                  const Gap(S.sm),
                  _PerDayStrip(
                    averages: _averages!,
                    money: (v) => money(v, data.activeCurrency),
                  ),
                ],

                const Gap(S.md),
              ]),
            ),
          ),

          if (!_initialised)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: S.lg),
                child: PageLoader(rows: 6, hero: false),
              ),
            )
          else if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.lg),
                child: ErrorState(
                  message: _error is ApiError
                      ? (_error as ApiError).message
                      : 'Could not load your transactions.',
                  onRetry: _reload,
                ),
              ),
            )
          else if (items.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.lg),
                child: EmptyState(
                  icon: Icons.receipt_long_outlined,
                  art: EmptyArt.ledger,
                  title: _activeFilterCount > 0 || _query.isNotEmpty
                      ? 'Nothing matches those filters'
                      : 'No transactions yet',
                  description: _activeFilterCount > 0 || _query.isNotEmpty
                      ? 'Try widening the date range or clearing a filter.'
                      : 'Add your first income or expense to get started.',
                  action: AppButton(
                    label: _activeFilterCount > 0 ? 'Clear filters' : 'Add transaction',
                    icon: _activeFilterCount > 0 ? Icons.close : Icons.add,
                    size: BtnSize.sm,
                    onPressed: _activeFilterCount > 0
                        ? _clearFilters
                        : () => shell.openAddTransaction(),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: S.lg),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, i) {
                  final (label, rows) = groups[i];
                  final dayTotal = rows.fold<double>(
                    0,
                    (s, x) => s + (x.kind == TxKind.expense ? x.value : 0),
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: S.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                          child: Row(
                            children: [
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: AppType.label,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                  color: t.mutedForeground,
                                ),
                              ),
                              const Spacer(),
                              if (dayTotal > 0)
                                Muted('−${money(dayTotal, data.activeCurrency)}', size: 11.5),
                            ],
                          ),
                        ),
                        AppCard(
                          padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.xxs),
                          child: TransactionList(
                            items: rows,
                            money: money,
                            animate: false,
                            showDate: false,
                            onTap: (tx) async {
                              final changed = await showTransactionDetail(context, tx);
                              if (changed == true) _reload();
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                }, childCount: groups.length),
              ),
            ),

          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, ShellLayout.bottomClearance(context)),
              child: items.isEmpty
                  ? const SizedBox.shrink()
                  : items.length >= _total
                  ? Center(child: Muted('That is all $_total.', size: 11.5))
                  : Center(
                      child: _loading
                          ? const Padding(padding: EdgeInsets.all(S.sm), child: BouncingDots())
                          : AppButton(
                              label: 'Load more',
                              variant: BtnVariant.outline,
                              size: BtnSize.sm,
                              onPressed: _loadMore,
                            ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickKind() async {
    final picked = await showAppSheet<String>(
      context,
      title: 'Kind',
      scrollable: false,
      builder: (ctx) => _OptionList(
        options: [('', 'All kinds'), for (final k in TxKind.values) (k.wire, k.label)],
        selected: _kind?.wire ?? '',
      ),
    );
    if (picked == null) return;
    setState(() => _kind = picked.isEmpty ? null : TxKind.parse(picked));
    _reload();
  }

  Future<void> _pickAccount() async {
    final accounts = context.read<DataState>().scopedAccounts;
    final picked = await showAppSheet<String>(
      context,
      title: 'Account',
      builder: (ctx) => _OptionList(
        options: [('', 'All accounts'), for (final a in accounts) (a.id, a.name)],
        selected: _accountId ?? '',
      ),
    );
    if (picked == null) return;
    setState(() => _accountId = picked.isEmpty ? null : picked);
    _reload();
  }

  Future<void> _pickCategory() async {
    final categories = (context.read<DataState>().categories.data ?? const <TxCategory>[])
        .where((c) => !c.archived)
        .toList();
    final picked = await showAppSheet<String>(
      context,
      title: 'Category',
      builder: (ctx) => _OptionList(
        options: [('', 'All categories'), for (final c in categories) (c.id, c.name)],
        selected: _categoryId ?? '',
      ),
    );
    if (picked == null) return;
    setState(() => _categoryId = picked.isEmpty ? null : picked);
    _reload();
  }

  Future<void> _pickSort() async {
    final picked = await showAppSheet<String>(
      context,
      title: 'Sort by',
      scrollable: false,
      builder: (ctx) => _OptionList(
        options: [for (final s in TxSort.values) (s.wire, s.label)],
        selected: _sort.wire,
      ),
    );
    if (picked == null) return;
    setState(() => _sort = TxSort.values.firstWhere((s) => s.wire == picked));
    _reload();
  }

  Future<void> _pickDates() async {
    var from = _from;
    var to = _to;
    final applied = await showAppSheet<bool>(
      context,
      title: 'Date range',
      scrollable: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.of(ctx).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in _datePresets())
                    ActionChip(
                      label: Text(preset.$1, style: const TextStyle(fontSize: AppType.label)),
                      onPressed: () => setSheet(() {
                        from = preset.$2;
                        to = preset.$3;
                      }),
                    ),
                ],
              ),
              const Gap(S.lg),
              DateField(
                label: 'From',
                value: from,
                allowClear: true,
                onChanged: (d) => setSheet(() => from = d),
              ),
              const Gap(S.md),
              DateField(
                label: 'To',
                value: to,
                allowClear: true,
                onChanged: (d) => setSheet(() => to = d),
              ),
              const Gap(S.xl),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Clear',
                      variant: BtnVariant.outline,
                      expand: true,
                      onPressed: () {
                        from = null;
                        to = null;
                        Navigator.pop(ctx, true);
                      },
                    ),
                  ),
                  const GapX(S.md),
                  Expanded(
                    child: AppButton(
                      label: 'Apply',
                      expand: true,
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (applied != true) return;
    setState(() {
      _from = from;
      _to = to;
    });
    _reload();
  }

  static List<(String, DateTime, DateTime)> _datePresets() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [
      ('This month', DateTime(now.year, now.month, 1), today),
      ('Last month', DateTime(now.year, now.month - 1, 1), DateTime(now.year, now.month, 0)),
      ('Last 7 days', today.subtract(const Duration(days: 6)), today),
      ('Last 30 days', today.subtract(const Duration(days: 29)), today),
      ('This year', DateTime(now.year, 1, 1), today),
    ];
  }
}

class _OptionList extends StatelessWidget {
  const _OptionList({required this.options, required this.selected});

  final List<(String, String)> options;
  final String selected;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: EdgeInsets.only(bottom: 16 + MediaQuery.of(context).padding.bottom),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: S.md),
        itemCount: options.length,
        itemBuilder: (context, i) {
          final isSelected = options[i].$1 == selected;
          return ListTile(
            onTap: () => Navigator.pop(context, options[i].$1),
            selected: isSelected,
            selectedTileColor: t.primary.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
            title: Text(
              options[i].$2,
              style: TextStyle(
                fontSize: AppType.body,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: t.foreground,
              ),
            ),
            trailing: isSelected ? Icon(Icons.check_circle, size: 20, color: t.primary) : null,
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool active;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
        decoration: BoxDecoration(
          color: active ? t.primary.withValues(alpha: 0.12) : t.surfaceMuted.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(R.pill),
          border: Border.all(color: active ? t.primary.withValues(alpha: 0.35) : t.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: active ? t.primary : t.mutedForeground),
            const GapX(S.xs),
            Text(
              label,
              style: TextStyle(
                fontSize: AppType.label,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? t.primary : t.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Spend and income per day, over whatever the filter covers.
///
/// One line, deliberately. The figures above already give the totals; this
/// answers the different question of *rate*, and a card around it would make a
/// footnote look like a headline. The denominator is shown because "per day"
/// over four days and over four months are not the same claim.
class _PerDayStrip extends StatelessWidget {
  const _PerDayStrip({required this.averages, required this.money});

  final RangeAverages averages;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final a = averages;

    return Semantics(
      label:
          'Per day over ${a.days} days: ${a.spend} spent, ${a.income} earned',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
        decoration: BoxDecoration(
          color: t.surfaceMuted.withValues(alpha: t.isDark ? 0.4 : 0.55),
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Row(
          children: [
            Muted('PER DAY', size: AppType.micro),
            const GapX(S.md),
            _Figure(
              icon: Icons.north_east_rounded,
              color: t.danger,
              value: money(a.spend),
            ),
            const GapX(S.md),
            _Figure(
              icon: Icons.south_west_rounded,
              color: t.success,
              value: money(a.income),
            ),
            const Spacer(),
            Muted('${a.days}d', size: AppType.micro),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.icon, required this.color, required this.value});

  final IconData icon;
  final Color color;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const GapX(S.xxs),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Amount(value, size: AppType.bodySm),
            ),
          ),
        ],
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const GapX(S.xxs),
              Muted(label, size: 10.5),
            ],
          ),
          const Gap(S.xxs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Amount(value, size: 14, color: color),
          ),
        ],
      ),
    );
  }
}
