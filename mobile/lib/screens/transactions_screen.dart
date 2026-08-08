import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/formatting.dart';
import '../models/finance.dart';
import '../offline/sync_engine.dart';
import '../state/data_store.dart';
import '../widgets/common.dart';
import 'dashboard_screen.dart' show TransactionTile;

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
    // Fetch a screen early so the list does not visibly stall at the bottom.
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      context.read<DataStore>().loadTransactions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final groups = _groupByDay(data.transactions);

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: RefreshIndicator(
        onRefresh: () => data.loadTransactions(reset: true),
        child: data.transactions.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No transactions yet',
                    message: 'Add one with the + button, or pair your phone so bank SMS fills them in.',
                  ),
                ],
              )
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
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
                    child: SectionCard(
                      title: group.label,
                      subtitle: group.subtitle,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Column(
                        children: [
                          for (final tx in group.items)
                            TransactionTile(
                              tx: tx,
                              onTap: () => _showDetail(context, tx),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _showDetail(BuildContext context, Transaction tx) async {
    final data = context.read<DataStore>();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _TransactionDetail(
        tx: tx,
        onDelete: () async {
          Navigator.pop(sheetContext);
            try {
            await data.deleteTransaction(tx.id);
            if (context.mounted) {
              showOk(
                context,
                context.read<SyncEngine>().online ? 'Deleted' : 'Deleted offline — will sync later',
              );
            }
          } on ApiException catch (e) {
            if (context.mounted) showError(context, e.message);
          }
        },
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
      // Net for the day, so a day reads as a whole rather than a pile of rows.
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

class _TransactionDetail extends StatelessWidget {
  const _TransactionDetail({required this.tx, required this.onDelete});

  final Transaction tx;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tx.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            Money.signed(tx.amount, tx.kind, currency: tx.currency),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: SantimAmountColor.of(context, tx.kind),
            ),
          ),
          const SizedBox(height: 20),

          _DetailRow(label: 'Date', value: Dates.full(tx.date)),
          if (tx.categoryName != null) _DetailRow(label: 'Category', value: tx.categoryName!),
          if (tx.accountName != null) _DetailRow(label: 'Account', value: tx.accountName!),
          if (tx.budgetName != null) _DetailRow(label: 'Plan', value: tx.budgetName!),
          if (tx.note?.isNotEmpty == true) _DetailRow(label: 'Note', value: tx.note!),
          if (tx.fromBankMessage)
            _DetailRow(label: 'Source', value: 'Captured from a bank message'),

          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete transaction'),
            style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Small helper so the detail sheet does not need to import the theme class.
class SantimAmountColor {
  static Color of(BuildContext context, String kind) => switch (kind) {
        'INCOME' => const Color(0xFF059669),
        'EXPENSE' => const Color(0xFFE11D48),
        _ => Theme.of(context).colorScheme.onSurfaceVariant,
      };
}
