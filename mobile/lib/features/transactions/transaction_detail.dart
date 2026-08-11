import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../widgets/ui.dart';
import 'transaction_form.dart';

/// `TransactionDetailModal` — the full record, with edit and delete.
/// Returns true when the transaction was changed or removed.
Future<bool?> showTransactionDetail(BuildContext context, Transaction tx) {
  return showAppSheet<bool>(
    context,
    title: 'Transaction',
    builder: (ctx) => _TransactionDetail(tx: tx),
  );
}

class _TransactionDetail extends StatelessWidget {
  const _TransactionDetail({required this.tx});
  final Transaction tx;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final prefs = context.watch<PrefsState>();
    final isIncome = tx.kind == TxKind.income;
    final isTransfer = tx.kind == TxKind.transfer;

    final tint = isTransfer
        ? t.accent
        : parseHexColor(tx.category?.color) ?? (isIncome ? t.success : t.danger);

    String money(Object? v) => prefs.money(v, currency: tx.currency, decimals: true);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Column(
              children: [
                IconTile(
                  icon: isTransfer
                      ? Icons.swap_horiz_rounded
                      : financeIcon(tx.category?.icon),
                  color: tint,
                  size: 56,
                  radius: R.lg,
                ),
                const SizedBox(height: 12),
                Amount(
                  isTransfer ? money(tx.amount) : '${isIncome ? '+' : '−'}${money(tx.amount)}',
                  size: 30,
                  color: isTransfer
                      ? t.foreground
                      : isIncome
                          ? t.success
                          : t.foreground,
                ),
                const SizedBox(height: 4),
                Text(
                  tx.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.foreground,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    AppBadge(
                      tx.kind.label,
                      tone: isIncome
                          ? BadgeTone.success
                          : isTransfer
                              ? BadgeTone.info
                              : BadgeTone.neutral,
                    ),
                    if (tx.recurringRuleId != null)
                      AppBadge('Recurring', tone: BadgeTone.primary, icon: Icons.repeat),
                    for (final tag in tx.tags) AppBadge('#$tag', tone: BadgeTone.neutral),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _DetailRow(label: 'Date', value: formatDate(tx.date), icon: Icons.calendar_today_outlined),
          _DetailRow(
            label: 'Ethiopian',
            value: formatEthiopian(tx.date),
            icon: Icons.event_note_outlined,
          ),
          if (tx.account != null)
            _DetailRow(
              label: isTransfer ? 'From' : 'Account',
              value: tx.account!.name,
              icon: Icons.account_balance_wallet_outlined,
            ),
          if (tx.transferAccount != null)
            _DetailRow(
              label: 'To',
              value: tx.transferAccount!.name,
              icon: Icons.south_east_rounded,
            ),
          if (tx.category != null)
            _DetailRow(
              label: 'Category',
              value: tx.category!.name,
              icon: financeIcon(tx.category!.icon),
              color: parseHexColor(tx.category!.color),
            ),
          if (tx.budget != null)
            _DetailRow(
              label: 'Budget plan',
              value: tx.budget!.name +
                  (tx.budgetCycle != null ? ' · cycle ${tx.budgetCycle}' : ''),
              icon: Icons.savings_outlined,
              color: parseHexColor(tx.budget!.color),
            ),
          if (tx.budgetSourceAccount != null)
            _DetailRow(
              label: 'Freed reservation on',
              value: tx.budgetSourceAccount!.name,
              icon: Icons.lock_open_outlined,
            ),
          if (tx.payee != null)
            _DetailRow(label: 'Payee', value: tx.payee!, icon: Icons.storefront_outlined),
          if (tx.note != null)
            _DetailRow(label: 'Note', value: tx.note!, icon: Icons.notes_outlined, wrap: true),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Edit',
                  icon: Icons.edit_outlined,
                  variant: BtnVariant.outline,
                  expand: true,
                  onPressed: () async {
                    final changed = await showTransactionForm(context, existing: tx);
                    if (changed == true && context.mounted) {
                      await context.read<DataState>().refreshAfterWrite();
                      if (context.mounted) Navigator.pop(context, true);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: 'Delete',
                  icon: Icons.delete_outline,
                  variant: BtnVariant.danger,
                  expand: true,
                  onPressed: () => _delete(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await confirm(
      context,
      title: 'Delete transaction?',
      message: 'The balance it moved will be put back. This cannot be undone.',
    );
    if (!ok || !context.mounted) return;

    final api = context.read<ApiClient>();
    final data = context.read<DataState>();
    try {
      await api.delete('/transactions/${tx.id}');
      await data.refreshAfterWrite();
      if (context.mounted) {
        Navigator.pop(context, true);
        toast(context, 'Transaction deleted');
      }
    } on ApiError catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.wrap = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: wrap ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color ?? t.mutedForeground),
          const SizedBox(width: 11),
          Muted(label, size: 12.5),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: wrap ? 6 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                height: wrap ? 1.45 : null,
                fontWeight: FontWeight.w600,
                color: t.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
