import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/formatting.dart';
import '../core/theme.dart';
import '../models/finance.dart';
import '../state/data_store.dart';
import '../widgets/common.dart';
import '../widgets/web_chrome.dart';
import 'transaction_detail_screen.dart';
import 'transaction_form.dart';
import 'transfer_sheet.dart';

/// Website-matching ledger: month nav, search, type/category/plan filters,
/// day-grouped bordered lists, and a detail bottom sheet.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;

  String _month = MonthNavigator.currentMonth();
  String _kind = '';
  String _categoryId = '';
  String _budgetId = '';
  int _tab = 0; // 0 ledger, 1 recurring placeholder

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyFilters());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.removeListener(_maybeLoadMore);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      context.read<DataStore>().loadTransactions();
    }
  }

  Future<void> _applyFilters() async {
    final bounds = MonthNavigator.bounds(_month);
    final data = context.read<DataStore>();
    data.setTransactionFilters(
      from: bounds.$1,
      to: bounds.$2,
      kind: _kind,
      categoryId: _categoryId,
      budgetId: _budgetId,
      q: _search.text.trim(),
      clearKind: _kind.isEmpty,
      clearCategory: _categoryId.isEmpty,
      clearBudget: _budgetId.isEmpty,
      clearQuery: _search.text.trim().isEmpty,
    );
    await data.loadTransactions(reset: true);
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), _applyFilters);
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final groups = _groupByDay(data.transactions);
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;
    final categories = data.categories.where((c) => !c.archived).toList();
    final budgets = data.budgets.where((b) => b.state == 'ACTIVE').toList();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _applyFilters,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              floating: true,
              leading: IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
              ),
              title: const Text('Transactions'),
              actions: [
                TextButton.icon(
                  onPressed: () => showTransferSheet(context),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('Transfer'),
                ),
                const WebTopActions(),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ledger for the selected month',
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                    ),
                    const SizedBox(height: 12),
                    SegmentedTabs(
                      labels: const ['Ledger', 'Recurring'],
                      index: _tab,
                      onChanged: (i) => setState(() => _tab = i),
                    ),
                    if (_tab == 0) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          MonthNavigator(
                            month: _month,
                            onChanged: (m) async {
                              setState(() => _month = m);
                              await _applyFilters();
                            },
                          ),
                          SizedBox(
                            width: 220,
                            child: TextField(
                              controller: _search,
                              onChanged: _onSearchChanged,
                              decoration: InputDecoration(
                                hintText: 'Search payee or note…',
                                prefixIcon: Icon(Icons.search_rounded, color: colors.muted, size: 20),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ),
                          _FilterChipSelect(
                            value: _kind,
                            hint: 'All types',
                            items: const {
                              '': 'All types',
                              'EXPENSE': 'Expense',
                              'INCOME': 'Income',
                              'TRANSFER': 'Transfer',
                            },
                            onChanged: (v) async {
                              setState(() => _kind = v);
                              await _applyFilters();
                            },
                          ),
                          _FilterChipSelect(
                            value: _categoryId,
                            hint: 'All categories',
                            items: {
                              '': 'All categories',
                              for (final c in categories) c.id: c.name,
                            },
                            onChanged: (v) async {
                              setState(() => _categoryId = v);
                              await _applyFilters();
                            },
                          ),
                          _FilterChipSelect(
                            value: _budgetId,
                            hint: 'All plans',
                            items: {
                              '': 'All plans',
                              for (final b in budgets) b.id: b.name,
                            },
                            onChanged: (v) async {
                              setState(() => _budgetId = v);
                              await _applyFilters();
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_tab == 1)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.repeat_rounded,
                  title: 'Recurring rules',
                  message: 'Manage recurring income and bills on the website for now.',
                ),
              )
            else if (data.loading && data.transactions.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      ShimmerBlock(height: 72),
                      SizedBox(height: 12),
                      ShimmerBlock(height: 72),
                    ],
                  ),
                ),
              )
            else if (data.transactions.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions',
                  message: 'Nothing matches these filters for this month.',
                  action: FilledButton(
                    onPressed: () => Navigator.of(context).push(santimRoute(const TransactionForm())),
                    child: const Text('Add transaction'),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                sliver: SliverList.builder(
                  itemCount: groups.length + (data.hasMoreTransactions ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= groups.length) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final group = groups[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    group.label.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                      color: colors.muted,
                                    ),
                                  ),
                                ),
                                Text(
                                  group.subtitle,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: group.net >= 0 ? colors.success : colors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SoftCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                for (var i = 0; i < group.items.length; i++) ...[
                                  if (i > 0) Divider(height: 1, color: colors.border),
                                  _TxRow(
                                    tx: group.items[i],
                                    onTap: () => showTransactionDetailSheet(context, group.items[i]),
                                    onDelete: () => _delete(group.items[i]),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(Transaction tx) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This transaction will be removed permanently.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 40)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<DataStore>().deleteTransaction(tx.id);
      if (mounted) showOk(context, 'Deleted');
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    }
  }

  List<_DayGroup> _groupByDay(List<Transaction> items) {
    final map = <String, List<Transaction>>{};
    for (final tx in items) {
      final d = tx.date;
      final key = d == null ? 'unknown' : '${d.year}-${d.month}-${d.day}';
      map.putIfAbsent(key, () => []).add(tx);
    }
    return map.entries.map((e) {
      final first = e.value.first.date;
      final net = e.value.fold<double>(0, (sum, tx) {
        final amount = Money.parse(tx.amount);
        return switch (tx.kind) {
          'INCOME' => sum + amount,
          'EXPENSE' => sum - amount,
          _ => sum,
        };
      });
      return _DayGroup(
        label: _dayLabel(first),
        subtitle: '${net >= 0 ? '+' : '−'}${Money.format(net.abs())}',
        net: net,
        items: e.value,
      );
    }).toList();
  }

  String _dayLabel(DateTime? d) {
    if (d == null) return 'Undated';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return Dates.day(d);
  }
}

class _DayGroup {
  const _DayGroup({
    required this.label,
    required this.subtitle,
    required this.net,
    required this.items,
  });

  final String label;
  final String subtitle;
  final double net;
  final List<Transaction> items;
}

class _FilterChipSelect extends StatelessWidget {
  const _FilterChipSelect({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  final String value;
  final String hint;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SantimColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.containsKey(value) ? value : '',
          isDense: true,
          borderRadius: BorderRadius.circular(12),
          hint: Text(hint, style: TextStyle(fontSize: 13, color: colors.muted)),
          items: [
            for (final e in items.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13))),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class _TxRow extends StatelessWidget {
  const _TxRow({required this.tx, required this.onTap, required this.onDelete});

  final Transaction tx;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;
    final amountColor = SantimTheme.amountColor(tx.kind, theme.colorScheme);
    final iconColor = tx.isTransfer
        ? const Color(0xFF64748B)
        : (parseHexColor(tx.categoryColor) ?? const Color(0xFF64748B));

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                tx.isTransfer ? Icons.swap_horiz_rounded : Icons.category_rounded,
                size: 18,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          tx.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: tx.pendingSync ? colors.muted : null,
                          ),
                        ),
                      ),
                      if (tx.pendingSync) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.warning.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            'Queued',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: colors.warning),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tx.isTransfer
                        ? (tx.note ?? 'Transfer')
                        : [
                            if (tx.categoryName != null) tx.categoryName!,
                            if (tx.accountName != null) tx.accountName!,
                            if (tx.note?.isNotEmpty == true) tx.note!,
                          ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              Money.signed(tx.amount, tx.kind, currency: tx.currency),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: amountColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline_rounded, size: 18, color: colors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
