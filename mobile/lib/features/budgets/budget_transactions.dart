import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';
import '../transactions/transaction_detail.dart';
import '../transactions/transaction_list.dart';

const _pageSize = 20;

/// Searchable, filterable, paginated expenses for a plan — mirrors the web
/// `BudgetTransactions` panel. Fetched separately so Unplanned never tries to
/// load years of rows at once.
class BudgetTransactionsPanel extends StatefulWidget {
  const BudgetTransactionsPanel({
    super.key,
    required this.plan,
    this.lockedCycle,
    this.heading = 'Transactions',
    this.embedded = false,
    this.onChanged,
  });

  final BudgetDetail plan;
  final int? lockedCycle;
  final String heading;

  /// When true, skip the outer AppCard chrome (used inside cycle sheets).
  final bool embedded;
  final VoidCallback? onChanged;

  @override
  State<BudgetTransactionsPanel> createState() => _BudgetTransactionsPanelState();
}

class _BudgetTransactionsPanelState extends State<BudgetTransactionsPanel> {
  final _search = TextEditingController();
  Timer? _debounce;

  String _q = '';
  String? _categoryId;
  String _cycle = 'all';
  DateTime? _from;
  DateTime? _to;
  String _sort = 'date_desc';
  int _page = 1;
  bool _showFilters = false;

  TransactionPage? _data;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.lockedCycle != null) _cycle = '${widget.lockedCycle}';
    _search.addListener(_onSearchTyped);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DataState>().loadCategories();
      _fetch();
    });
  }

  @override
  void didUpdateWidget(covariant BudgetTransactionsPanel old) {
    super.didUpdateWidget(old);
    if (old.plan.row.id != widget.plan.row.id ||
        old.lockedCycle != widget.lockedCycle) {
      if (widget.lockedCycle != null) _cycle = '${widget.lockedCycle}';
      _page = 1;
      _fetch();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.removeListener(_onSearchTyped);
    _search.dispose();
    super.dispose();
  }

  void _onSearchTyped() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final next = _search.text.trim();
      if (next == _q) return;
      setState(() {
        _q = next;
        _page = 1;
      });
      _fetch();
    });
  }

  int get _activeFilters {
    var n = 0;
    if (_q.isNotEmpty) n++;
    if (_categoryId != null) n++;
    if (widget.lockedCycle == null && _cycle != 'all') n++;
    if (_from != null) n++;
    if (_to != null) n++;
    return n;
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = <String, dynamic>{
        'budgetId': widget.plan.row.id,
        'page': '$_page',
        'pageSize': '$_pageSize',
        'sort': _sort,
        if (_q.isNotEmpty) 'q': _q,
        if (_categoryId != null) 'categoryId': _categoryId,
        if (_cycle != 'all') 'budgetCycle': _cycle,
        if (_from != null) 'from': _from!.toUtc().toIso8601String(),
        if (_to != null) 'to': _to!.toUtc().toIso8601String(),
      };
      final json = await context.read<ApiClient>().get<Map<String, dynamic>>(
            '/transactions',
            query: query,
          );
      if (!mounted) return;
      setState(() {
        _data = TransactionPage.fromJson(json);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _resetFilters() {
    setState(() {
      _search.clear();
      _q = '';
      _categoryId = null;
      if (widget.lockedCycle == null) _cycle = 'all';
      _from = null;
      _to = null;
      _sort = 'date_desc';
      _page = 1;
    });
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final prefs = context.watch<PrefsState>();
    final data = context.watch<DataState>();
    final b = widget.plan.row;
    final items = _data?.items ?? const <Transaction>[];
    final total = _data?.total ?? 0;
    final pages = (_data == null) ? 1 : ((_data!.total / _pageSize).ceil().clamp(1, 9999));
    final pageTotal = items.fold<double>(0, (s, tx) => s + tx.value);

    String money(Object? v) => prefs.money(v, currency: b.currency);

    final categories = data.categories.data
            ?.where((c) => c.kind == 'EXPENSE' && !c.archived)
            .toList() ??
        const <TxCategory>[];

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.heading,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: t.foreground,
                ),
              ),
            ),
            if (total > 0)
              Muted('$total · ${money(pageTotal)} on page', size: 11),
          ],
        ),
        const SizedBox(height: 12),

        // Search + filter toggle
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: _search,
                placeholder: 'Search payee or note',
                prefixIcon: Icons.search_rounded,
                textCapitalization: TextCapitalization.none,
              ),
            ),
            const SizedBox(width: 8),
            _FilterChipButton(
              active: _showFilters || _activeFilters > 0,
              count: _activeFilters,
              onTap: () => setState(() => _showFilters = !_showFilters),
            ),
          ],
        ),

        AnimatedSize(
          duration: Motion.fast,
          curve: Motion.easeOut,
          alignment: Alignment.topCenter,
          child: _showFilters
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _FiltersPanel(
                    categories: categories,
                    cycles: widget.plan.cycles,
                    lockedCycle: widget.lockedCycle,
                    categoryId: _categoryId,
                    cycle: _cycle,
                    from: _from,
                    to: _to,
                    sort: _sort,
                    onCategory: (id) {
                      setState(() {
                        _categoryId = id;
                        _page = 1;
                      });
                      _fetch();
                    },
                    onCycle: (c) {
                      setState(() {
                        _cycle = c;
                        _page = 1;
                      });
                      _fetch();
                    },
                    onFrom: (d) {
                      setState(() {
                        _from = d;
                        _page = 1;
                      });
                      _fetch();
                    },
                    onTo: (d) {
                      setState(() {
                        _to = d;
                        _page = 1;
                      });
                      _fetch();
                    },
                    onSort: (s) {
                      setState(() {
                        _sort = s;
                        _page = 1;
                      });
                      _fetch();
                    },
                    onClear: _activeFilters > 0 ? _resetFilters : null,
                  ),
                )
              : const SizedBox.shrink(),
        ),

        const SizedBox(height: 14),

        if (_loading && _data == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_error != null && _data == null)
          ErrorState(
            message: _error is ApiError
                ? (_error as ApiError).message
                : 'Could not load transactions.',
            onRetry: _fetch,
          )
        else if (items.isEmpty)
          EmptyState(
            title: _activeFilters > 0 ? 'No matches' : 'No expenses yet',
            description: _activeFilters > 0
                ? 'Try clearing filters or searching something else.'
                : 'Spend from this plan and it will show up here.',
            compact: true,
          )
        else ...[
          if (_loading)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(
                minHeight: 2,
                color: t.primary,
                backgroundColor: t.primary.withValues(alpha: 0.12),
              ),
            ),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: t.border.withValues(alpha: 0.5)),
            TransactionRow(
              tx: items[i],
              money: (amt, cur) => prefs.money(amt, currency: cur),
              compact: true,
              onTap: () async {
                final changed = await showTransactionDetail(context, items[i]);
                if (changed == true) {
                  await _fetch();
                  widget.onChanged?.call();
                }
              },
            ),
          ],
          if (pages > 1) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _page > 1
                      ? () {
                          setState(() => _page--);
                          _fetch();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Text(
                  '$_page / $pages',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.foreground,
                  ),
                ),
                IconButton(
                  onPressed: _page < pages
                      ? () {
                          setState(() => _page++);
                          _fetch();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ],
        ],
      ],
    );

    if (widget.embedded) return body;
    return AppCard(padding: const EdgeInsets.all(14), child: body);
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.active,
    required this.count,
    required this.onTap,
  });

  final bool active;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: active ? t.primary.withValues(alpha: 0.12) : t.surfaceMuted,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.lg),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(
              color: active ? t.primary.withValues(alpha: 0.35) : t.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 18,
                color: active ? t.primary : t.mutedForeground,
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: t.primary,
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: t.primaryForeground,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FiltersPanel extends StatelessWidget {
  const _FiltersPanel({
    required this.categories,
    required this.cycles,
    required this.lockedCycle,
    required this.categoryId,
    required this.cycle,
    required this.from,
    required this.to,
    required this.sort,
    required this.onCategory,
    required this.onCycle,
    required this.onFrom,
    required this.onTo,
    required this.onSort,
    this.onClear,
  });

  final List<TxCategory> categories;
  final List<BudgetCycleSnapshot> cycles;
  final int? lockedCycle;
  final String? categoryId;
  final String cycle;
  final DateTime? from;
  final DateTime? to;
  final String sort;
  final ValueChanged<String?> onCategory;
  final ValueChanged<String> onCycle;
  final ValueChanged<DateTime?> onFrom;
  final ValueChanged<DateTime?> onTo;
  final ValueChanged<String> onSort;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surfaceMuted.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: t.border.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PickerField<TxCategory>(
            label: 'Category',
            value: categories.where((c) => c.id == categoryId).firstOrNull,
            options: categories,
            labelOf: (c) => c.name,
            iconOf: (c) => financeIcon(c.icon),
            colorOf: (c) => parseHexColor(c.color) ?? t.mutedForeground,
            onChanged: (c) => onCategory(c?.id),
            allowClear: true,
            placeholder: 'All categories',
            sheetTitle: 'Category',
          ),
          if (lockedCycle == null && cycles.isNotEmpty) ...[
            const SizedBox(height: 12),
            PickerField<_CycleOpt>(
              label: 'Cycle',
              value: _cycleOpts(cycles).where((o) => o.id == cycle).firstOrNull,
              options: _cycleOpts(cycles),
              labelOf: (o) => o.label,
              onChanged: (o) => onCycle(o?.id ?? 'all'),
              placeholder: 'All time',
              sheetTitle: 'Cycle',
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DateField(
                  label: 'From',
                  value: from,
                  onChanged: onFrom,
                  allowClear: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DateField(
                  label: 'To',
                  value: to,
                  onChanged: onTo,
                  allowClear: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PickerField<_SortOpt>(
            label: 'Sort',
            value: _sorts.where((s) => s.id == sort).firstOrNull,
            options: _sorts,
            labelOf: (s) => s.label,
            onChanged: (s) {
              if (s != null) onSort(s.id);
            },
            sheetTitle: 'Sort',
          ),
          if (onClear != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onClear,
                child: const Text('Clear filters'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static List<_CycleOpt> _cycleOpts(List<BudgetCycleSnapshot> cycles) => [
        const _CycleOpt('all', 'All time'),
        const _CycleOpt('current', 'Current cycle'),
        for (final c in cycles) _CycleOpt('${c.index}', c.label),
      ];
}

class _CycleOpt {
  const _CycleOpt(this.id, this.label);
  final String id;
  final String label;
}

class _SortOpt {
  const _SortOpt(this.id, this.label);
  final String id;
  final String label;
}

const _sorts = [
  _SortOpt('date_desc', 'Newest first'),
  _SortOpt('date_asc', 'Oldest first'),
  _SortOpt('amount_desc', 'Largest first'),
  _SortOpt('amount_asc', 'Smallest first'),
];
