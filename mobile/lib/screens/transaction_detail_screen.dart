import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/formatting.dart';
import '../core/theme.dart';
import '../models/finance.dart';
import '../offline/sync_engine.dart';
import '../state/data_store.dart';
import '../widgets/common.dart';

class TransactionDetailScreen extends StatelessWidget {
  const TransactionDetailScreen({super.key, required this.tx});

  final Transaction tx;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = SantimTheme.amountColor(tx.kind, theme.colorScheme);

    return Scaffold(
      appBar: AppBar(title: const Text('Transaction')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          SoftCard(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.05)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusPill(
                  label: tx.kind.toLowerCase(),
                  tone: tx.kind == 'INCOME'
                      ? PillTone.good
                      : tx.kind == 'EXPENSE'
                          ? PillTone.bad
                          : PillTone.neutral,
                ),
                const SizedBox(height: 14),
                Text(tx.title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  Money.signed(tx.amount, tx.kind, currency: tx.currency),
                  style: theme.textTheme.displaySmall?.copyWith(color: color),
                ),
                if (tx.pendingSync) ...[
                  const SizedBox(height: 10),
                  const StatusPill(label: 'Waiting to sync', tone: PillTone.warn),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          SoftCard(
            child: Column(
              children: [
                _row(context, Icons.calendar_today_outlined, 'Date', Dates.day(tx.date)),
                _row(context, Icons.category_outlined, 'Category', tx.categoryName ?? '—'),
                _row(context, Icons.account_balance_wallet_outlined, 'Wallet', tx.accountName ?? '—'),
                _row(context, Icons.pie_chart_outline, 'Plan', tx.budgetName ?? '—'),
                if (tx.note?.isNotEmpty == true) _row(context, Icons.notes_outlined, 'Note', tx.note!),
                if (tx.fromBankMessage) _row(context, Icons.sms_outlined, 'Source', 'Bank message'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: SantimTheme.expense),
            onPressed: () => _delete(context),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete transaction'),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This cannot be undone.'),
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
    if (ok != true || !context.mounted) return;
    final data = context.read<DataStore>();
    try {
      await data.deleteTransaction(tx.id);
      if (!context.mounted) return;
      final online = context.read<SyncEngine>().online;
      Navigator.pop(context);
      showOk(context, online ? 'Deleted' : 'Deleted offline — will sync later');
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e.message);
    }
  }
}
