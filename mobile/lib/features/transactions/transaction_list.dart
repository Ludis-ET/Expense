import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../widgets/ui.dart';

/// One transaction row: category tile, title, meta line, signed amount. Shared
/// by the dashboard's "Recent transactions" card and the activity screen.
class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.tx,
    required this.money,
    this.onTap,
    this.compact = false,
    this.showDate = true,
  });

  final Transaction tx;
  final String Function(Object? amount, String currency) money;
  final VoidCallback? onTap;
  final bool compact;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final isIncome = tx.kind == TxKind.income;
    final isTransfer = tx.kind == TxKind.transfer;

    final tint = isTransfer
        ? t.accent
        : parseHexColor(tx.category?.color) ?? (isIncome ? t.success : t.mutedForeground);

    final icon = isTransfer
        ? Icons.swap_horiz_rounded
        : financeIcon(tx.category?.icon ?? (isIncome ? 'trending-up' : null));

    final amountColor = isTransfer
        ? t.foreground
        : isIncome
            ? t.success
            : t.foreground;

    final meta = <String>[
      if (showDate) formatDayMonth(tx.date),
      if (tx.account != null) tx.account!.name,
      if (isTransfer && tx.transferAccount != null) '→ ${tx.transferAccount!.name}',
      if (!isTransfer && tx.category != null) tx.category!.name,
    ];

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.md),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: compact ? 8 : 10),
        child: Row(
          children: [
            Stack(
              children: [
                IconTile(icon: icon, color: tint, size: compact ? 36 : 40),
                if (tx.pending != PendingState.none)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: tx.pending == PendingState.error ? t.danger : t.warning,
                        shape: BoxShape.circle,
                        border: Border.all(color: t.surface, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          tx.title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compact ? 13.5 : 14,
                            fontWeight: FontWeight.w600,
                            color: t.foreground,
                          ),
                        ),
                      ),
                      if (tx.budget != null && !tx.budget!.name.contains('Unplanned')) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.savings_outlined, size: 12, color: t.primary),
                      ],
                      if (tx.recurringRuleId != null) ...[
                        const SizedBox(width: 5),
                        Icon(Icons.repeat, size: 12, color: t.mutedForeground),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Muted(meta.join(' · '), size: 11.5, maxLines: 1),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Amount(
                  isTransfer
                      ? money(tx.amount, tx.currency)
                      : '${isIncome ? '+' : '−'}${money(tx.amount, tx.currency)}',
                  size: compact ? 13.5 : 14.5,
                  color: amountColor,
                ),
                if (tx.tags.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Muted('#${tx.tags.first}', size: 10),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A list of rows with hairline separators, no outer padding — drop it inside
/// a card or a sliver.
class TransactionList extends StatelessWidget {
  const TransactionList({
    super.key,
    required this.items,
    required this.money,
    this.onTap,
    this.compact = false,
    this.animate = true,
    this.showDate = true,
  });

  final List<Transaction> items;
  final String Function(Object? amount, String currency) money;
  final void Function(Transaction tx)? onTap;
  final bool compact;
  final bool animate;

  /// Off when the list is already grouped under a date header.
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) Divider(height: 1, color: t.border.withValues(alpha: 0.6)),
          if (animate)
            FadeInUp.staggered(
              index: i.clamp(0, 10),
              offset: 6,
              child: TransactionRow(
                tx: items[i],
                money: money,
                compact: compact,
                showDate: showDate,
                onTap: onTap == null ? null : () => onTap!(items[i]),
              ),
            )
          else
            TransactionRow(
              tx: items[i],
              money: money,
              compact: compact,
              showDate: showDate,
              onTap: onTap == null ? null : () => onTap!(items[i]),
            ),
        ],
      ],
    );
  }
}
