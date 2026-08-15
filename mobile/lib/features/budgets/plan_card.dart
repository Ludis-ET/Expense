// The plan card, in both of its identities.
//
// A spending envelope and a saving pot are the same primitive underneath, and
// drawing them the same way was throwing away the only thing that matters at a
// glance: which direction the money is going. So the card is one component with
// two physics.
//
//   spending          a recessed well, the fill retreating leftward
//   saving + goal     the same well upright, the fill rising to a target line
//   saving, no goal   no finish line to draw, so the lifetime total leads and
//                     the bar measures only this period
//
// One rule picks between them - a finish line decides the shape, recurrence
// decides whether a period row appears - so every combination has a card and
// none of them is a special case bolted on.
import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../widgets/depth.dart';
import '../../widgets/ui.dart';
import 'budget_common.dart';

class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.budget,
    required this.money,
    this.onTap,
  });

  final BudgetRow budget;
  final String Function(Object?) money;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final saving = budget.saving;
    return PressableTilt(
      onTap: onTap,
      child: saving == null
          ? _SpendingCard(budget: budget, money: money)
          : _SavingCard(budget: budget, saving: saving, money: money),
    );
  }
}

/// Shared chrome: the sheen, the border, the shadow.
///
/// The sheen is a white gradient over the top ~45%, which reads as a light
/// source without touching the palette. It is what makes the card feel like a
/// surface rather than a rectangle.
class _Shell extends StatelessWidget {
  const _Shell({required this.child, required this.tint, this.lifted = false});

  final Widget child;
  final Color tint;
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(R.xl),
        border: Border.all(
          color: Color.lerp(t.border, tint, lifted ? 0.34 : 0.22)!,
        ),
        boxShadow: t.cardShadow,
        gradient: lifted
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(t.surface, tint, t.isDark ? 0.10 : 0.055)!,
                  t.surface,
                ],
                stops: const [0, 0.62],
              )
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(R.xl),
        child: Stack(
          children: [
            Padding(padding: const EdgeInsets.all(S.lg), child: child),
            // The lit top edge.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 54,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: t.isDark ? 0.055 : 0.42),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon, name, badge line, and the one figure that leads.
class _Head extends StatelessWidget {
  const _Head({
    required this.icon,
    required this.tint,
    required this.name,
    required this.subtitle,
    required this.figure,
    required this.figureLabel,
    required this.figureColor,
    this.badge,
    this.badgeTone = BadgeTone.neutral,
    this.gradientGlyph = false,
  });

  final IconData icon;
  final Color tint;
  final String name;
  final Widget subtitle;
  final String figure;
  final String figureLabel;
  final Color figureColor;
  final String? badge;
  final BadgeTone badgeTone;
  final bool gradientGlyph;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A saving glyph is filled rather than tinted, so the two types differ
        // at the very first glance.
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            color: gradientGlyph ? null : tint.withValues(alpha: t.isDark ? 0.16 : 0.1),
            gradient: gradientGlyph
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [t.saveLift, t.save],
                  )
                : null,
            boxShadow: gradientGlyph
                ? [
                    BoxShadow(
                      color: t.save.withValues(alpha: 0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 20,
            color: gradientGlyph ? Colors.white : tint,
          ),
        ),
        const GapX(S.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppType.body,
                  fontWeight: W.bold,
                  letterSpacing: -0.1,
                  color: t.foreground,
                ),
              ),
              const Gap(S.hair),
              Row(
                children: [
                  if (badge != null) ...[
                    AppBadge(badge!, tone: badgeTone, dense: true),
                    const GapX(S.xs),
                  ],
                  Flexible(child: subtitle),
                ],
              ),
            ],
          ),
        ),
        const GapX(S.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Amount(figure, size: AppType.lead, color: figureColor),
            ),
            const Gap(S.hair),
            Muted(figureLabel, size: AppType.micro, maxLines: 1),
          ],
        ),
      ],
    );
  }
}

// ─── Spending ────────────────────────────────────────────────────────────────

class _SpendingCard extends StatelessWidget {
  const _SpendingCard({required this.budget, required this.money});

  final BudgetRow budget;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final b = budget;
    final tint = parseHexColor(b.color) ?? healthColor(context, b.health);

    final funded = toNum(b.fundedAmount);
    // What is *left*, as a share of what went in. The well empties, so the fill
    // is the remainder rather than the spend.
    final left = funded <= 0 ? 0.0 : (toNum(b.balance) / funded).clamp(0.0, 1.0);

    return _Shell(
      tint: tint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Head(
            icon: financeIcon(b.icon ?? b.category?.icon),
            tint: tint,
            name: b.name,
            badge: b.health.label,
            badgeTone: healthTone(b.health),
            subtitle: Muted(cadenceLabel(b), size: AppType.caption, maxLines: 1),
            figure: money(b.balance),
            figureLabel: 'left',
            figureColor: tint,
          ),
          const Gap(S.md),
          InsetWell(
            value: left,
            fill: tint,
            axis: WellAxis.horizontal,
            // A tick per week: the drain needs a pace to be judged against.
            ticks: b.recurrenceUnit == RecurrenceUnit.month ? 4 : 0,
          ),
          const Gap(S.sm),
          DefaultTextStyle(
            style: TextStyle(fontSize: AppType.caption, color: t.mutedForeground),
            child: Row(
              children: [
                Text('${money(b.spentAmount)} spent'),
                const Spacer(),
                Text('${money(b.fundedAmount)} filled'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Saving ──────────────────────────────────────────────────────────────────

class _SavingCard extends StatelessWidget {
  const _SavingCard({
    required this.budget,
    required this.saving,
    required this.money,
  });

  final BudgetRow budget;
  final SavingFacts saving;
  final String Function(Object?) money;

  /// Where each contribution sits inside the fill, as a fraction of it.
  ///
  /// Recomputed against the *fill* rather than the goal, so the lines stay put
  /// relative to the money they represent as the pot rises.
  List<double> _strata() {
    final total = toNum(budget.balance);
    if (total <= 0 || saving.recentPeriods.isEmpty) return const [];
    // One line per recent period that received something. Precise positions
    // would need the amounts; evenly spaced reads the same at this size and
    // avoids shipping a contribution list to every card.
    final n = saving.recentPeriods.where((m) => m).length.clamp(0, 6);
    return [for (var i = 1; i <= n; i++) i / (n + 1)];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final b = budget;
    final tint = parseHexColor(b.color) ?? t.save;
    final hasGoal = saving.hasGoal;
    final recurring = b.kind == BudgetKind.recurring;

    return _Shell(
      tint: t.save,
      lifted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Head(
            icon: financeIcon(b.icon ?? b.category?.icon),
            tint: tint,
            gradientGlyph: true,
            name: b.name,
            badge: _badge(),
            badgeTone: _badgeTone(),
            subtitle: _Subtitle(budget: b, saving: saving, money: money),
            // With a finish line the pair "27,500 of 40,000" is the story.
            // Without one there is no denominator, so the lifetime total is.
            figure: money(b.balance),
            figureLabel: hasGoal ? 'of ${money(saving.goalAmount)}' : 'saved so far',
            figureColor: t.save,
          ),
          const Gap(S.md),

          if (hasGoal)
            InsetWell(
              value: (saving.pctOfGoal ?? 0) / 100,
              fill: t.save,
              axis: WellAxis.vertical,
              height: 74,
              radius: R.lg,
              strata: _strata(),
              target: 1,
              targetLabel: saving.goalMet ? null : 'target',
            )
          else
            InsetWell(
              value: (saving.pctOfPeriod ?? 0) / 100,
              fill: t.save,
              axis: WellAxis.horizontal,
            ),

          // A recurring plan with a goal gets both readings, never competing
          // for the same slot: the vault answers how far to the finish line,
          // this hairline answers whether the month is being kept up.
          if (hasGoal && recurring) ...[
            const Gap(S.sm),
            InsetWell(
              value: (saving.pctOfPeriod ?? 0) / 100,
              fill: t.saveLift,
              axis: WellAxis.horizontal,
              height: 7,
              radius: R.sm,
            ),
          ],

          const Gap(S.sm),
          DefaultTextStyle(
            style: TextStyle(fontSize: AppType.caption, color: t.mutedForeground),
            child: Row(
              children: [
                Flexible(child: Text(_leftLine(), overflow: TextOverflow.ellipsis)),
                const Spacer(),
                Flexible(child: Text(_rightLine(), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _badge() {
    if (saving.goalMet) return 'Reached';
    return switch (saving.pace) {
      'ahead' => 'Ahead',
      'behind' => 'Behind',
      'on-track' => 'On track',
      _ => null,
    };
  }

  BadgeTone _badgeTone() {
    if (saving.goalMet) return BadgeTone.success;
    return switch (saving.pace) {
      'ahead' => BadgeTone.success,
      'behind' => BadgeTone.warning,
      _ => BadgeTone.info,
    };
  }

  String _leftLine() {
    if (saving.periodTarget != null) {
      return '${money(saving.periodContributed)} of ${money(saving.periodTarget)} this period';
    }
    if (saving.pctOfGoal != null) return '${saving.pctOfGoal!.round()}% saved';
    return '${money(budget.balance)} saved';
  }

  String _rightLine() {
    if (saving.goalMet) return 'Goal reached';
    if (saving.hasGoal) {
      if (saving.projectedAt != null) {
        return 'on track for ${formatDayMonth(saving.projectedAt)}';
      }
      return '${money(saving.remainingToGoal)} to go';
    }
    return 'no ceiling';
  }
}

/// The cadence line, with the streak beside it when there is one.
class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.budget, required this.saving, required this.money});

  final BudgetRow budget;
  final SavingFacts saving;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    final text = saving.periodTarget != null
        ? '${money(saving.periodTarget)} ${budget.recurrenceLabel ?? 'each period'}'
        : cadenceLabel(budget);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Muted(text, size: AppType.caption, maxLines: 1)),
        if (saving.recentPeriods.isNotEmpty) ...[
          const GapX(S.xs),
          _Streak(periods: saving.recentPeriods),
        ],
      ],
    );
  }
}

/// One dot per recent period: filled when its target was met.
///
/// The run is the thing worth protecting on a habit, and it reads faster as
/// dots than as "4 months in a row".
class _Streak extends StatelessWidget {
  const _Streak({required this.periods});

  final List<bool> periods;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final shown = periods.length > 6 ? periods.sublist(periods.length - 6) : periods;
    return Semantics(
      label: '${shown.where((m) => m).length} of ${shown.length} recent periods met',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final met in shown)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: met ? t.save : t.border,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
