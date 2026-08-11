import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../core/layout.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/utils/monthly_outlook.dart';
import '../../models/models.dart';
import '../../models/outlook_history.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../widgets/ui.dart';
import '../budgets/budget_detail_screen.dart';
import '../recurring/recurring_screen.dart';
import '../shell/app_shell.dart';

/// Full-screen monthly cashflow outlook.
///
/// The question this page answers — "how much do I need to earn?" — has three
/// honest answers, not one. Collapsing them into a single figure hid which
/// lever to pull, and quietly folded in a surprise reserve sized from the
/// current month's own overspending. Here each layer is selectable and every
/// number says where it came from.
class MonthlyOutlookScreen extends StatefulWidget {
  const MonthlyOutlookScreen({super.key});

  @override
  State<MonthlyOutlookScreen> createState() => _MonthlyOutlookScreenState();
}

class _MonthlyOutlookScreenState extends State<MonthlyOutlookScreen> {
  OutlookTarget _target = OutlookTarget.steady;
  PayCadence _cadence = PayCadence.monthly;

  /// What-if income, or null while the user has not dragged the slider.
  double? _whatIf;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final data = context.read<DataState>();
      await Future.wait([
        data.loadRecurring(),
        data.loadBudgets(),
        data.loadDashboard(),
        data.loadOutlookHistory(),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final data = context.watch<DataState>();
    final prefs = context.watch<PrefsState>();
    final currency = data.activeCurrency;
    final month = data.activeBreakdown?.month ?? data.dashboard.data?.month;

    final outlook = buildMonthlyOutlook(
      currency: currency,
      rules: data.recurring.data ?? const [],
      budgets: data.budgets.data?.items ?? const [],
      month: month,
      history: data.outlookHistory.data,
      topCategories: data.dashboard.data?.topCategories ?? const [],
    );

    String money(Object? v) => prefs.money(v, currency: currency);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        foregroundColor: t.foreground,
        title: Text(
          'Monthly outlook',
          style: TextStyle(
            fontSize: AppType.lead,
            fontWeight: W.bold,
            color: t.foreground,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => AppShell.of(context).push(const RecurringScreen()),
            child: Text('Manage', style: TextStyle(color: t.primary, fontWeight: W.bold)),
          ),
        ],
      ),
      body: MeshBackground(
        child: RefreshIndicator(
          onRefresh: () => Future.wait([
            data.loadRecurring(force: true),
            data.loadBudgets(force: true),
            data.loadDashboard(force: true),
            data.loadOutlookHistory(force: true),
          ]),
          color: t.primary,
          child: ListView(
            padding: EdgeInsets.fromLTRB(S.lg, S.xxs, S.lg, ShellLayout.bottomClearance(context)),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              FadeInUp(
                child: _TargetHero(
                  outlook: outlook,
                  money: money,
                  target: _target,
                  cadence: _cadence,
                  onTarget: (v) {
                    Haptics.select();
                    setState(() => _target = v);
                  },
                  onCadence: (v) {
                    Haptics.select();
                    setState(() => _cadence = v);
                  },
                ),
              ),
              const Gap(S.md),
              FadeInUp(
                delay: const Duration(milliseconds: 40),
                child: _LayerBreakdown(outlook: outlook, money: money, target: _target),
              ),

              if (outlook.breakEvenDay != null || outlook.floorSpend > 0) ...[
                const Gap(S.md),
                FadeInUp(
                  delay: const Duration(milliseconds: 60),
                  child: _BreakEvenCard(outlook: outlook),
                ),
              ],

              if (outlook.requiredFor(OutlookTarget.comfortable) > 0) ...[
                const Gap(S.md),
                FadeInUp(
                  delay: const Duration(milliseconds: 80),
                  child: _WhatIfCard(
                    outlook: outlook,
                    money: money,
                    value: _whatIf,
                    onChanged: (v) => setState(() => _whatIf = v),
                    onReset: () {
                      Haptics.toggle();
                      setState(() => _whatIf = null);
                    },
                  ),
                ),
              ],

              if ((outlook.history?.months.isNotEmpty ?? false)) ...[
                const Gap(S.md),
                FadeInUp(
                  delay: const Duration(milliseconds: 100),
                  child: _CoverageHistoryCard(history: outlook.history!, money: money),
                ),
              ],

              const Gap(S.md),
              FadeInUp(
                delay: const Duration(milliseconds: 120),
                child: _ActualVsExpected(outlook: outlook, money: money, target: _target),
              ),

              if (outlook.repeatCandidates.isNotEmpty) ...[
                const Gap(S.md),
                FadeInUp(
                  delay: const Duration(milliseconds: 140),
                  child: _RepeatCandidatesCard(
                    outlook: outlook,
                    money: money,
                    onCreated: () => data.loadRecurring(force: true),
                  ),
                ),
              ],

              const Gap(S.md),
              FadeInUp(
                delay: const Duration(milliseconds: 160),
                child: _InsightsCard(insights: outlook.insights),
              ),

              const Gap(S.xl),
              SectionLabel(
                'RECURRING BILLS',
                hint: 'Rules that fire whether or not you act. These alone are the Floor target.',
              ),
              if (outlook.expenseLines.isEmpty)
                _EmptyHint(
                  icon: Icons.north_east_rounded,
                  title: 'No recurring bills',
                  body: 'Rent, utilities and subscriptions belong here — they are the '
                      'floor under everything else.',
                  actionLabel: 'Add a bill',
                  onAction: () => AppShell.of(context).push(const RecurringScreen()),
                )
              else
                for (var i = 0; i < outlook.expenseLines.length; i++)
                  FadeInUp.staggered(
                    index: i,
                    child: _LineCard(
                      line: outlook.expenseLines[i],
                      money: money,
                      total: outlook.requiredFor(_target),
                      accent: t.danger,
                    ),
                  ),

              const Gap(S.md),
              SectionLabel(
                'BUDGET PLANS',
                hint: 'Each plan\'s planned amount. Where a recurring bill already pays for '
                    'the same category, the plan is counted once — not twice.',
              ),
              if (outlook.planLines.isEmpty)
                _EmptyHint(
                  icon: Icons.savings_outlined,
                  title: 'No active plans',
                  body: 'Create plans for groceries, transport or school fees.',
                  actionLabel: 'Open plans',
                  onAction: () => AppShell.of(context).goTo(ShellTab.plan),
                )
              else
                for (var i = 0; i < outlook.planLines.length; i++)
                  FadeInUp.staggered(
                    index: i,
                    child: _LineCard(
                      line: outlook.planLines[i],
                      money: money,
                      total: outlook.requiredFor(_target),
                      accent: t.primary,
                      onTap: () => AppShell.of(context)
                          .push(BudgetDetailScreen(budgetId: outlook.planLines[i].id)),
                    ),
                  ),

              const Gap(S.md),
              SectionLabel(
                'YOUR RECURRING INCOME',
                hint: 'What your salary and side-income rules forecast, against the target above.',
              ),
              if (outlook.incomeLines.isEmpty)
                _EmptyHint(
                  icon: Icons.south_west_rounded,
                  title: 'No recurring income yet',
                  body: 'Add salary or side income so Santim can check coverage.',
                  actionLabel: 'Add income rule',
                  onAction: () => AppShell.of(context).push(const RecurringScreen()),
                )
              else
                for (var i = 0; i < outlook.incomeLines.length; i++)
                  FadeInUp.staggered(
                    index: i,
                    child: _LineCard(
                      line: outlook.incomeLines[i],
                      money: money,
                      total: outlook.forecastedIncome,
                      accent: t.success,
                    ),
                  ),

              const Gap(S.xl),
              AppButton(
                label: 'Edit recurring rules',
                icon: Icons.repeat_rounded,
                expand: true,
                variant: BtnVariant.outline,
                onPressed: () => AppShell.of(context).push(const RecurringScreen()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The headline: pick which question you are asking, get the number.
class _TargetHero extends StatelessWidget {
  const _TargetHero({
    required this.outlook,
    required this.money,
    required this.target,
    required this.cadence,
    required this.onTarget,
    required this.onCadence,
  });

  final MonthlyOutlook outlook;
  final String Function(Object?) money;
  final OutlookTarget target;
  final PayCadence cadence;
  final ValueChanged<OutlookTarget> onTarget;
  final ValueChanged<PayCadence> onCadence;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final need = outlook.requiredFor(target);
    final gap = outlook.gapFor(target);
    final coverage = outlook.coverageFor(target);
    final perPeriod = outlook.perPeriod(target, cadence);

    return AppCard(
      prominence: Prominence.hero,
      padding: const EdgeInsets.all(S.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Segmented<OutlookTarget>(
            value: target,
            options: OutlookTarget.values,
            labelOf: (v) => v.label,
            onChanged: onTarget,
          ),
          const Gap(S.lg),
          Muted(target.question, size: AppType.label),
          const Gap(S.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: AnimatedNumber(
                  value: perPeriod,
                  builder: (context, v) => Amount(
                    money(v),
                    size: AppType.display,
                    color: t.foreground,
                  ),
                ),
              ),
              const GapX(S.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: S.xs),
                child: Muted(cadence.label, size: AppType.label),
              ),
            ],
          ),
          if (cadence != PayCadence.monthly) ...[
            const Gap(S.xxs),
            Muted('${money(need)} per month', size: AppType.caption),
          ],
          const Gap(S.md),
          _Segmented<PayCadence>(
            value: cadence,
            options: PayCadence.values,
            labelOf: (v) => v.short,
            dense: true,
            onChanged: onCadence,
          ),

          if (outlook.forecastedIncome > 0) ...[
            const Gap(S.lg),
            ProgressBar(
              value: (coverage ?? 0).clamp(0, 100),
              label: '${target.label} target coverage',
              tone: (coverage ?? 0) >= 100
                  ? BadgeTone.success
                  : (coverage ?? 0) >= 80
                      ? BadgeTone.warning
                      : BadgeTone.danger,
            ),
            const Gap(S.sm),
            Row(
              children: [
                Expanded(
                  child: Muted(
                    coverage == null
                        ? 'Nothing to cover yet'
                        : '${coverage.round()}% covered by ${money(outlook.forecastedIncome)} of recurring income',
                    size: AppType.caption,
                    maxLines: 2,
                  ),
                ),
                const GapX(S.sm),
                AppBadge(
                  gap > 0 ? 'Short ${money(gap)}' : 'Spare ${money(-gap)}',
                  tone: gap > 0 ? BadgeTone.warning : BadgeTone.success,
                ),
              ],
            ),
          ] else ...[
            const Gap(S.md),
            Muted(
              'Add a recurring income rule to see whether this is covered.',
              size: AppType.caption,
              maxLines: 2,
            ),
          ],

          const Gap(S.md),
          Muted(outlook.confidence, size: AppType.caption, maxLines: 3),
        ],
      ),
    );
  }
}

/// Stacked bar: what each layer adds, and where the buffer came from.
class _LayerBreakdown extends StatelessWidget {
  const _LayerBreakdown({
    required this.outlook,
    required this.money,
    required this.target,
  });

  final MonthlyOutlook outlook;
  final String Function(Object?) money;
  final OutlookTarget target;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final total = outlook.requiredFor(OutlookTarget.comfortable);
    if (total <= 0) {
      return AppCard(
        child: Muted(
          'Add recurring bills and budget plans and this breaks the target into layers.',
          size: AppType.bodySm,
          maxLines: 3,
        ),
      );
    }

    final layers = <(String, double, Color, bool)>[
      ('Bills', outlook.floorSpend, t.danger, true),
      ('Plans', outlook.planSpend, t.primary, target != OutlookTarget.floor),
      (
        'Buffer',
        outlook.buffer,
        t.warning,
        target == OutlookTarget.comfortable,
      ),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitleRow(
            title: 'What builds the target',
            hint: 'Bills are recurring rules. Plans are envelope amounts, minus anything a '
                'bill already covers for the same category. The buffer is for surprises.',
          ),
          const Gap(S.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(R.pill),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (final (_, amount, color, active) in layers)
                    if (amount > 0)
                      Expanded(
                        flex: (amount / total * 1000).round().clamp(1, 1000),
                        child: Container(
                          color: active
                              ? color
                              : color.withValues(alpha: t.isDark ? 0.22 : 0.18),
                          child: const SizedBox.expand(),
                        ),
                      ),
                ],
              ),
            ),
          ),
          const Gap(S.md),
          for (final (label, amount, color, active) in layers) ...[
            _LayerRow(
              label: label,
              amount: amount,
              color: color,
              active: active,
              money: money,
              note: label == 'Buffer' ? _bufferNote(outlook) : null,
            ),
            if (label != 'Buffer') const Gap(S.sm),
          ],
        ],
      ),
    );
  }

  String _bufferNote(MonthlyOutlook o) => switch (o.bufferBasis) {
        BufferBasis.planned => 'the cushion you set on Unplanned',
        BufferBasis.median =>
          'median of ${o.bufferSampleMonths} completed ${o.bufferSampleMonths == 1 ? 'month' : 'months'}',
        BufferBasis.none => 'not set — add a cushion on Unplanned',
      };
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    required this.label,
    required this.amount,
    required this.color,
    required this.active,
    required this.money,
    this.note,
  });

  final String label;
  final double amount;
  final Color color;
  final bool active;
  final String Function(Object?) money;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Opacity(
      opacity: active ? 1 : 0.45,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const GapX(S.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppType.bodySm,
                    fontWeight: W.semibold,
                    color: t.foreground,
                  ),
                ),
                if (note != null) Muted(note!, size: AppType.caption, maxLines: 2),
                if (!active)
                  Muted('not in this target', size: AppType.caption),
              ],
            ),
          ),
          const GapX(S.sm),
          Amount(money(amount), size: AppType.bodySm),
        ],
      ),
    );
  }
}

/// When the bills are paid off within the month.
class _BreakEvenCard extends StatelessWidget {
  const _BreakEvenCard({required this.outlook});

  final MonthlyOutlook outlook;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final day = outlook.breakEvenDay;
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitleRow(
            title: 'Break-even day',
            icon: Icons.event_available_outlined,
            hint: 'The day of the month by which your recurring income has covered your '
                'recurring bills. Before it, you are running on last month\'s balance.',
          ),
          const Gap(S.md),
          if (day == null)
            Muted(
              outlook.forecastedIncome <= 0
                  ? 'Add a recurring income rule to find your break-even day.'
                  : 'Your recurring income never catches up with the bills inside the month. '
                      'Moving a bill\'s due date later, or a salary date earlier, would fix it.',
              size: AppType.bodySm,
              maxLines: 3,
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Amount('Day $day', size: AppType.figure, color: t.primary),
                const GapX(S.sm),
                Padding(
                  padding: const EdgeInsets.only(bottom: S.xxs),
                  child: Muted('of $daysInMonth', size: AppType.label),
                ),
              ],
            ),
            const Gap(S.md),
            // Simple month strip: red until break-even, green after.
            ClipRRect(
              borderRadius: BorderRadius.circular(R.pill),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    Expanded(flex: day, child: Container(color: t.danger.withValues(alpha: 0.5))),
                    Expanded(
                      flex: (daysInMonth - day).clamp(1, daysInMonth),
                      child: Container(color: t.success),
                    ),
                  ],
                ),
              ),
            ),
            const Gap(S.sm),
            Muted(
              now.day >= day
                  ? 'You are past it — the rest of the month is yours.'
                  : '${day - now.day} more ${day - now.day == 1 ? 'day' : 'days'} until the bills are covered.',
              size: AppType.caption,
              maxLines: 2,
            ),
          ],
        ],
      ),
    );
  }
}

/// Drag an income figure and see which targets it clears.
class _WhatIfCard extends StatelessWidget {
  const _WhatIfCard({
    required this.outlook,
    required this.money,
    required this.value,
    required this.onChanged,
    required this.onReset,
  });

  final MonthlyOutlook outlook;
  final String Function(Object?) money;
  final double? value;
  final ValueChanged<double> onChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final comfortable = outlook.requiredFor(OutlookTarget.comfortable);

    // Headroom above the biggest target so the slider can always reach "covered".
    final max = (comfortable * 1.5).clamp(1000, double.infinity).toDouble();
    final current = (value ?? outlook.forecastedIncome).clamp(0, max).toDouble();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitleRow(
            title: 'What if I earned…',
            icon: Icons.tune_rounded,
            hint: 'Drag to try an income. Nothing is saved — this only shows which targets '
                'that figure would clear.',
            trailingLabel: value == null ? null : 'Reset',
            onTrailingTap: value == null ? null : onReset,
          ),
          const Gap(S.sm),
          Amount(money(current), size: AppType.heading, color: t.primary),
          Slider(
            value: current,
            max: max,
            divisions: 60,
            activeColor: t.primary,
            inactiveColor: t.surfaceMuted,
            label: money(current),
            onChanged: onChanged,
          ),
          const Gap(S.sm),
          for (final target in OutlookTarget.values) ...[
            _WhatIfRow(
              target: target,
              need: outlook.requiredFor(target),
              income: current,
              money: money,
            ),
            if (target != OutlookTarget.values.last) const Gap(S.sm),
          ],
        ],
      ),
    );
  }
}

class _WhatIfRow extends StatelessWidget {
  const _WhatIfRow({
    required this.target,
    required this.need,
    required this.income,
    required this.money,
  });

  final OutlookTarget target;
  final double need;
  final double income;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final clears = need > 0 && income >= need;
    final colour = need <= 0
        ? t.mutedForeground
        : clears
            ? t.success
            : t.warning;

    return Semantics(
      label: '${target.label}, needs ${money(need)}, '
          '${clears ? 'covered' : 'short ${money(need - income)}'}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Icon(
              need <= 0
                  ? Icons.remove_circle_outline
                  : clears
                      ? Icons.check_circle_rounded
                      : Icons.cancel_outlined,
              size: 18,
              color: colour,
            ),
            const GapX(S.sm),
            Expanded(
              child: Text(
                target.label,
                style: TextStyle(
                  fontSize: AppType.bodySm,
                  fontWeight: W.semibold,
                  color: t.foreground,
                ),
              ),
            ),
            Muted(
              need <= 0
                  ? 'nothing to cover'
                  : clears
                      ? 'covered'
                      : 'short ${money(need - income)}',
              size: AppType.caption,
            ),
          ],
        ),
      ),
    );
  }
}

/// Were you actually covered, month by month?
class _CoverageHistoryCard extends StatelessWidget {
  const _CoverageHistoryCard({required this.history, required this.money});

  final OutlookHistory history;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final months = history.months;
    final peak = months.fold<double>(
      1,
      (m, x) => [m, x.income, x.expense].reduce((a, b) => a > b ? a : b),
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitleRow(
            title: 'Track record',
            icon: Icons.history_rounded,
            hint: 'Completed months only. A month counts as covered when income was at '
                'least as much as spending.',
          ),
          const Gap(S.md),
          Semantics(
            label: 'Covered ${history.coveredMonths} of ${months.length} completed months',
            child: ExcludeSemantics(
              child: SizedBox(
                height: 92,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final m in months)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: _Bar(
                                        fraction: m.income / peak,
                                        color: t.success,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Expanded(
                                      child: _Bar(
                                        fraction: m.expense / peak,
                                        color: t.danger.withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Gap(S.xs),
                              Muted(_shortMonth(m.month), size: AppType.micro, maxLines: 1),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const Gap(S.md),
          Row(
            children: [
              _Dot(color: t.success, label: 'In'),
              const GapX(S.md),
              _Dot(color: t.danger.withValues(alpha: 0.8), label: 'Out'),
              const Spacer(),
              AppBadge(
                '${history.coveredMonths}/${months.length} covered',
                tone: history.coveredMonths >= months.length - 1
                    ? BadgeTone.success
                    : BadgeTone.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _shortMonth(String yyyyMm) {
    final parts = yyyyMm.split('-');
    if (parts.length != 2) return yyyyMm;
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final m = int.tryParse(parts[1]);
    return m == null || m < 1 || m > 12 ? yyyyMm : names[m - 1];
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.color});
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
        heightFactor: fraction.isFinite ? fraction.clamp(0.02, 1.0) : 0.02,
        alignment: Alignment.bottomCenter,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ),
      );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const GapX(S.xxs),
          Muted(label, size: AppType.caption),
        ],
      );
}

/// Repeating payees with no rule — the fix for the data, not a guess bolted
/// onto the target.
class _RepeatCandidatesCard extends StatelessWidget {
  const _RepeatCandidatesCard({
    required this.outlook,
    required this.money,
    required this.onCreated,
  });

  final MonthlyOutlook outlook;
  final String Function(Object?) money;
  final VoidCallback onCreated;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final items = outlook.repeatCandidates.take(5).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitleRow(
            title: 'Looks like a commitment',
            icon: Icons.lightbulb_outline,
            hint: 'Payees seen repeatedly over the last '
                '${outlook.history?.patternWindowDays ?? 90} days with no recurring rule. '
                'They are not counted in the target — turning one into a rule is what '
                'makes the target sharper.',
          ),
          const Gap(S.md),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Gap(S.md),
            _CandidateRow(
              candidate: items[i],
              money: money,
              onMakeRule: () async {
                Haptics.select();
                final c = items[i];
                final saved = await showRecurringForm(
                  context,
                  prefill: RecurringPrefill(
                    name: c.payee,
                    amount: c.avgAmount,
                    kind: c.isExpense ? TxKind.expense : TxKind.income,
                    frequency: _frequencyFor(c.avgGapDays),
                    payee: c.payee,
                    categoryId: c.categoryId,
                  ),
                );
                if (saved == true) {
                  Haptics.commit();
                  onCreated();
                }
              },
            ),
          ],
          if (outlook.repeatCandidates.length > items.length) ...[
            const Gap(S.md),
            Muted(
              '${outlook.repeatCandidates.length - items.length} more not shown.',
              size: AppType.caption,
            ),
          ],
          const Gap(S.md),
          Container(
            padding: const EdgeInsets.all(S.md),
            decoration: BoxDecoration(
              color: t.surfaceMuted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Muted(
              'These are suggestions, not commitments — none of them move your income '
              'target until you make one a rule.',
              size: AppType.caption,
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }

  static Frequency _frequencyFor(int gapDays) {
    if (gapDays <= 2) return Frequency.daily;
    if (gapDays <= 10) return Frequency.weekly;
    if (gapDays <= 60) return Frequency.monthly;
    return Frequency.yearly;
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.money,
    required this.onMakeRule,
  });

  final RepeatCandidate candidate;
  final String Function(Object?) money;
  final VoidCallback onMakeRule;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                candidate.payee,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppType.bodySm,
                  fontWeight: W.semibold,
                  color: t.foreground,
                ),
              ),
              Muted(
                '${candidate.count}× · ${candidate.cadence} · '
                '~${money(candidate.monthlyAmount)}/mo',
                size: AppType.caption,
                maxLines: 2,
              ),
            ],
          ),
        ),
        const GapX(S.sm),
        AppButton(
          label: 'Make a rule',
          size: BtnSize.sm,
          variant: BtnVariant.outline,
          onPressed: onMakeRule,
        ),
      ],
    );
  }
}

/// Reusable pill segmented control.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onChanged,
    this.dense = false,
  });

  final T value;
  final List<T> options;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surfaceMuted.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: option == value,
                label: labelOf(option),
                child: ExcludeSemantics(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(option),
                    child: AnimatedContainer(
                      duration: Motion.fast,
                      curve: Motion.easeOut,
                      height: dense ? 32 : 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: option == value ? t.surface : Colors.transparent,
                        borderRadius: BorderRadius.circular(R.pill),
                        boxShadow: option == value ? t.cardShadow : null,
                      ),
                      child: Text(
                        labelOf(option),
                        style: TextStyle(
                          fontSize: dense ? AppType.caption : AppType.bodySm,
                          fontWeight: option == value ? W.bold : W.medium,
                          color: option == value ? t.foreground : t.mutedForeground,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActualVsExpected extends StatelessWidget {
  const _ActualVsExpected({
    required this.outlook,
    required this.money,
    required this.target,
  });

  final MonthlyOutlook outlook;
  final String Function(Object?) money;
  final OutlookTarget target;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final now = DateTime.now();
    final day = now.day;
    final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardTitleRow(
            title: 'So far this month',
            hint: 'What has actually happened, against the ${target.label} target.',
          ),
          const Gap(S.xxs),
          Muted(
            'Day $day of $daysInMonth · ${(day / daysInMonth * 100).round()}% through',
            size: AppType.label,
          ),
          const Gap(S.md),
          _CompareRow(
            label: 'Income received',
            actual: outlook.actualIncomeMtd,
            expected: outlook.requiredFor(target),
            money: money,
            color: t.success,
          ),
          const Gap(S.md),
          _CompareRow(
            label: 'Spending',
            actual: outlook.actualExpenseMtd,
            expected: outlook.requiredFor(target),
            money: money,
            color: t.danger,
            invertHealth: true,
          ),
        ],
      ),
    );
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({
    required this.label,
    required this.actual,
    required this.expected,
    required this.money,
    required this.color,
    this.invertHealth = false,
  });

  final String label;
  final double actual;
  final double expected;
  final String Function(Object?) money;
  final Color color;
  final bool invertHealth;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final ratio = expected <= 0 ? (actual > 0 ? 1.0 : 0.0) : (actual / expected).clamp(0.0, 1.5);
    final bar = ratio.clamp(0.0, 1.0);
    final healthy = invertHealth ? ratio <= 1.0 : ratio >= 0.85 || expected == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: AppType.label,
                fontWeight: W.semibold,
                color: t.mutedForeground,
              ),
            ),
            const Spacer(),
            Text(
              '${money(actual)} / ${money(expected)}',
              style: TextStyle(
                fontSize: AppType.label,
                fontWeight: W.bold,
                color: t.foreground,
              ),
            ),
          ],
        ),
        const Gap(S.xs),
        ProgressBar(
          value: bar * 100,
          label: label,
          tone: healthy ? BadgeTone.success : BadgeTone.warning,
          gradient: healthy ? [color, color] : null,
        ),
      ],
    );
  }
}

class _InsightsCard extends StatelessWidget {
  const _InsightsCard({required this.insights});
  final List<String> insights;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AppCard(
      color: t.accent.withValues(alpha: 0.06),
      borderColor: t.accent.withValues(alpha: 0.22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: t.accent),
              const GapX(S.sm),
              Text(
                'What this means',
                style: TextStyle(
                  fontSize: AppType.body,
                  fontWeight: W.heavy,
                  color: t.foreground,
                ),
              ),
            ],
          ),
          const Gap(S.sm),
          for (var i = 0; i < insights.length; i++) ...[
            if (i > 0) const Gap(S.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(top: S.xs),
                  decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
                ),
                const GapX(S.sm),
                Expanded(
                  child: Text(
                    insights[i],
                    style: TextStyle(fontSize: AppType.bodySm, height: 1.45, color: t.foreground),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.money,
    required this.total,
    required this.accent,
    this.onTap,
  });

  final OutlookLine line;
  final String Function(Object?) money;
  final double total;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final share = total <= 0 ? 0.0 : (line.monthlyAmount / total).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: S.sm),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.md),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(R.md),
                  ),
                  child: Icon(
                    line.kind == TxKind.income
                        ? Icons.south_west_rounded
                        : line.source == OutlookSource.budgetPlan
                            ? Icons.savings_outlined
                            : Icons.north_east_rounded,
                    size: 17,
                    color: accent,
                  ),
                ),
                const GapX(S.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.title,
                        style: TextStyle(
                          fontSize: AppType.body,
                          fontWeight: W.bold,
                          color: t.foreground,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (line.subtitle != null && line.subtitle!.isNotEmpty)
                        Muted(line.subtitle!, size: AppType.caption, maxLines: 2),
                    ],
                  ),
                ),
                const GapX(S.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Amount(money(line.displayAmount), size: AppType.body, color: accent),
                    Muted('/mo', size: AppType.micro),
                  ],
                ),
              ],
            ),

            // A plan whose category a bill already pays for contributes less
            // than its own amount — say so rather than letting the maths look
            // wrong.
            if (line.coveredByRule) ...[
              const Gap(S.sm),
              Row(
                children: [
                  Icon(Icons.merge_rounded, size: 14, color: t.warning),
                  const GapX(S.xs),
                  Expanded(
                    child: Muted(
                      line.monthlyAmount <= 0
                          ? 'Fully covered by a recurring bill — adds nothing to the target'
                          : 'Adds ${money(line.monthlyAmount)} on top of the recurring bill',
                      size: AppType.caption,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ],

            if (line.note != null &&
                line.note!.trim().isNotEmpty &&
                line.note != line.subtitle) ...[
              const Gap(S.sm),
              Text(
                line.note!,
                style: TextStyle(
                  fontSize: AppType.label,
                  height: 1.35,
                  fontStyle: FontStyle.italic,
                  color: t.mutedForeground,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const Gap(S.sm),
            Row(
              children: [
                if (line.cadence != null) _Tag(label: line.cadence!, color: t.mutedForeground),
                if (line.autoPost) ...[
                  const GapX(S.xs),
                  _Tag(label: 'Auto-post', color: t.primary),
                ],
                if (line.nextDate != null) ...[
                  const GapX(S.xs),
                  _Tag(label: 'Next ${formatDate(line.nextDate)}', color: t.accent),
                ],
                const Spacer(),
                Text(
                  '${(share * 100).round()}%',
                  style: TextStyle(
                    fontSize: AppType.caption,
                    fontWeight: W.bold,
                    color: t.mutedForeground,
                  ),
                ),
              ],
            ),
            const Gap(S.sm),
            ProgressBar(
              value: share * 100,
              height: 4,
              label: line.title,
              gradient: [accent.withValues(alpha: 0.85), accent],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.xxs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: AppType.caption, fontWeight: W.bold, color: color),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: S.sm),
      child: AppCard(
        child: Column(
          children: [
            Icon(icon, size: 28, color: context.t.mutedForeground),
            const Gap(S.sm),
            Text(
              title,
              style: TextStyle(
                fontSize: AppType.body,
                fontWeight: W.bold,
                color: context.t.foreground,
              ),
            ),
            const Gap(S.xxs),
            Muted(body, size: AppType.label, maxLines: 3),
            const Gap(S.md),
            AppButton(label: actionLabel, size: BtnSize.sm, onPressed: onAction),
          ],
        ),
      ),
    );
  }
}

/// Compact dashboard card — tap through to the full outlook.
class MonthlyOutlookCard extends StatefulWidget {
  const MonthlyOutlookCard({super.key});

  @override
  State<MonthlyOutlookCard> createState() => _MonthlyOutlookCardState();
}

class _MonthlyOutlookCardState extends State<MonthlyOutlookCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final data = context.read<DataState>();
      data.loadRecurring();
      data.loadBudgets();
      data.loadOutlookHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final data = context.watch<DataState>();
    final prefs = context.watch<PrefsState>();
    final currency = data.activeCurrency;
    final month = data.activeBreakdown?.month ?? data.dashboard.data?.month;

    final outlook = buildMonthlyOutlook(
      currency: currency,
      rules: data.recurring.data ?? const [],
      budgets: data.budgets.data?.items ?? const [],
      month: month,
      history: data.outlookHistory.data,
      topCategories: data.dashboard.data?.topCategories ?? const [],
    );

    String money(Object? v) => prefs.money(v, currency: currency);
    final shell = AppShell.of(context);

    // The card leads with Floor — the number that is true regardless of what
    // the user intends to do this month.
    final floor = outlook.requiredFor(OutlookTarget.floor);
    final steady = outlook.requiredFor(OutlookTarget.steady);
    final covered = outlook.coveredTarget;

    return AppCard(
      onTap: () => shell.push(const MonthlyOutlookScreen()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [t.primary, t.accent]),
                  borderRadius: BorderRadius.circular(R.md),
                ),
                child: Icon(Icons.insights_rounded, color: t.primaryForeground, size: 20),
              ),
              const GapX(S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monthly outlook',
                      style: TextStyle(
                        fontSize: AppType.body,
                        fontWeight: W.heavy,
                        color: t.foreground,
                      ),
                    ),
                    const Muted('What the month needs you to earn'),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: t.mutedForeground),
            ],
          ),
          const Gap(S.md),
          Row(
            children: [
              Expanded(
                child: _MiniFig(label: 'Bills', value: money(floor), color: t.danger),
              ),
              Container(width: 1, height: 36, color: t.border),
              Expanded(
                child: _MiniFig(label: '+ plans', value: money(steady), color: t.primary),
              ),
              Container(width: 1, height: 36, color: t.border),
              Expanded(
                child: _MiniFig(
                  label: 'You bring',
                  value: money(outlook.forecastedIncome),
                  color: t.success,
                ),
              ),
            ],
          ),
          if (!outlook.hasAnySignal)
            Padding(
              padding: const EdgeInsets.only(top: S.sm),
              child: const Muted(
                'Add bills and plans — Santim will work out the income you need.',
                maxLines: 2,
              ),
            )
          else ...[
            const Gap(S.md),
            ProgressBar(
              value: (outlook.coverageFor(OutlookTarget.steady) ?? 0).clamp(0, 100),
              height: 6,
              label: 'Steady target coverage',
              tone: covered == null
                  ? BadgeTone.danger
                  : covered == OutlookTarget.floor
                      ? BadgeTone.warning
                      : BadgeTone.success,
            ),
            const Gap(S.xs),
            Muted(
              switch (covered) {
                null => outlook.forecastedIncome <= 0
                    ? 'Add a salary rule to check coverage'
                    : 'Recurring income does not cover the bills yet',
                OutlookTarget.floor => 'Bills covered — plans are not yet',
                OutlookTarget.steady => 'Bills and plans covered',
                OutlookTarget.comfortable => 'Covered, with room for surprises',
              },
              size: AppType.caption,
              maxLines: 2,
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniFig extends StatelessWidget {
  const _MiniFig({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Muted(label, size: AppType.caption, maxLines: 1),
        const Gap(S.hair),
        Amount(value, size: AppType.bodySm, color: color),
      ],
    );
  }
}
