import 'package:flutter/material.dart';

import '../../core/haptics.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../widgets/ui.dart';
import 'budget_common.dart';
import 'budget_transactions.dart';

/// A cycle card view: either the live open cycle or a frozen past snapshot.
class CycleView {
  CycleView({
    required this.index,
    required this.label,
    required this.startedAt,
    required this.endedAt,
    required this.openingPlanned,
    required this.adjustedAmount,
    required this.plannedAmount,
    required this.carriedIn,
    required this.fundedAmount,
    required this.spentAmount,
    required this.leftoverAmount,
    required this.txCount,
    required this.adjustments,
    required this.current,
  });

  final int index;
  final String label;
  final DateTime startedAt;
  final DateTime endedAt;
  final String openingPlanned;
  final String adjustedAmount;
  final String plannedAmount;
  final String carriedIn;
  final String fundedAmount;
  final String spentAmount;
  final String leftoverAmount;
  final int txCount;
  final List<BudgetAdjustment> adjustments;
  final bool current;

  factory CycleView.current(BudgetDetail plan) {
    final b = plan.row;
    return CycleView(
      index: b.cycleIndex,
      label: b.cycleLabel ?? 'This cycle',
      startedAt: b.cycleStartedAt,
      endedAt: b.nextResetAt ?? b.cycleStartedAt,
      openingPlanned: b.openingPlanned,
      adjustedAmount: b.adjustedThisCycle,
      plannedAmount: b.plannedAmount,
      carriedIn: b.carriedIn,
      fundedAmount: b.fundedAmount,
      spentAmount: b.spentAmount,
      leftoverAmount: b.balance,
      txCount: plan.cycleTxCount,
      adjustments: plan.adjustments,
      current: true,
    );
  }

  factory CycleView.fromSnapshot(BudgetCycleSnapshot c) => CycleView(
    index: c.index,
    label: c.label,
    startedAt: c.startedAt,
    endedAt: c.endedAt,
    openingPlanned: c.openingPlanned,
    adjustedAmount: c.adjustedAmount,
    plannedAmount: c.plannedAmount,
    carriedIn: c.carriedIn,
    fundedAmount: c.fundedAmount,
    spentAmount: c.spentAmount,
    leftoverAmount: c.leftoverAmount,
    txCount: c.txCount,
    adjustments: c.adjustments,
    current: false,
  );
}

/// Recurring plan: period cards (current + history). Tap to open cycle sheet.
class BudgetCycleSections extends StatelessWidget {
  const BudgetCycleSections({super.key, required this.plan, required this.money, this.onChanged});

  final BudgetDetail plan;
  final String Function(Object?) money;
  final VoidCallback? onChanged;

  List<CycleView> get _cycles => [
    CycleView.current(plan),
    ...plan.cycles.map(CycleView.fromSnapshot),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final b = plan.row;
    final cycles = _cycles;
    final noun = b.periodNoun ?? 'cycle';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.repeat_rounded, size: 16, color: t.mutedForeground),
            const GapX(S.sm),
            Text(
              'Every $noun',
              style: TextStyle(
                fontSize: AppType.body,
                fontWeight: FontWeight.w700,
                color: t.foreground,
              ),
            ),
            const GapX(S.xs),
            InfoHint(
              label: 'Every $noun',
              body:
                  'Each $noun keeps the amount it opened with, so a mid-cycle '
                  'raise shows up as a change rather than rewriting history. '
                  'Quiet periods where nothing moved are skipped.',
              size: 14,
            ),
            const Spacer(),
            Muted('${cycles.length} ${cycles.length == 1 ? 'period' : 'periods'}', size: 11),
          ],
        ),
        const Gap(S.md),
        for (var i = 0; i < cycles.length; i++) ...[
          if (i > 0) const Gap(S.sm),
          FadeInUp.staggered(
            index: i.clamp(0, 6),
            child: _CycleCard(
              cycle: cycles[i],
              money: money,
              tint: parseHexColor(b.color) ?? t.primary,
              onOpen: () => _openCycle(context, cycles[i]),
            ),
          ),
        ],
        if (plan.cycles.isEmpty) ...[
          const Gap(S.sm),
          Muted('None yet', size: 11.5),
        ],
      ],
    );
  }

  Future<void> _openCycle(BuildContext context, CycleView cycle) async {
    Haptics.select();
    await showAppSheet<void>(
      context,
      title: cycle.label,
      subtitle: cycle.current ? 'Running now' : 'Closed period',
      builder: (ctx) => _CycleSheet(plan: plan, cycle: cycle, money: money, onChanged: onChanged),
    );
  }
}

class _CycleCard extends StatelessWidget {
  const _CycleCard({
    required this.cycle,
    required this.money,
    required this.tint,
    required this.onOpen,
  });

  final CycleView cycle;
  final String Function(Object?) money;
  final Color tint;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final opening = toNum(cycle.openingPlanned) <= 0 ? 0.01 : toNum(cycle.openingPlanned);
    final spentPct = (toNum(cycle.spentAmount) / opening * 100).clamp(0.0, 100.0);
    final fundedPct = (toNum(cycle.fundedAmount) / opening * 100).clamp(0.0, 100.0);
    final adjusted = toNum(cycle.adjustedAmount);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(R.xl),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.xl),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                t.surfaceElevated,
                t.surfaceMuted.withValues(alpha: t.isDark ? 0.55 : 0.85),
              ],
            ),
            border: Border.all(
              color: cycle.current ? tint.withValues(alpha: 0.45) : t.border.withValues(alpha: 0.8),
            ),
            boxShadow: cycle.current
                ? [
                    BoxShadow(
                      color: tint.withValues(alpha: 0.12),
                      blurRadius: 18,
                      spreadRadius: -4,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : t.cardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.all(S.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  cycle.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: AppType.body,
                                    fontWeight: FontWeight.w700,
                                    color: t.foreground,
                                  ),
                                ),
                              ),
                              if (cycle.current) ...[
                                const GapX(S.sm),
                                AppBadge('Running', tone: BadgeTone.primary, dense: true),
                              ],
                            ],
                          ),
                          const Gap(S.xxs),
                          Muted(
                            '${formatDate(cycle.startedAt)} → ${formatDate(cycle.endedAt)}'
                            ' · ${cycle.txCount} expense${cycle.txCount == 1 ? '' : 's'}',
                            size: 11,
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                    const GapX(S.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Amount(money(cycle.openingPlanned), size: 16),
                        const Gap(S.hair),
                        Muted('planned at start', size: 10),
                      ],
                    ),
                  ],
                ),
                if (adjusted != 0) ...[
                  const Gap(S.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AdjustmentChip(amount: cycle.adjustedAmount, money: money),
                  ),
                ],
                const Gap(S.md),
                Stack(
                  children: [
                    ProgressBar(
                      value: fundedPct,
                      height: 8,
                      gradient: [tint.withValues(alpha: 0.3), tint.withValues(alpha: 0.2)],
                    ),
                    ProgressBar(value: spentPct, height: 8, tone: BadgeTone.primary),
                  ],
                ),
                const Gap(S.md),
                Row(
                  children: [
                    Expanded(
                      child: _MiniStat(label: 'Filled', value: money(cycle.fundedAmount)),
                    ),
                    Expanded(
                      child: _MiniStat(label: 'Spent', value: money(cycle.spentAmount)),
                    ),
                    Expanded(
                      child: _MiniStat(label: 'Carried in', value: money(cycle.carriedIn)),
                    ),
                    Expanded(
                      child: _MiniStat(
                        label: cycle.current ? 'Left' : 'Carried out',
                        value: money(cycle.leftoverAmount),
                        accent: cycle.current,
                      ),
                    ),
                  ],
                ),
                const Gap(S.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Muted('View expenses', size: 11),
                    Icon(Icons.chevron_right_rounded, size: 16, color: t.mutedForeground),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.accent = false});

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Muted(label, size: 10),
        const Gap(S.hair),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: AppType.label,
              fontWeight: FontWeight.w700,
              color: accent ? t.primary : t.foreground,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _CycleSheet extends StatelessWidget {
  const _CycleSheet({required this.plan, required this.cycle, required this.money, this.onChanged});

  final BudgetDetail plan;
  final CycleView cycle;
  final String Function(Object?) money;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final adjusted = toNum(cycle.adjustedAmount);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Amount(money(cycle.openingPlanned), size: 26),
                    const Gap(S.hair),
                    Muted('opening planned', size: 12),
                  ],
                ),
              ),
              if (adjusted != 0) AdjustmentChip(amount: cycle.adjustedAmount, money: money),
            ],
          ),
          const Gap(S.md),
          Row(
            children: [
              Expanded(
                child: _FigTile(label: 'Filled', value: money(cycle.fundedAmount)),
              ),
              const GapX(S.sm),
              Expanded(
                child: _FigTile(label: 'Spent', value: money(cycle.spentAmount)),
              ),
            ],
          ),
          const Gap(S.sm),
          Row(
            children: [
              Expanded(
                child: _FigTile(label: 'Carried in', value: money(cycle.carriedIn)),
              ),
              const GapX(S.sm),
              Expanded(
                child: _FigTile(
                  label: cycle.current ? 'Left' : 'Carried out',
                  value: money(cycle.leftoverAmount),
                  color: t.primary,
                ),
              ),
            ],
          ),
          if (cycle.adjustments.isNotEmpty) ...[
            const Gap(S.lg),
            Text(
              'Adjustments',
              style: TextStyle(
                fontSize: AppType.bodySm,
                fontWeight: FontWeight.w700,
                color: t.foreground,
              ),
            ),
            const Gap(S.sm),
            for (final a in cycle.adjustments)
              Padding(
                padding: const EdgeInsets.only(bottom: S.sm),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.md),
                  decoration: BoxDecoration(
                    color: t.surfaceMuted.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(R.md),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        toNum(a.amount) >= 0 ? Icons.trending_up : Icons.trending_down,
                        size: 16,
                        color: toNum(a.amount) >= 0 ? t.success : t.warning,
                      ),
                      const GapX(S.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.reason?.isNotEmpty == true
                                  ? a.reason!
                                  : (toNum(a.amount) >= 0 ? 'Raised' : 'Cut'),
                              style: TextStyle(
                                fontSize: AppType.bodySm,
                                fontWeight: FontWeight.w600,
                                color: t.foreground,
                              ),
                            ),
                            Muted(formatDate(a.date), size: 11),
                          ],
                        ),
                      ),
                      Amount(
                        '${toNum(a.amount) >= 0 ? '+' : '−'}${money(toNum(a.amount).abs())}',
                        size: 13,
                        color: toNum(a.amount) >= 0 ? t.success : t.warning,
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const Gap(S.lg),
          BudgetTransactionsPanel(
            plan: plan,
            lockedCycle: cycle.index,
            heading: 'Expenses this period',
            embedded: true,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _FigTile extends StatelessWidget {
  const _FigTile({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.md),
      decoration: BoxDecoration(
        color: t.surfaceMuted.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Muted(label, size: 10.5),
          const Gap(S.xxs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Amount(value, size: 14.5, color: color),
          ),
        ],
      ),
    );
  }
}
