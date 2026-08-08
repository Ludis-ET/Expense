import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../models/finance.dart';
import '../widgets/common.dart';

class BudgetDetailScreen extends StatelessWidget {
  const BudgetDetailScreen({super.key, required this.budget});

  final Budget budget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final left = Money.parse(budget.potBalance);
    final drained = left <= 0 && !budget.isUnplanned;
    final color = drained
        ? SantimTheme.expense
        : budget.progress >= 0.8
            ? SantimTheme.warning
            : SantimTheme.income;

    return Scaffold(
      appBar: AppBar(title: Text(budget.isUnplanned ? 'Catch-all' : 'Plan')),
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
                Row(
                  children: [
                    Expanded(
                      child: Text(budget.name, style: theme.textTheme.headlineSmall),
                    ),
                    if (!budget.started)
                      const StatusPill(label: 'Not started', tone: PillTone.neutral)
                    else if (drained)
                      const StatusPill(label: 'Empty', tone: PillTone.bad)
                    else if (budget.progress >= 0.8)
                      const StatusPill(label: 'Running low', tone: PillTone.warn)
                    else
                      const StatusPill(label: 'Healthy', tone: PillTone.good),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  budget.isUnplanned ? 'Spent so far' : 'Left in the pot',
                  style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text(
                  Money.format(
                    budget.isUnplanned ? budget.spentAmount : budget.potBalance,
                    currency: budget.currency,
                  ),
                  style: theme.textTheme.displaySmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
          if (!budget.isUnplanned) ...[
            const SizedBox(height: 14),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: budget.progress,
                      minHeight: 10,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _row(context, 'Funded', Money.format(budget.fundedAmount, currency: budget.currency)),
                  _row(context, 'Spent', Money.format(budget.spentAmount, currency: budget.currency)),
                  if (Money.parse(budget.plannedAmount) > 0)
                    _row(context, 'Planned this cycle', Money.format(budget.plannedAmount, currency: budget.currency)),
                  _row(context, 'Kind', budget.kind.replaceAll('_', ' ').toLowerCase()),
                  _row(context, 'State', budget.state.toLowerCase()),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SoftCard(
              child: Text(
                'A plan is an envelope of reserved money, not a spending limit. '
                'Filling it holds cash in your wallet; spending from it releases the hold.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
            SoftCard(
              child: Text(
                'Unplanned catches spending you never set money aside for. '
                'It does not reserve a pot — it only labels the outflow.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
