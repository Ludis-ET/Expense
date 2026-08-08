import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../models/finance.dart';
import '../state/data_store.dart';
import '../widgets/common.dart';

/// Budget plans, shown as funded envelopes rather than spending limits.
///
/// The distinction matters: a plan here holds real reserved money, so the
/// figure that counts is what is left in the pot, not how far through an
/// allowance you are.
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final plans = data.budgets.where((b) => b.state == 'ACTIVE' && !b.isUnplanned).toList();
    final unplanned = data.budgets.where((b) => b.isUnplanned).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plans'),
        actions: const [
          InfoHint(
            title: 'Funded plans',
            message:
                'A plan is an envelope, not a limit. You fill it from an account, and that '
                'money stops counting as free to spend even though it never leaves the '
                'account. Spending against the plan releases the reservation.',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: data.refreshAll,
        child: plans.isEmpty && unplanned == null
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.pie_chart_outline,
                    title: 'No plans yet',
                    message: 'Create plans in the Santim web app, then fill and spend them here.',
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  for (final b in plans) ...[
                    _BudgetCard(budget: b),
                    const SizedBox(height: 12),
                  ],
                  if (unplanned != null) ...[
                    const SizedBox(height: 4),
                    _UnplannedCard(budget: unplanned),
                  ],
                ],
              ),
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.budget});

  final Budget budget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final left = Money.parse(budget.potBalance);
    final drained = left <= 0;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  budget.name,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (!budget.started)
                const StatusPill(label: 'Not started', tone: PillTone.neutral)
              else if (drained)
                const StatusPill(label: 'Empty', tone: PillTone.bad, icon: Icons.error_outline)
              else if (budget.progress >= 0.8)
                const StatusPill(label: 'Running low', tone: PillTone.warn),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Left in the pot',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    Money.format(budget.potBalance, currency: budget.currency),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: drained ? SantimTheme.expense : SantimTheme.income,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                '${Money.format(budget.spentAmount, currency: budget.currency)} spent '
                'of ${Money.format(budget.fundedAmount, currency: budget.currency)}',
                textAlign: TextAlign.right,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: budget.progress,
              minHeight: 8,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(
                drained
                    ? SantimTheme.expense
                    : budget.progress >= 0.8
                        ? SantimTheme.warning
                        : SantimTheme.income,
              ),
            ),
          ),

          if (Money.parse(budget.plannedAmount) > 0) ...[
            const SizedBox(height: 10),
            Text(
              'Planned ${Money.format(budget.plannedAmount, currency: budget.currency)} this cycle',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The built-in catch-all. It holds no pot, so showing pot figures for it would
/// be misleading - only the running total makes sense.
class _UnplannedCard extends StatelessWidget {
  const _UnplannedCard({required this.budget});

  final Budget budget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SectionCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.more_horiz, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  budget.name,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  'Spending you never set money aside for',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            Money.format(budget.spentAmount, currency: budget.currency),
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
