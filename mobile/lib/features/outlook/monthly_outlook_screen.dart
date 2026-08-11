import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/layout.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/utils/monthly_outlook.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../widgets/ui.dart';
import '../budgets/budget_detail_screen.dart';
import '../recurring/recurring_screen.dart';
import '../shell/app_shell.dart';

/// Full-screen monthly cashflow outlook — expected income, bills, plans, patterns.
class MonthlyOutlookScreen extends StatefulWidget {
  const MonthlyOutlookScreen({super.key});

  @override
  State<MonthlyOutlookScreen> createState() => _MonthlyOutlookScreenState();
}

class _MonthlyOutlookScreenState extends State<MonthlyOutlookScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final data = context.read<DataState>();
      await Future.wait([
        data.loadRecurring(),
        data.loadBudgets(),
        data.loadDashboard(),
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
      recentTransactions: data.dashboard.data?.recentTransactions ?? const [],
      month: month,
    );
    String money(Object? v) => prefs.money(v, currency: currency);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        foregroundColor: t.foreground,
        title: Text(
          'Monthly outlook',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.foreground),
        ),
        actions: [
          TextButton(
            onPressed: () => AppShell.of(context).push(const RecurringScreen()),
            child: Text('Manage', style: TextStyle(color: t.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: MeshBackground(
        child: RefreshIndicator(
          onRefresh: () => Future.wait([
            data.loadRecurring(force: true),
            data.loadBudgets(force: true),
            data.loadDashboard(force: true),
          ]),
          color: t.primary,
          child: ListView(
            padding: EdgeInsets.fromLTRB(14, 4, 14, ShellLayout.bottomClearance(context)),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              FadeInUp(child: _HeroOutlook(outlook: outlook, money: money)),
              const SizedBox(height: 14),
              FadeInUp(
                delay: const Duration(milliseconds: 40),
                child: _ActualVsExpected(outlook: outlook, money: money),
              ),
              if (outlook.insights.isNotEmpty) ...[
                const SizedBox(height: 14),
                FadeInUp(
                  delay: const Duration(milliseconds: 60),
                  child: _InsightsCard(insights: outlook.insights),
                ),
              ],
              const SizedBox(height: 18),
              SectionLabel('EXPECTED INCOME'),
              if (outlook.incomeLines.isEmpty)
                _EmptyHint(
                  icon: Icons.south_west_rounded,
                  title: 'No recurring income yet',
                  body: 'Add salary, side gigs, or allowances as recurring income so Santim can forecast.',
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
                      total: outlook.expectedIncome,
                      accent: t.success,
                    ),
                  ),
              const SizedBox(height: 14),
              SectionLabel('RECURRING BILLS'),
              if (outlook.expenseLines.isEmpty)
                _EmptyHint(
                  icon: Icons.north_east_rounded,
                  title: 'No recurring bills',
                  body: 'Rent, utilities, and subscriptions belong here — they shape free cash.',
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
                      total: outlook.committedSpend,
                      accent: t.danger,
                    ),
                  ),
              const SizedBox(height: 14),
              SectionLabel('BUDGET PLANS'),
              Muted(
                'Envelope plans you intend to fund — separate from auto-posting bills.',
                size: 12,
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              if (outlook.planLines.isEmpty)
                _EmptyHint(
                  icon: Icons.savings_outlined,
                  title: 'No active plans',
                  body: 'Create budget plans for groceries, transport, or school fees.',
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
                      total: outlook.plannedEnvelopes,
                      accent: t.primary,
                      onTap: () => AppShell.of(context).push(
                        BudgetDetailScreen(budgetId: outlook.planLines[i].id),
                      ),
                    ),
                  ),
              if (outlook.patternLines.isNotEmpty) ...[
                const SizedBox(height: 14),
                SectionLabel('FROM YOUR DETAILS'),
                Muted(
                  'Repeating payees or notes in recent transactions — candidates for recurring rules.',
                  size: 12,
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < outlook.patternLines.take(6).length; i++)
                  FadeInUp.staggered(
                    index: i,
                    child: _LineCard(
                      line: outlook.patternLines[i],
                      money: money,
                      total: outlook.patternLines.fold(0, (s, l) => s + l.monthlyAmount),
                      accent: t.accent,
                      soft: true,
                    ),
                  ),
              ],
              const SizedBox(height: 20),
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

class _HeroOutlook extends StatelessWidget {
  const _HeroOutlook({required this.outlook, required this.money});
  final MonthlyOutlook outlook;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    final outlook = this.outlook;
    final net = outlook.outlookNet;
    final spoken = outlook.spokenForPct;

    return GradientHero(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(R.pill),
                ),
                child: const Text(
                  'THIS MONTH',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                outlook.currency,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Expected income',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 4),
          Amount(
            money(outlook.expectedIncome),
            size: 34,
            color: Colors.white,
            weight: FontWeight.w800,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeroChip(
                  label: 'Bills',
                  value: money(outlook.committedSpend),
                  icon: Icons.north_east_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroChip(
                  label: 'Plans',
                  value: money(outlook.plannedEnvelopes),
                  icon: Icons.savings_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroChip(
                  label: net >= 0 ? 'Left' : 'Short',
                  value: money(net.abs()),
                  icon: net >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                ),
              ),
            ],
          ),
          if (spoken != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(R.pill),
              child: LinearProgressIndicator(
                value: (spoken / 100).clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                color: spoken >= 90
                    ? const Color(0xFFFCA5A5)
                    : spoken >= 60
                        ? const Color(0xFFFDE68A)
                        : Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${spoken.round()}% of expected income claimed by recurring bills',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActualVsExpected extends StatelessWidget {
  const _ActualVsExpected({required this.outlook, required this.money});
  final MonthlyOutlook outlook;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final day = DateTime.now().day;
    final daysInMonth = DateUtils.getDaysInMonth(DateTime.now().year, DateTime.now().month);
    final monthProgress = day / daysInMonth;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Actual so far vs outlook',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: t.foreground),
          ),
          const SizedBox(height: 4),
          Muted('Day $day of $daysInMonth · ${(monthProgress * 100).round()}% through the month', size: 12),
          const SizedBox(height: 14),
          _CompareRow(
            label: 'Income',
            actual: outlook.actualIncomeMtd,
            expected: outlook.expectedIncome,
            money: money,
            color: t.success,
          ),
          const SizedBox(height: 12),
          _CompareRow(
            label: 'Spending',
            actual: outlook.actualExpenseMtd,
            expected: outlook.committedSpend + outlook.plannedEnvelopes,
            money: money,
            color: t.danger,
            invertHealth: true,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: t.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.waterfall_chart_rounded, size: 18, color: t.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    outlook.freeAfterPlans >= 0
                        ? 'Flexible after bills & plans: ${money(outlook.freeAfterPlans)}'
                        : 'Over-committed by ${money(outlook.freeAfterPlans.abs())}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: t.foreground,
                    ),
                  ),
                ),
              ],
            ),
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
            Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: t.mutedForeground)),
            const Spacer(),
            Text(
              '${money(actual)} / ${money(expected)}',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: t.foreground),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(R.pill),
          child: LinearProgressIndicator(
            value: bar,
            minHeight: 8,
            backgroundColor: t.surfaceMuted,
            color: healthy ? color : t.warning,
          ),
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
      padding: const EdgeInsets.all(16),
      color: t.accent.withValues(alpha: 0.06),
      borderColor: t.accent.withValues(alpha: 0.22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: t.accent),
              const SizedBox(width: 8),
              Text(
                'What this means',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: t.foreground),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < insights.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    insights[i],
                    style: TextStyle(fontSize: 13, height: 1.45, color: t.foreground),
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
    this.soft = false,
  });

  final OutlookLine line;
  final String Function(Object?) money;
  final double total;
  final Color accent;
  final VoidCallback? onTap;
  final bool soft;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final share = total <= 0 ? 0.0 : (line.monthlyAmount / total).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                    color: accent.withValues(alpha: soft ? 0.1 : 0.14),
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
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: t.foreground,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (line.subtitle != null && line.subtitle!.isNotEmpty)
                        Muted(line.subtitle!, size: 11.5, maxLines: 2),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Amount(money(line.monthlyAmount), size: 14.5, color: accent),
                    Muted('/mo', size: 10.5),
                  ],
                ),
              ],
            ),
            if (line.note != null && line.note!.trim().isNotEmpty && line.note != line.subtitle) ...[
              const SizedBox(height: 8),
              Text(
                line.note!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  fontStyle: FontStyle.italic,
                  color: t.mutedForeground,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (line.cadence != null)
                  _Tag(label: line.cadence!, color: t.mutedForeground),
                if (line.autoPost) ...[
                  const SizedBox(width: 6),
                  _Tag(label: 'Auto-post', color: t.primary),
                ],
                if (line.nextDate != null) ...[
                  const SizedBox(width: 6),
                  _Tag(label: 'Next ${formatDate(line.nextDate)}', color: t.accent),
                ],
                if (line.source == OutlookSource.transactionPattern) ...[
                  const SizedBox(width: 6),
                  _Tag(label: 'From details', color: t.warning),
                ],
                const Spacer(),
                Text(
                  '${(share * 100).round()}%',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: t.mutedForeground),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(R.pill),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 4,
                backgroundColor: t.surfaceMuted,
                color: accent.withValues(alpha: 0.85),
              ),
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 28, color: context.t.mutedForeground),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: context.t.foreground,
              ),
            ),
            const SizedBox(height: 4),
            Muted(body, size: 12.5, maxLines: 3),
            const SizedBox(height: 12),
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
      recentTransactions: data.dashboard.data?.recentTransactions ?? const [],
      month: month,
    );
    String money(Object? v) => prefs.money(v, currency: currency);
    final shell = AppShell.of(context);

    return AppCard(
      padding: const EdgeInsets.all(16),
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
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.insights_rounded, color: t.primaryForeground, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monthly outlook',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: t.foreground,
                      ),
                    ),
                    Muted('Expected income, bills & plans', size: 12),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: t.mutedForeground),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MiniFig(
                  label: 'Expected in',
                  value: money(outlook.expectedIncome),
                  color: t.success,
                ),
              ),
              Container(width: 1, height: 36, color: t.border),
              Expanded(
                child: _MiniFig(
                  label: 'Bills',
                  value: money(outlook.committedSpend),
                  color: t.danger,
                ),
              ),
              Container(width: 1, height: 36, color: t.border),
              Expanded(
                child: _MiniFig(
                  label: outlook.outlookNet >= 0 ? 'Left' : 'Short',
                  value: money(outlook.outlookNet.abs()),
                  color: outlook.outlookNet >= 0 ? t.primary : t.warning,
                ),
              ),
            ],
          ),
          if (outlook.spokenForPct != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(R.pill),
              child: LinearProgressIndicator(
                value: (outlook.spokenForPct! / 100).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: t.surfaceMuted,
                color: outlook.spokenForPct! >= 90
                    ? t.danger
                    : outlook.spokenForPct! >= 60
                        ? t.warning
                        : t.primary,
              ),
            ),
            const SizedBox(height: 6),
            Muted(
              '${outlook.spokenForPct!.round()}% of expected income spoken for'
              '${outlook.planLines.isNotEmpty ? ' · ${outlook.planLines.length} plans' : ''}'
              '${outlook.patternLines.isNotEmpty ? ' · ${outlook.patternLines.length} patterns' : ''}',
              size: 11.5,
              maxLines: 2,
            ),
          ] else if (!outlook.hasAnySignal)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Muted(
                'Add recurring salary and bills to unlock your forecast.',
                size: 12,
                maxLines: 2,
              ),
            ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: context.t.mutedForeground,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}
