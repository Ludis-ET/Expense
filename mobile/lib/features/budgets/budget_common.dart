import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../models/models.dart';
import '../../widgets/ui.dart';

/// Colour and tone for each `BudgetHealth`, shared by the list card, the
/// detail header and the analytics rows.
BadgeTone healthTone(BudgetHealth health) => switch (health) {
  BudgetHealth.drained => BadgeTone.danger,
  BudgetHealth.low => BadgeTone.warning,
  BudgetHealth.ready || BudgetHealth.spending => BadgeTone.primary,
  BudgetHealth.partlyFunded => BadgeTone.info,
  BudgetHealth.scheduled => BadgeTone.info,
  BudgetHealth.closed || BudgetHealth.unplanned || BudgetHealth.empty => BadgeTone.neutral,
};

Color healthColor(BuildContext context, BudgetHealth health) {
  final t = context.t;
  return switch (health) {
    BudgetHealth.drained => t.danger,
    BudgetHealth.low => t.warning,
    BudgetHealth.ready || BudgetHealth.spending => t.primary,
    BudgetHealth.partlyFunded || BudgetHealth.scheduled => t.accent,
    _ => t.mutedForeground,
  };
}

/// One line of plain English explaining where the plan stands, so the numbers
/// never have to be decoded.
String healthSentence(BudgetRow b, String Function(Object?) money) => switch (b.health) {
  BudgetHealth.unplanned => 'Spending that never went through a funded plan lands here.',
  BudgetHealth.scheduled =>
    'Starts ${_startPhrase(b.startsAt)} — nothing can be spent before then.',
  BudgetHealth.empty => 'Nothing filled yet. Add money from a wallet to start.',
  BudgetHealth.partlyFunded => '${money(b.fillable)} more can still go in before it hits the plan.',
  BudgetHealth.ready => 'Filled and ready. ${money(b.balance)} to spend.',
  BudgetHealth.spending => '${money(b.balance)} left of ${money(b.fundedAmount)} filled.',
  BudgetHealth.low => 'Running low — only ${money(b.balance)} left.',
  BudgetHealth.drained => 'Empty. Top it up or hold off until the next cycle.',
  BudgetHealth.closed => 'Closed. Kept for the record.',
};

String _startPhrase(DateTime startsAt) {
  final days = startsAt.difference(DateTime.now()).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'tomorrow';
  return 'in $days days';
}

/// "monthly", "every 6 hours" — the API sends this ready to print, but
/// one-time plans have none.
String cadenceLabel(BudgetRow b) {
  if (b.isUnplanned) return 'Catch-all';
  if (b.kind == BudgetKind.oneTime) return 'One-time';
  return b.recurrenceLabel ?? 'Recurring';
}

/// Signed raise/cut chip matching the web `AdjustmentChip`.
class AdjustmentChip extends StatelessWidget {
  const AdjustmentChip({super.key, required this.amount, required this.money});

  final Object? amount;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final n = toNum(amount);
    if (n == 0) return const SizedBox.shrink();
    final up = n > 0;
    final color = up ? t.success : t.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 13,
            color: color,
          ),
          const GapX(S.xxs),
          Text(
            '${up ? 'Raised' : 'Cut'} by ${money(n.abs())}',
            style: TextStyle(fontSize: AppType.caption, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}
