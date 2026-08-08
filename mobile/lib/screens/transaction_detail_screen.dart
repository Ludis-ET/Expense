import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/formatting.dart';
import '../core/theme.dart';
import '../models/finance.dart';
import '../offline/sync_engine.dart';
import '../state/data_store.dart';
import '../widgets/common.dart';
import '../widgets/web_chrome.dart';
import 'transaction_form.dart';

Future<void> showTransactionDetailSheet(BuildContext context, Transaction tx) {
  return showSantimSheet(
    context: context,
    title: 'Transaction Details',
    builder: (ctx) => TransactionDetailBody(tx: tx),
  );
}

class TransactionDetailBody extends StatelessWidget {
  const TransactionDetailBody({super.key, required this.tx});

  final Transaction tx;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;
    final amountColor = SantimTheme.amountColor(tx.kind, theme.colorScheme);
    final iconColor = tx.isTransfer
        ? const Color(0xFF64748B)
        : (parseHexColor(tx.categoryColor) ?? const Color(0xFF64748B));
    final kindLabel = switch (tx.kind) {
      'INCOME' => 'Income',
      'EXPENSE' => 'Expense',
      _ => 'Transfer',
    };
    final kindIcon = switch (tx.kind) {
      'INCOME' => Icons.south_west_rounded,
      'EXPENSE' => Icons.north_east_rounded,
      _ => Icons.swap_horiz_rounded,
    };
    final dateFormatted = tx.date == null
        ? '—'
        : DateFormat('EEEE, d MMMM yyyy').format(tx.date!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.border),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                iconColor.withValues(alpha: 0.09),
                theme.colorScheme.surface,
                iconColor.withValues(alpha: 0.05),
              ],
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border.withValues(alpha: 0.6)),
                ),
                child: Icon(
                  tx.isTransfer ? Icons.swap_horiz_rounded : Icons.category_rounded,
                  color: iconColor,
                  size: 32,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                Money.signed(tx.amount, tx.kind, currency: tx.currency),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: amountColor,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: amountColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(kindIcon, size: 12, color: amountColor),
                    const SizedBox(width: 6),
                    Text(
                      kindLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: amountColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (tx.pendingSync) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'Queued (offline)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.warning),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (tx.budgetName != null) ...[
          const SizedBox(height: 16),
          SoftCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: (parseHexColor(tx.budgetColor) ?? colors.primary)
                              .withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.savings_outlined,
                          color: parseHexColor(tx.budgetColor) ?? colors.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PARENT PLAN',
                              style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w600,
                                color: colors.muted,
                              ),
                            ),
                            Text(
                              tx.budgetName!,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        tx.budgetCycle != null ? 'Cycle ${tx.budgetCycle}' : 'Plan spend',
                        style: TextStyle(fontSize: 12, color: colors.muted),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colors.border),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _miniStat(context, 'Plan', tx.budgetName!),
                      _miniStat(context, 'Category', tx.categoryName ?? 'Uncategorized'),
                      _miniStat(context, 'Account', tx.accountName ?? 'Unknown'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        SoftCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              DetailRowTile(icon: Icons.calendar_today_outlined, label: 'Date', value: dateFormatted),
              if (tx.isTransfer)
                DetailRowTile(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Transfer',
                  value: '${tx.accountName ?? '?'} → ${tx.transferAccountName ?? '?'}',
                )
              else ...[
                if (tx.payee?.isNotEmpty == true)
                  DetailRowTile(icon: Icons.person_outline_rounded, label: 'Payee / Merchant', value: tx.payee!),
                if (tx.categoryName != null)
                  DetailRowTile(icon: Icons.category_outlined, label: 'Category', value: tx.categoryName!),
              ],
              DetailRowTile(
                icon: Icons.credit_card_outlined,
                label: 'Account',
                value: tx.accountName ?? 'Unknown',
              ),
              if (tx.note?.isNotEmpty == true)
                DetailRowTile(icon: Icons.notes_outlined, label: 'Note', value: tx.note!),
              if (tx.tags.isNotEmpty)
                DetailRowTile(
                  icon: Icons.tag_rounded,
                  label: 'Tags',
                  value: '',
                  valueWidget: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in tx.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '#$t',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (tx.recurringRuleId != null)
                DetailRowTile(
                  icon: Icons.repeat_rounded,
                  label: 'Recurring',
                  value: 'Part of a recurring rule',
                  valueColor: colors.primary,
                ),
              if (tx.fromBankMessage)
                const DetailRowTile(
                  icon: Icons.sms_outlined,
                  label: 'Source',
                  value: 'Bank message',
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          tx.id,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: colors.muted.withValues(alpha: 0.5),
          ),
        ),
        if (!tx.isTransfer) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await Navigator.of(context).push(
                      santimRoute(
                        TransactionForm(
                          initialKind: tx.kind,
                          initialAmount: tx.amount,
                          initialPayee: tx.payee,
                          initialDate: tx.date,
                        ),
                      ),
                    );
                  },
                  child: const Text('Edit'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: colors.danger),
                  onPressed: () => _delete(context),
                  child: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _miniStat(BuildContext context, String label, String value) {
    final colors = Theme.of(context).extension<SantimColors>()!;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceMuted.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(fontSize: 10, letterSpacing: 0.6, color: colors.muted),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
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

/// Kept for deep-link / older push call sites.
class TransactionDetailScreen extends StatelessWidget {
  const TransactionDetailScreen({super.key, required this.tx});

  final Transaction tx;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction Details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [TransactionDetailBody(tx: tx)],
      ),
    );
  }
}
