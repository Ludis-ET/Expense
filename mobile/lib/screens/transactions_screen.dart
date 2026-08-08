import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../models/finance.dart';
import '../state/data_store.dart';
import '../widgets/common.dart';
import 'transaction_detail_screen.dart';

/// The full ledger, grouped by day and paged as you scroll.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.removeListener(_maybeLoadMore);
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      context.read<DataStore>().loadTransactions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final groups = _groupByDay(data.transactions);
    final theme = Theme.of(context);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => data.loadTransactions(reset: true),
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              floating: true,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Activity', style: theme.textTheme.titleLarge),
                  Text(
                    data.transactions.isEmpty
                        ? 'Your ledger'
                        : '${data.transactions.length} entries',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (data.loading && data.transactions.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      ShimmerBlock(height: 120),
                      SizedBox(height: 12),
                      ShimmerBlock(height: 120),
                    ],
                  ),
                ),
              )
            else if (data.transactions.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions yet',
                  message: 'Add one with + , or pair your phone so bank SMS fills them in.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
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
                      padding: const EdgeInsets.only(bottom: 14),
                      child: SoftCard(
                        padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      group.label,
                                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  Text(
                                    group.subtitle,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (final tx in group.items)
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () => Navigator.of(context).push(
                                    santimRoute(TransactionDetailScreen(tx: tx)),
                                  ),
                                  child: _TxRow(tx: tx),
                                ),
                              ),
                          ],
                        ),
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
  const _DayGroup({required this.label, required this.subtitle, required this.items});

  final String label;
  final String subtitle;
  final List<Transaction> items;
}

class _TxRow extends StatelessWidget {
  const _TxRow({required this.tx});

  final Transaction tx;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = SantimTheme.amountColor(tx.kind, theme.colorScheme);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Container(
        height: 44,
        width: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          switch (tx.kind) {
            'INCOME' => Icons.south_west_rounded,
            'EXPENSE' => Icons.north_east_rounded,
            _ => Icons.swap_horiz_rounded,
          },
          size: 20,
          color: color,
        ),
      ),
      title: Text(
        tx.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: tx.pendingSync ? theme.colorScheme.onSurface.withValues(alpha: 0.55) : null,
        ),
      ),
      subtitle: Text(
        [
          if (tx.categoryName != null) tx.categoryName!,
          if (tx.accountName != null) tx.accountName!,
          Dates.day(tx.date),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            Money.signed(tx.amount, tx.kind, currency: tx.currency),
            style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
          if (tx.pendingSync)
            const Icon(Icons.cloud_upload_outlined, size: 14, color: SantimTheme.warning),
        ],
      ),
    );
  }
}
