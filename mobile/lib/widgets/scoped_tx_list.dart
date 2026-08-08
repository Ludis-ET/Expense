import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../models/finance.dart';
import '../screens/transaction_detail_screen.dart';
import 'common.dart';
import 'web_chrome.dart';

/// Compact transaction list used inside account / plan detail views.
class ScopedTransactionList extends StatelessWidget {
  const ScopedTransactionList({
    super.key,
    required this.items,
    this.loading = false,
    this.emptyTitle = 'No transactions',
    this.emptyMessage = 'Nothing recorded here yet.',
    this.popBeforeDetail = false,
  });

  final List<Transaction> items;
  final bool loading;
  final String emptyTitle;
  final String emptyMessage;
  final bool popBeforeDetail;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SantimColors>()!;

    if (loading) {
      return const Column(
        children: [
          ShimmerBlock(height: 56),
          SizedBox(height: 8),
          ShimmerBlock(height: 56),
        ],
      );
    }
    if (items.isEmpty) {
      return EmptyState(icon: Icons.receipt_long_outlined, title: emptyTitle, message: emptyMessage);
    }

    return SoftCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: colors.border),
            _ScopedTxRow(tx: items[i], popBeforeDetail: popBeforeDetail),
          ],
        ],
      ),
    );
  }
}

class _ScopedTxRow extends StatelessWidget {
  const _ScopedTxRow({required this.tx, required this.popBeforeDetail});

  final Transaction tx;
  final bool popBeforeDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;
    final amountColor = SantimTheme.amountColor(tx.kind, theme.colorScheme);
    final iconColor = tx.isTransfer
        ? const Color(0xFF64748B)
        : (parseHexColor(tx.categoryColor) ?? const Color(0xFF64748B));

    return InkWell(
      onTap: () async {
        if (popBeforeDetail) Navigator.pop(context);
        await showTransactionDetailSheet(context, tx);
      },
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
                  Text(
                    tx.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    [
                      if (tx.categoryName != null) tx.categoryName!,
                      Dates.day(tx.date),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                  ),
                ],
              ),
            ),
            Text(
              Money.signed(tx.amount, tx.kind, currency: tx.currency),
              style: theme.textTheme.bodyMedium?.copyWith(color: amountColor, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
