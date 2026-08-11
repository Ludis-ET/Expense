import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/prefs_state.dart';
import '../../widgets/charts.dart';
import '../../widgets/ui.dart';

typedef Money = String Function(Object? amount);

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

/// `HeroBalance` — greeting, both calendars, the available balance, and the
/// income/spent/saved chips over the gradient panel.
class HeroBalance extends StatelessWidget {
  const HeroBalance({
    super.key,
    required this.data,
    required this.money,
    required this.currency,
    required this.breakdown,
    this.userName,
    this.onManageAccounts,
  });

  final DashboardData data;
  final Money money;
  final String currency;
  final CurrencyBreakdown? breakdown;
  final String? userName;
  final VoidCallback? onManageAccounts;

  @override
  Widget build(BuildContext context) {
    final month = breakdown?.month ?? data.month;
    // Available money: what is in the accounts minus what budget plans hold.
    final balance = breakdown?.totalBalance ?? data.totalBalance;
    final locked = toNum(breakdown?.budgetLocked ?? data.budgetLocked);
    final accounts = data.accounts.where((a) => a.currency == currency).toList();

    final income = toNum(month.income);
    final expense = toNum(month.expense);
    final net = toNum(month.net);
    final savingsRate = income > 0 ? (net / income * 100).round() : null;

    final now = DateTime.now();
    final white = Colors.white;

    return GradientHero(
      padding: const EdgeInsets.fromLTRB(S.xl, S.xl, S.xl, S.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${greeting(now)}${userName != null ? ', $userName' : ''}',
                      style: TextStyle(
                        fontSize: AppType.bodySm,
                        fontWeight: FontWeight.w600,
                        color: white.withValues(alpha: 0.85),
                      ),
                    ),
                    const Gap(S.xs),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 11,
                          color: white.withValues(alpha: 0.7),
                        ),
                        const GapX(S.xxs),
                        Flexible(
                          child: Text(
                            formatLongDate(now),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppType.caption,
                              color: white.withValues(alpha: 0.75),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Gap(S.hair),
                    Text(
                      'ግዕዝ · ${formatEthiopian(now)}',
                      style: TextStyle(
                        fontSize: AppType.caption,
                        fontWeight: FontWeight.w600,
                        color: white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(R.md),
                ),
                child: Icon(Icons.account_balance_wallet_outlined, size: 19, color: white),
              ),
            ],
          ),
          const Gap(S.md),
          Text(
            'Available to spend · $currency',
            style: TextStyle(fontSize: AppType.caption, color: white.withValues(alpha: 0.65)),
          ),
          const Gap(S.xxs),
          AnimatedNumber(
            value: toNum(balance),
            builder: (context, v) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                money(v),
                style: TextStyle(
                  fontSize: AppType.hero,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1.4,
                  height: 1.1,
                  color: white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          if (locked > 0) ...[
            const Gap(S.xs),
            Text(
              '${money(breakdown?.realBalance ?? data.realBalance ?? balance)} in your accounts · '
              '${money(locked)} set aside in budget plans',
              style: TextStyle(
                fontSize: AppType.caption,
                height: 1.4,
                color: white.withValues(alpha: 0.78),
              ),
            ),
          ],
          if (data.convertedTotal != null &&
              !data.convertedTotal!.complete &&
              data.convertedTotal!.missingRates.isNotEmpty) ...[
            const Gap(S.xs),
            Text(
              'Other currencies are not included. Add exchange rates in Settings '
              'to see a combined total.',
              style: TextStyle(
                fontSize: AppType.caption,
                height: 1.4,
                color: white.withValues(alpha: 0.75),
              ),
            ),
          ],
          const Gap(S.lg),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroStat(
                icon: Icons.trending_up,
                label: 'Income',
                value: money(income),
                delta: month.incomeDeltaPct,
              ),
              _HeroStat(
                icon: Icons.trending_down,
                label: 'Spent',
                value: money(expense),
                delta: month.expenseDeltaPct,
              ),
              if (savingsRate != null) _HeroStat(label: 'Saved', value: '$savingsRate%'),
            ],
          ),
          if (accounts.isNotEmpty) ...[
            const Gap(S.md),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final a in accounts.take(4))
                  GlassChip(
                    radius: R.sm,
                    padding: const EdgeInsets.fromLTRB(S.md, S.xs, S.md, S.xs),
                    borderLeftColor: parseHexColor(a.color),
                    child: Text(
                      '${a.name}${a.isShared ? ' · shared' : ''}: ${money(a.balance)}',
                      style: TextStyle(
                        fontSize: AppType.caption,
                        fontWeight: FontWeight.w600,
                        color: white,
                      ),
                    ),
                  ),
                if (accounts.length > 4)
                  GlassChip(
                    radius: R.sm,
                    padding: const EdgeInsets.fromLTRB(S.md, S.xs, S.md, S.xs),
                    onTap: onManageAccounts,
                    child: Text(
                      '+${accounts.length - 4} more',
                      style: TextStyle(
                        fontSize: AppType.caption,
                        fontWeight: FontWeight.w600,
                        color: white,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const Gap(S.md),
          GestureDetector(
            onTap: onManageAccounts,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Manage accounts',
                  style: TextStyle(
                    fontSize: AppType.bodySm,
                    fontWeight: FontWeight.w600,
                    color: white.withValues(alpha: 0.85),
                  ),
                ),
                const GapX(S.xxs),
                Icon(Icons.arrow_forward, size: 13, color: white.withValues(alpha: 0.85)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value, this.icon, this.delta});

  final String label;
  final String value;
  final IconData? icon;
  final double? delta;

  @override
  Widget build(BuildContext context) {
    final white = Colors.white;
    return GlassChip(
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: white.withValues(alpha: 0.8)),
            const GapX(S.xs),
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: AppType.micro,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: white.withValues(alpha: 0.7),
                ),
              ),
              const Gap(S.hair),
              Text(
                value,
                style: TextStyle(
                  fontSize: AppType.bodySm,
                  fontWeight: FontWeight.w700,
                  color: white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (delta != null) ...[
            const GapX(S.xs),
            Text(
              formatPct(delta),
              style: TextStyle(
                fontSize: AppType.caption,
                fontWeight: FontWeight.w600,
                color: white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Financial health
// ---------------------------------------------------------------------------

class HealthFactor {
  const HealthFactor({
    required this.label,
    required this.score,
    required this.detail,
    required this.icon,
  });

  final String label;

  /// 0–100, or null when there is not enough data to judge.
  final double? score;

  /// The real figure the score came from, shown under the label.
  final String detail;
  final IconData icon;
}

/// `FinancialHealth`. Every factor is derived from live figures and shows the
/// number behind it, so the score is auditable rather than a vibe. A factor
/// with nothing to measure scores null and is left out of the average.
class FinancialHealthCard extends StatelessWidget {
  const FinancialHealthCard({super.key, required this.data, required this.money});

  final DashboardData data;
  final Money money;

  static double _clamp(double n) => n.clamp(0, 100).roundToDouble();

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final income = toNum(data.month.income);
    final expense = toNum(data.month.expense);
    final net = toNum(data.month.net);
    final unnecessary = toNum(data.unnecessary.total);

    // 1. Savings rate: what share of income you kept this month. 20% saved is
    //    the common target, so that maps to a full score.
    final savingsRate = income > 0 ? net / income * 100 : null;
    final savings = HealthFactor(
      label: 'Savings rate',
      score: savingsRate == null ? null : _clamp(savingsRate / 20 * 100),
      detail: savingsRate == null
          ? 'no income yet this month'
          : '${savingsRate.round()}% of ${money(income)} kept',
      icon: Icons.trending_up,
    );

    // 2. Plan health: are your active plans still holding money?
    final atRisk = data.budgetsAtRisk.length;
    final activePlans = data.budgetTotals.activeCount;
    final plans = HealthFactor(
      label: 'Plans',
      score: activePlans == 0 ? null : _clamp((activePlans - atRisk) / activePlans * 100),
      detail: activePlans == 0
          ? 'no plans yet'
          : atRisk == 0
          ? 'all $activePlans on track'
          : '$atRisk of $activePlans running low',
      icon: Icons.shield_outlined,
    );

    // 3. Funding: how much of what you planned is actually set aside.
    final planned = toNum(data.budgetTotals.planned);
    final funded = toNum(data.budgetTotals.funded);
    final funding = HealthFactor(
      label: 'Funded',
      score: planned == 0 ? null : _clamp(funded / planned * 100),
      detail: planned == 0
          ? 'nothing planned yet'
          : '${money(funded)} of ${money(planned)} set aside',
      icon: Icons.savings_outlined,
    );

    // 4. Discipline: 10% of spend on impulse buys zeroes it out.
    final wasteShare = expense > 0 ? unnecessary / expense * 100 : null;
    final discipline = HealthFactor(
      label: 'Discipline',
      score: wasteShare == null ? null : _clamp(100 - wasteShare * 10),
      detail: wasteShare == null
          ? 'no spending yet this month'
          : unnecessary == 0
          ? 'nothing flagged unnecessary'
          : '${money(unnecessary)} unnecessary (${wasteShare.round()}%)',
      icon: Icons.monitor_heart_outlined,
    );

    final factors = [savings, plans, funding, discipline];
    final scored = factors.where((f) => f.score != null).toList();
    final score = scored.isEmpty
        ? null
        : (scored.fold<double>(0, (s, f) => s + f.score!) / scored.length).round();

    final (label, color) = switch (score) {
      null => ('Not enough data', t.mutedForeground),
      >= 80 => ('Excellent', t.success),
      >= 60 => ('Good', t.primary),
      >= 40 => ('Fair', t.warning),
      _ => ('Needs attention', t.danger),
    };

    return AppCard(
      padding: const EdgeInsets.all(S.xl),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Financial health',
                style: TextStyle(
                  fontSize: AppType.bodySm,
                  fontWeight: FontWeight.w600,
                  color: t.mutedForeground,
                ),
              ),
              const Spacer(),
              InfoHint(
                label: 'Financial health',
                body:
                    'Averaged over the ${scored.length} factor'
                    '${scored.length == 1 ? '' : 's'} there is data for. '
                    'Each factor shows the real figure it came from.',
                size: 15,
              ),
            ],
          ),
          const Gap(S.lg),
          SizedBox(
            width: 124,
            height: 124,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: (score ?? 0) / 100),
                  duration: const Duration(milliseconds: 1000),
                  curve: Motion.easeOut,
                  builder: (context, v, _) => CustomPaint(
                    size: const Size.square(124),
                    painter: RingPainter(
                      progress: v,
                      trackColor: t.surfaceMuted,
                      colors: [t.primary, t.accent],
                      strokeWidth: 9,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      score?.toString() ?? '-',
                      style: TextStyle(
                        fontSize: AppType.display,
                        fontWeight: FontWeight.bold,
                        color: t.foreground,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: AppType.caption,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Gap(S.lg),
          for (final f in factors)
            Padding(
              padding: const EdgeInsets.only(bottom: S.xs),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
                decoration: BoxDecoration(
                  color: t.surfaceMuted.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(R.sm + 2),
                ),
                child: Row(
                  children: [
                    Icon(f.icon, size: 15, color: t.mutedForeground),
                    const GapX(S.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f.label,
                            style: TextStyle(
                              fontSize: AppType.caption,
                              fontWeight: FontWeight.w600,
                              color: t.foreground,
                            ),
                          ),
                          Muted(f.detail, size: 10, maxLines: 1),
                        ],
                      ),
                    ),
                    const GapX(S.sm),
                    if (f.score == null)
                      Muted('-', size: 10)
                    else ...[
                      SizedBox(
                        width: 34,
                        child: ProgressBar(
                          value: f.score!,
                          height: 4,
                          gradient: [
                            f.score! >= 70
                                ? t.success
                                : f.score! >= 40
                                ? t.primary
                                : t.warning,
                            f.score! >= 70
                                ? t.success
                                : f.score! >= 40
                                ? t.accent
                                : t.warning,
                          ],
                        ),
                      ),
                      const GapX(S.xs),
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${f.score!.round()}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: AppType.caption,
                            fontWeight: FontWeight.w700,
                            color: t.foreground,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small widgets
// ---------------------------------------------------------------------------

/// `SmartInsight` — the single most useful sentence the data supports.
class SmartInsightCard extends StatelessWidget {
  const SmartInsightCard({super.key, required this.data, required this.money});

  final DashboardData data;
  final Money money;

  String _insight() {
    final net = toNum(data.month.net);
    final income = toNum(data.month.income);

    final drained = data.budgetsAtRisk.where((b) => b.health == BudgetHealth.drained).length;
    if (drained > 0) {
      return '$drained budget plan${drained > 1 ? 's are' : ' is'} empty - '
          'top up or hold off until the next cycle.';
    }
    if (data.budgetsAtRisk.isNotEmpty) {
      final n = data.budgetsAtRisk.length;
      return '$n budget plan${n > 1 ? 's are' : ' is'} running low.';
    }
    if (toNum(data.budgetLocked) > 0) {
      return '${money(data.budgetLocked)} is set aside in budget plans and '
          'excluded from your available balance.';
    }
    if (income > 0 && net / income < 0.1) {
      return 'Your savings rate is below 10% this month. '
          'Consider cutting unnecessary expenses.';
    }
    if (net > 0) return "You're saving ${money(net)} this month - keep it up!";
    if (toNum(data.unnecessary.total) > 0) {
      return '${money(data.unnecessary.total)} went to "unnecessary" spending.';
    }
    if (data.categoryHeatAlerts.isNotEmpty) {
      final a = data.categoryHeatAlerts.first;
      return '${a.category?.name} spending is up ${a.deltaPct.round()}% vs last month.';
    }
    if (data.tab.openCount > 0) {
      final forecast = toNum(data.tab.netIfOnTime);
      if (forecast > 0) {
        return 'Your Money Tab forecast: +${money(forecast)} if due items settle this month.';
      }
      if (forecast < 0) {
        return 'Your Money Tab forecast: ${money(forecast)} outflow if due tabs settle this month.';
      }
      if (data.tab.overdueCount > 0) {
        final n = data.tab.overdueCount;
        return '$n Money Tab item${n > 1 ? 's are' : ' is'} overdue.';
      }
    }
    return 'Add transactions and set budgets to unlock personalized insights.';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final month = data.month;
    final net = toNum(month.net);
    final insight = _insight();

    return GlassCard(
      padding: const EdgeInsets.all(S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(icon: Icons.lightbulb_outline, color: t.primary, size: 36),
              const GapX(S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow('Smart insight'),
                    const Gap(S.xxs),
                    Text(
                      insight,
                      style: TextStyle(fontSize: AppType.bodySm, height: 1.5, color: t.foreground),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Gap(S.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
            decoration: BoxDecoration(
              color: t.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Row(
              children: [
                Icon(
                  net >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  size: 15,
                  color: net >= 0 ? t.success : t.danger,
                ),
                const GapX(S.sm),
                Expanded(
                  child: Text(
                    'Net this month · ${money(month.net)}',
                    style: TextStyle(
                      fontSize: AppType.caption,
                      fontWeight: FontWeight.w700,
                      color: t.foreground,
                    ),
                  ),
                ),
                Text(
                  'Swipe →',
                  style: TextStyle(
                    fontSize: AppType.micro,
                    fontWeight: FontWeight.w700,
                    color: t.mutedForeground,
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

/// `WeeklySnapshot` — this week against last, from the stored Sunday-boundary
/// snapshots. Bars compare both weeks on whichever spent more.
class WeeklySnapshotCard extends StatelessWidget {
  const WeeklySnapshotCard({super.key, required this.data, required this.prefs});

  final WeeklySnapshot data;
  final PrefsState prefs;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cur = data.current;
    final prev = data.previous;
    final spentMore = toNum(data.expenseAmount) > 0;
    final peak = math.max(math.max(toNum(cur.expense), toNum(prev.expense)), 1);

    String money(Object? v, {bool compact = false}) =>
        prefs.money(v, currency: data.currency, compact: compact);

    return AppCard(
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
                    Text(
                      'Weekly snapshot',
                      style: TextStyle(
                        fontSize: AppType.bodySm,
                        fontWeight: FontWeight.w600,
                        color: t.mutedForeground,
                      ),
                    ),
                    const Gap(S.hair),
                    Muted(
                      '${formatDayMonth(cur.weekStart)} - '
                      '${formatDayMonth(cur.weekEnd.subtract(const Duration(days: 1)))}',
                      size: 10.5,
                    ),
                  ],
                ),
              ),
              Icon(Icons.calendar_month_outlined, size: 16, color: t.mutedForeground),
            ],
          ),
          const Gap(S.md),
          _MiniRow(
            label: 'Income',
            value: money(cur.income),
            delta: data.incomeDelta,
            goodWhenUp: true,
          ),
          const Gap(S.xs),
          _MiniRow(
            label: 'Spent',
            value: money(cur.expense),
            delta: data.expenseDelta,
            goodWhenUp: false,
          ),
          const Gap(S.xs),
          _MiniRow(
            label: 'Net',
            value: money(cur.net),
            emphasise: true,
            tone: toNum(cur.net) >= 0 ? t.success : t.danger,
          ),
          const Gap(S.md),
          Divider(color: t.border, height: 1),
          const Gap(S.md),
          _CompareBar(
            label: 'This week',
            value: money(cur.expense, compact: true),
            pct: math.max(2, toNum(cur.expense) / peak * 100),
            active: true,
          ),
          const Gap(S.sm),
          _CompareBar(
            label: 'Last week',
            value: money(prev.expense, compact: true),
            pct: math.max(2, toNum(prev.expense) / peak * 100),
          ),
          const Gap(S.md),
          if (toNum(prev.expense) == 0 && toNum(cur.expense) == 0)
            Muted('No spending either week.', size: 11, height: 1.4)
          else
            RichText(
              text: TextSpan(
                style: TextStyle(fontSize: AppType.caption, height: 1.45, color: t.mutedForeground),
                children: [
                  const TextSpan(text: 'You have spent '),
                  TextSpan(
                    text:
                        '${money(toNum(data.expenseAmount).abs(), compact: true)} '
                        '${spentMore ? 'more' : 'less'}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: spentMore ? t.warning : t.success,
                    ),
                  ),
                  const TextSpan(text: ' than last week'),
                  if (cur.topCategory != null) TextSpan(text: ' · mostly ${cur.topCategory}'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniRow extends StatelessWidget {
  const _MiniRow({
    required this.label,
    required this.value,
    this.delta,
    this.goodWhenUp,
    this.emphasise = false,
    this.tone,
  });

  final String label;
  final String value;
  final double? delta;
  final bool? goodWhenUp;
  final bool emphasise;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final positive = delta == null || goodWhenUp == null
        ? null
        : (goodWhenUp! ? delta! >= 0 : delta! <= 0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
      decoration: BoxDecoration(
        color: t.surfaceMuted.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Row(
        children: [
          Eyebrow(label),
          const Spacer(),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Amount(value, size: emphasise ? 14.5 : 13, color: tone ?? t.foreground),
            ),
          ),
          if (delta != null) ...[
            const GapX(S.xs),
            Text(
              formatPct(delta),
              style: TextStyle(
                fontSize: AppType.caption,
                fontWeight: FontWeight.w700,
                color: positive == null
                    ? t.mutedForeground
                    : positive
                    ? t.success
                    : t.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompareBar extends StatelessWidget {
  const _CompareBar({
    required this.label,
    required this.value,
    required this.pct,
    this.active = false,
  });

  final String label;
  final String value;
  final double pct;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Muted(label, size: 10.5),
            const Spacer(),
            Amount(value, size: 11, weight: FontWeight.w600),
          ],
        ),
        const Gap(S.xxs),
        ProgressBar(
          value: pct,
          height: 5,
          gradient: active ? null : [t.mutedForeground, t.mutedForeground],
        ),
      ],
    );
  }
}

/// `SpendingStreaks` — the run of days under the average daily pace, with the
/// full window as a dot strip so broken days stay visible.
class SpendingStreaksCard extends StatelessWidget {
  const SpendingStreaksCard({super.key, required this.data, required this.prefs});

  final SpendingStreak data;
  final PrefsState prefs;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Spending streak',
                style: TextStyle(
                  fontSize: AppType.bodySm,
                  fontWeight: FontWeight.w600,
                  color: t.mutedForeground,
                ),
              ),
              const Spacer(),
              Icon(Icons.local_fire_department_outlined, size: 16, color: t.warning),
            ],
          ),
          const Gap(S.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Amount('${data.currentDays}', size: 30),
              const GapX(S.xs),
              Padding(
                padding: const EdgeInsets.only(bottom: S.xxs),
                child: Muted('day${data.currentDays == 1 ? '' : 's'} under pace', size: 11.5),
              ),
            ],
          ),
          const Gap(S.xxs),
          Muted(
            'Pace ${prefs.money(data.avgDailySpend, currency: data.currency)}/day · '
            'best ${data.bestStreak}',
            size: 11,
          ),
          const Gap(S.md),
          SpendStrip(days: [for (final d in data.days) (d.under, d.spent)]),
          const Gap(S.md),
          Muted('${data.daysUnder} of ${data.dayCount} days under · ${data.label}', size: 10.5),
        ],
      ),
    );
  }
}

/// `TabWidget` — open lends and borrows with the settle-on-time forecast.
class TabWidgetCard extends StatelessWidget {
  const TabWidgetCard({super.key, required this.tab, required this.money, this.onOpen});

  final LedgerSummary tab;
  final Money money;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final net = toNum(tab.netPosition);

    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Money Tab',
                style: TextStyle(
                  fontSize: AppType.bodySm,
                  fontWeight: FontWeight.w600,
                  color: t.mutedForeground,
                ),
              ),
              const Spacer(),
              if (tab.overdueCount > 0)
                AppBadge('${tab.overdueCount} overdue', tone: BadgeTone.danger, dense: true)
              else
                Icon(Icons.volunteer_activism_outlined, size: 16, color: t.mutedForeground),
            ],
          ),
          const Gap(S.md),
          Amount(money(net.abs()), size: 24, color: net >= 0 ? t.success : t.danger),
          const Gap(S.hair),
          Muted(net >= 0 ? 'owed to you, net' : 'you owe, net', size: 11),
          const Gap(S.md),
          Row(
            children: [
              Expanded(
                child: _TinyStat(
                  label: 'Owed to you',
                  value: money(tab.receivable),
                  color: t.success,
                ),
              ),
              const GapX(S.sm),
              Expanded(
                child: _TinyStat(label: 'You owe', value: money(tab.payable), color: t.danger),
              ),
            ],
          ),
          if (tab.openCount > 0) ...[
            const Gap(S.sm),
            Muted(
              '${tab.openCount} open · forecast ${money(tab.netIfOnTime)} if all settle',
              size: 10.5,
              maxLines: 2,
            ),
          ],
        ],
      ),
    );
  }
}

class _TinyStat extends StatelessWidget {
  const _TinyStat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
      decoration: BoxDecoration(
        color: t.surfaceMuted.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(R.sm + 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Muted(label, size: 10, maxLines: 1),
          const Gap(S.hair),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Amount(value, size: 13, color: color),
          ),
        ],
      ),
    );
  }
}

/// `WishlistWidget` — a want is just the idea of a thing, so this counts them
/// rather than showing money.
class WishlistWidgetCard extends StatelessWidget {
  const WishlistWidgetCard({super.key, required this.wishlist, this.onOpen});

  final WishlistDigest wishlist;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Wishlist',
                style: TextStyle(
                  fontSize: AppType.bodySm,
                  fontWeight: FontWeight.w600,
                  color: t.mutedForeground,
                ),
              ),
              const Spacer(),
              Icon(Icons.favorite_border, size: 16, color: t.mutedForeground),
            ],
          ),
          const Gap(S.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Amount('${wishlist.activeCount}', size: 30),
              const GapX(S.xs),
              Padding(
                padding: const EdgeInsets.only(bottom: S.xxs),
                child: Muted('want${wishlist.activeCount == 1 ? '' : 's'}', size: 11.5),
              ),
            ],
          ),
          const Gap(S.xxs),
          Muted('${wishlist.plannedCount} turned into a plan', size: 11),
          if (wishlist.top.isNotEmpty) ...[
            const Gap(S.md),
            for (final w in wishlist.top.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: S.xs),
                child: Row(
                  children: [
                    Text(w.emoji ?? '✨', style: const TextStyle(fontSize: AppType.bodySm)),
                    const GapX(S.xs),
                    Expanded(
                      child: Text(
                        w.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: AppType.label, color: t.foreground),
                      ),
                    ),
                    if (w.plan != null) AppBadge('planned', tone: BadgeTone.primary, dense: true),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// `CategoryHeatAlerts` — categories running hotter than last month.
class CategoryHeatCard extends StatelessWidget {
  const CategoryHeatCard({super.key, required this.alerts, required this.money});

  final List<CategoryHeatAlert> alerts;
  final Money money;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitleRow(
            title: 'Heating up',
            icon: Icons.local_fire_department_outlined,
            hint: 'Categories where this month is well ahead of last month.',
          ),
          const Gap(S.md),
          if (alerts.isEmpty)
            const EmptyState(
              title: 'Nothing is spiking',
              description: 'No category is far ahead of last month.',
              compact: true,
            )
          else
            for (var i = 0; i < alerts.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == alerts.length - 1 ? 0 : 9),
                child: FadeInUp.staggered(
                  index: i,
                  offset: 6,
                  child: Row(
                    children: [
                      IconTile(
                        icon: financeIcon(alerts[i].category?.icon),
                        color: parseHexColor(alerts[i].category?.color),
                        size: 34,
                      ),
                      const GapX(S.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alerts[i].category?.name ?? 'Uncategorised',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppType.bodySm,
                                fontWeight: FontWeight.w600,
                                color: t.foreground,
                              ),
                            ),
                            Muted(
                              '${money(alerts[i].amount)} vs ${money(alerts[i].prevAmount)}',
                              size: 11,
                            ),
                          ],
                        ),
                      ),
                      AppBadge(
                        formatPct(alerts[i].deltaPct),
                        tone: switch (alerts[i].severity) {
                          'high' => BadgeTone.danger,
                          'medium' => BadgeTone.warning,
                          _ => BadgeTone.neutral,
                        },
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// `FamilySupportTracker` — money sent to family, a first-class category in
/// the Ethiopian context this app was built for.
class FamilySupportCard extends StatelessWidget {
  const FamilySupportCard({super.key, required this.data, required this.money});

  final FamilySupportStats data;
  final Money money;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final total = toNum(data.total);

    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitleRow(
            title: data.category?.name ?? 'Family support',
            icon: Icons.volunteer_activism_outlined,
            hint: 'What you have sent this month, against last month.',
          ),
          const Gap(S.md),
          if (total == 0 && data.recent.isEmpty)
            const EmptyState(title: 'Nothing sent this month', compact: true)
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Amount(money(total), size: 24),
                const GapX(S.sm),
                if (data.deltaPct != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: S.xxs),
                    child: AppBadge(
                      formatPct(data.deltaPct),
                      tone: data.deltaPct! > 0 ? BadgeTone.warning : BadgeTone.success,
                      dense: true,
                    ),
                  ),
              ],
            ),
            const Gap(S.xxs),
            Muted(
              '${data.count} transfer${data.count == 1 ? '' : 's'} · '
              'last month ${money(data.prevTotal)}',
              size: 11,
            ),
            if (data.recent.isNotEmpty) ...[
              const Gap(S.md),
              for (final tx in data.recent.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: S.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tx.payee ?? tx.note ?? 'Transfer',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppType.label, color: t.foreground),
                        ),
                      ),
                      Muted(formatDayMonth(tx.date), size: 11),
                      const GapX(S.sm),
                      Amount(money(tx.amount), size: 12.5),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

/// `HouseholdWidget` — shared wallets and the partners who can see them.
class HouseholdCard extends StatelessWidget {
  const HouseholdCard({super.key, required this.household, required this.money});

  final HouseholdOverview household;
  final Money money;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitleRow(
            title: household.name,
            icon: Icons.group_outlined,
            hint: 'Shared wallets are visible to everyone in the household.',
          ),
          const Gap(S.md),
          Row(
            children: [
              for (final m in household.members)
                Padding(
                  padding: const EdgeInsets.only(right: S.sm),
                  child: Column(
                    children: [
                      Avatar(name: m.name, avatarId: m.avatarId, size: 34),
                      const Gap(S.xxs),
                      Text(
                        m.isYou ? 'You' : m.name.split(' ').first,
                        style: TextStyle(fontSize: AppType.micro, color: t.mutedForeground),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Amount(money(household.sharedBalance), size: 17),
                  Muted('shared balance', size: 10.5),
                ],
              ),
            ],
          ),
          if (household.sharedAccounts.isNotEmpty) ...[
            const Gap(S.md),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final a in household.sharedAccounts)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.xs),
                    decoration: BoxDecoration(
                      color: t.surfaceMuted.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(R.sm),
                      border: Border(
                        left: BorderSide(color: parseHexColor(a.color) ?? t.primary, width: 3),
                      ),
                    ),
                    child: Text(
                      a.name,
                      style: TextStyle(
                        fontSize: AppType.caption,
                        fontWeight: FontWeight.w600,
                        color: t.foreground,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (household.pendingInvites > 0) ...[
            const Gap(S.sm),
            Muted('${household.pendingInvites} invite pending', size: 11),
          ],
        ],
      ),
    );
  }
}

/// `SpendingPace` — where the month's spend sits against a straight-line
/// budget for the days elapsed.
class SpendingPaceCard extends StatelessWidget {
  const SpendingPaceCard({super.key, required this.month, required this.money});

  final MonthSummary month;
  final Money money;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final elapsed = now.day;
    final expense = toNum(month.expense);
    final income = toNum(month.income);

    // Straight-line pace: if you keep spending like this, where do you land?
    final projected = elapsed == 0 ? 0.0 : expense / elapsed * daysInMonth;
    final onTrack = income <= 0 || projected <= income;
    final pctOfMonth = elapsed / daysInMonth * 100;
    final pctSpent = income > 0 ? (expense / income * 100).clamp(0, 200).toDouble() : 0.0;

    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitleRow(
            title: 'Spending pace',
            icon: Icons.speed_outlined,
            hint:
                'Projects the month from what you have spent so far. '
                'It assumes the rest of the month looks like the part already gone.',
          ),
          const Gap(S.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Muted('Spent so far', size: 11),
                    const Gap(S.hair),
                    Amount(money(expense), size: 20),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Muted('On this pace', size: 11),
                  const Gap(S.hair),
                  Amount(money(projected), size: 20, color: onTrack ? t.foreground : t.danger),
                ],
              ),
            ],
          ),
          const Gap(S.md),
          Stack(
            alignment: Alignment.centerLeft,
            children: [
              ProgressBar(
                value: pctSpent,
                height: 10,
                tone: !onTrack
                    ? BadgeTone.danger
                    : pctSpent > pctOfMonth
                    ? BadgeTone.warning
                    : BadgeTone.primary,
              ),
              // The day marker: where a straight-line budget would be today.
              if (income > 0)
                FractionallySizedBox(
                  widthFactor: (pctOfMonth / 100).clamp(0.0, 1.0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: 2,
                      height: 14,
                      decoration: BoxDecoration(
                        color: t.foreground.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const Gap(S.sm),
          Row(
            children: [
              Muted('Day $elapsed of $daysInMonth', size: 11),
              const Spacer(),
              Muted(
                income > 0
                    ? '${pctSpent.round()}% of income spent'
                    : 'Avg ${money(month.avgDailySpend)}/day',
                size: 11,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The 2×2 mini stat grid under the widgets.
class StatMini extends StatelessWidget {
  const StatMini({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.hint,
    this.positive,
    this.warning = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? hint;
  final bool? positive;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = positive == true
        ? t.success
        : positive == false
        ? t.danger
        : warning
        ? t.warning
        : t.foreground;

    return AppCard(
      padding: const EdgeInsets.all(S.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Muted(label, size: 11.5, maxLines: 1)),
              Icon(icon, size: 14, color: t.mutedForeground),
            ],
          ),
          const Gap(S.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Amount(value, size: 18, color: color),
          ),
          if (hint != null) ...[const Gap(S.hair), Muted(hint!, size: 9.5)],
        ],
      ),
    );
  }
}
