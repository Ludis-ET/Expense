import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/prefs_state.dart';
import '../../widgets/charts.dart';
import '../../widgets/ui.dart';
import 'dashboard_layout.dart';

typedef Money = String Function(Object? amount);

// ---------------------------------------------------------------------------
// Worth-knowing peeks   uniform shell + detail sheet
// ---------------------------------------------------------------------------

/// Shared chrome for carousel insight tiles: fills [kInsightPeekHeight],
/// keeps content density even, and opens a detail sheet on tap.
class InsightPeekFrame extends StatelessWidget {
  const InsightPeekFrame({
    super.key,
    required this.icon,
    required this.eyebrow,
    required this.child,
    required this.onOpen,
    this.accent,
    this.cta = 'Tap for details',
  });

  final IconData icon;
  final String eyebrow;
  final Widget child;
  final VoidCallback onOpen;
  final Color? accent;
  final String cta;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = accent ?? t.primary;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.md),
      onTap: () {
        Haptics.select();
        onOpen();
      },
      child: SizedBox.expand(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const GapX(S.sm),
                Expanded(
                  child: Text(
                    eyebrow,
                    style: TextStyle(
                      fontSize: AppType.label,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: t.mutedForeground,
                    ),
                  ),
                ),
                Icon(
                  Icons.fullscreen_rounded,
                  size: 16,
                  color: t.mutedForeground,
                ),
              ],
            ),
            const Gap(S.sm),
            Expanded(child: child),
            const Gap(S.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: S.md,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(R.pill),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    cta,
                    style: TextStyle(
                      fontSize: AppType.caption,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const GapX(S.xs),
                  Icon(Icons.arrow_forward_rounded, size: 14, color: color),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _openInsightSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Widget Function(BuildContext) builder,
}) {
  showAppSheet(
    context,
    title: title,
    subtitle: subtitle,
    scrollable: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(S.xl, 0, S.xl, S.huge),
      child: builder(ctx),
    ),
  );
}

/// Compact metric chip used inside peeks.
class _PeekChip extends StatelessWidget {
  const _PeekChip({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.sm),
        decoration: BoxDecoration(
          color: t.surfaceMuted.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Muted(label, size: 10, maxLines: 1),
            const Gap(2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: AppType.bodySm,
                  fontWeight: FontWeight.w800,
                  color: color ?? t.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

/// `HeroBalance`   greeting, both calendars, the available balance, and the
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
    final accounts = data.accounts
        .where((a) => a.currency == currency)
        .toList();

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
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 19,
                  color: white,
                ),
              ),
            ],
          ),
          const Gap(S.md),
          Text(
            'Available to spend · $currency',
            style: TextStyle(
              fontSize: AppType.caption,
              color: white.withValues(alpha: 0.65),
            ),
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
              if (savingsRate != null)
                _HeroStat(label: 'Saved', value: '$savingsRate%'),
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
                Icon(
                  Icons.arrow_forward,
                  size: 13,
                  color: white.withValues(alpha: 0.85),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    this.icon,
    this.delta,
  });

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
  const FinancialHealthCard({
    super.key,
    required this.data,
    required this.money,
  });

  final DashboardData data;
  final Money money;

  static double _clamp(double n) => n.clamp(0, 100).roundToDouble();

  List<HealthFactor> _factors(SantimTokens t) {
    final income = toNum(data.month.income);
    final expense = toNum(data.month.expense);
    final net = toNum(data.month.net);
    final unnecessary = toNum(data.unnecessary.total);

    final savingsRate = income > 0 ? net / income * 100 : null;
    final savings = HealthFactor(
      label: 'Savings rate',
      score: savingsRate == null ? null : _clamp(savingsRate / 20 * 100),
      detail: savingsRate == null
          ? 'no income yet this month'
          : '${savingsRate.round()}% of ${money(income)} kept',
      icon: Icons.trending_up,
    );

    final atRisk = data.budgetsAtRisk.length;
    final activePlans = data.budgetTotals.activeCount;
    final plans = HealthFactor(
      label: 'Plans',
      score: activePlans == 0
          ? null
          : _clamp((activePlans - atRisk) / activePlans * 100),
      detail: activePlans == 0
          ? 'no plans yet'
          : atRisk == 0
          ? 'all $activePlans on track'
          : '$atRisk of $activePlans running low',
      icon: Icons.shield_outlined,
    );

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

    return [savings, plans, funding, discipline];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final factors = _factors(t);
    final scored = factors.where((f) => f.score != null).toList();
    final score = scored.isEmpty
        ? null
        : (scored.fold<double>(0, (s, f) => s + f.score!) / scored.length)
              .round();

    final (label, color) = switch (score) {
      null => ('Not enough data', t.mutedForeground),
      >= 80 => ('Excellent', t.success),
      >= 60 => ('Good', t.primary),
      >= 40 => ('Fair', t.warning),
      _ => ('Needs attention', t.danger),
    };

    return InsightPeekFrame(
      icon: Icons.favorite_outline_rounded,
      eyebrow: 'FINANCIAL HEALTH',
      accent: color,
      onOpen: () => _openInsightSheet(
        context,
        title: 'Financial health',
        subtitle: score == null
            ? 'Waiting on more activity'
            : '$label · score $score',
        builder: (_) => _HealthDetail(
          factors: factors,
          score: score,
          label: label,
          color: color,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: (score ?? 0) / 100),
                  duration: const Duration(milliseconds: 900),
                  curve: Motion.easeOut,
                  builder: (context, v, _) => CustomPaint(
                    size: const Size.square(88),
                    painter: RingPainter(
                      progress: v,
                      trackColor: t.surfaceMuted,
                      colors: [t.primary, t.accent],
                      strokeWidth: 8,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      score?.toString() ?? '–',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: t.foreground,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const GapX(S.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in factors.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(f.icon, size: 13, color: t.mutedForeground),
                        const GapX(6),
                        Expanded(
                          child: Text(
                            f.label,
                            style: TextStyle(
                              fontSize: AppType.caption,
                              fontWeight: FontWeight.w600,
                              color: t.foreground,
                            ),
                          ),
                        ),
                        Text(
                          f.score == null ? '–' : '${f.score!.round()}',
                          style: TextStyle(
                            fontSize: AppType.caption,
                            fontWeight: FontWeight.w800,
                            color: t.foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                Muted('${scored.length} factors scored', size: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthDetail extends StatelessWidget {
  const _HealthDetail({
    required this.factors,
    required this.score,
    required this.label,
    required this.color,
  });

  final List<HealthFactor> factors;
  final int? score;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: SizedBox(
            width: 132,
            height: 132,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size.square(132),
                  painter: RingPainter(
                    progress: (score ?? 0) / 100,
                    trackColor: t.surfaceMuted,
                    colors: [t.primary, t.accent],
                    strokeWidth: 10,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      score?.toString() ?? '–',
                      style: TextStyle(
                        fontSize: AppType.display,
                        fontWeight: FontWeight.bold,
                        color: t.foreground,
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: AppType.caption,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const Gap(S.xl),
        for (final f in factors)
          Padding(
            padding: const EdgeInsets.only(bottom: S.sm),
            child: Container(
              padding: const EdgeInsets.all(S.md),
              decoration: BoxDecoration(
                color: t.surfaceMuted.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(R.md),
              ),
              child: Row(
                children: [
                  Icon(f.icon, size: 18, color: t.mutedForeground),
                  const GapX(S.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.label,
                          style: TextStyle(
                            fontSize: AppType.bodySm,
                            fontWeight: FontWeight.w700,
                            color: t.foreground,
                          ),
                        ),
                        Muted(f.detail, size: 12, maxLines: 2),
                      ],
                    ),
                  ),
                  if (f.score != null) ...[
                    const GapX(S.sm),
                    SizedBox(
                      width: 48,
                      child: ProgressBar(value: f.score!, height: 5),
                    ),
                    const GapX(S.xs),
                    Text(
                      '${f.score!.round()}',
                      style: TextStyle(
                        fontSize: AppType.bodySm,
                        fontWeight: FontWeight.w800,
                        color: t.foreground,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Small widgets
// ---------------------------------------------------------------------------

/// `SmartInsight`   the single most useful sentence the data supports.
class SmartInsightCard extends StatelessWidget {
  const SmartInsightCard({super.key, required this.data, required this.money});

  final DashboardData data;
  final Money money;

  String _insight() {
    final net = toNum(data.month.net);
    final income = toNum(data.month.income);

    final drained = data.budgetsAtRisk
        .where((b) => b.health == BudgetHealth.drained)
        .length;
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
    final income = toNum(month.income);
    final expense = toNum(month.expense);

    return InsightPeekFrame(
      icon: Icons.lightbulb_outline_rounded,
      eyebrow: 'SMART INSIGHT',
      accent: t.primary,
      onOpen: () => _openInsightSheet(
        context,
        title: 'Smart insight',
        subtitle: 'The most useful signal from your numbers right now',
        builder: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(S.lg),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    t.primary.withValues(alpha: 0.12),
                    t.accent.withValues(alpha: 0.06),
                  ],
                ),
                borderRadius: BorderRadius.circular(R.card),
              ),
              child: Text(
                insight,
                style: TextStyle(
                  fontSize: AppType.body,
                  height: 1.55,
                  fontWeight: FontWeight.w600,
                  color: t.foreground,
                ),
              ),
            ),
            const Gap(S.lg),
            Row(
              children: [
                _PeekChip(
                  label: 'Income',
                  value: money(month.income),
                  color: t.success,
                ),
                const GapX(S.sm),
                _PeekChip(
                  label: 'Spent',
                  value: money(month.expense),
                  color: t.danger,
                ),
                const GapX(S.sm),
                _PeekChip(
                  label: 'Net',
                  value: money(month.net),
                  color: net >= 0 ? t.success : t.danger,
                ),
              ],
            ),
            const Gap(S.lg),
            Muted(
              income > 0
                  ? 'Savings rate this month: ${((net / income) * 100).round()}%.'
                  : 'Add income to unlock a savings-rate read.',
              size: 12,
              maxLines: 3,
            ),
            if (toNum(data.unnecessary.total) > 0) ...[
              const Gap(S.sm),
              Muted(
                '${money(data.unnecessary.total)} flagged as unnecessary so far.',
                size: 12,
                maxLines: 2,
              ),
            ],
            if (expense > 0) ...[
              const Gap(S.sm),
              Muted('Avg daily spend ${money(month.avgDailySpend)}.', size: 12),
            ],
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Text(
              insight,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppType.bodySm,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: t.foreground,
              ),
            ),
          ),
          Row(
            children: [
              _PeekChip(
                label: 'Income',
                value: money(month.income),
                color: t.success,
              ),
              const GapX(S.sm),
              _PeekChip(
                label: 'Net',
                value: money(month.net),
                color: net >= 0 ? t.success : t.danger,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `WeeklySnapshot`   this week against last, from the stored Sunday-boundary
/// snapshots. Bars compare both weeks on whichever spent more.
class WeeklySnapshotCard extends StatelessWidget {
  const WeeklySnapshotCard({
    super.key,
    required this.data,
    required this.prefs,
  });

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

    return InsightPeekFrame(
      icon: Icons.calendar_view_week_rounded,
      eyebrow: 'WEEKLY SNAPSHOT',
      accent: t.accent,
      onOpen: () => _openInsightSheet(
        context,
        title: 'Weekly snapshot',
        subtitle:
            '${formatDayMonth(cur.weekStart)} – ${formatDayMonth(cur.weekEnd.subtract(const Duration(days: 1)))}',
        builder: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MiniRow(
              label: 'Income',
              value: money(cur.income),
              delta: data.incomeDelta,
              goodWhenUp: true,
            ),
            const Gap(S.sm),
            _MiniRow(
              label: 'Spent',
              value: money(cur.expense),
              delta: data.expenseDelta,
              goodWhenUp: false,
            ),
            const Gap(S.sm),
            _MiniRow(
              label: 'Net',
              value: money(cur.net),
              emphasise: true,
              tone: toNum(cur.net) >= 0 ? t.success : t.danger,
            ),
            const Gap(S.lg),
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
            const Gap(S.lg),
            Text(
              toNum(prev.expense) == 0 && toNum(cur.expense) == 0
                  ? 'No spending either week.'
                  : 'You spent ${money(toNum(data.expenseAmount).abs(), compact: true)} '
                        '${spentMore ? 'more' : 'less'} than last week'
                        '${cur.topCategory != null ? ' · mostly ${cur.topCategory}' : ''}.',
              style: TextStyle(
                fontSize: AppType.bodySm,
                height: 1.45,
                color: t.foreground,
              ),
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _PeekChip(
                label: 'Income',
                value: money(cur.income, compact: true),
                color: t.success,
              ),
              const GapX(S.sm),
              _PeekChip(
                label: 'Spent',
                value: money(cur.expense, compact: true),
                color: t.danger,
              ),
              const GapX(S.sm),
              _PeekChip(
                label: 'Net',
                value: money(cur.net, compact: true),
                color: toNum(cur.net) >= 0 ? t.success : t.danger,
              ),
            ],
          ),
          const Gap(S.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CompareBar(
                  label: 'This week',
                  value: money(cur.expense, compact: true),
                  pct: math.max(2, toNum(cur.expense) / peak * 100),
                  active: true,
                ),
                const Gap(S.xs),
                _CompareBar(
                  label: 'Last week',
                  value: money(prev.expense, compact: true),
                  pct: math.max(2, toNum(prev.expense) / peak * 100),
                ),
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
              child: Amount(
                value,
                size: emphasise ? 14.5 : 13,
                color: tone ?? t.foreground,
              ),
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

/// `SpendingStreaks`   the run of days under the average daily pace, with the
/// full window as a dot strip so broken days stay visible.
class SpendingStreaksCard extends StatelessWidget {
  const SpendingStreaksCard({
    super.key,
    required this.data,
    required this.prefs,
  });

  final SpendingStreak data;
  final PrefsState prefs;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return InsightPeekFrame(
      icon: Icons.local_fire_department_rounded,
      eyebrow: 'SPENDING STREAK',
      accent: t.warning,
      onOpen: () => _openInsightSheet(
        context,
        title: 'Spending streak',
        subtitle: data.label,
        builder: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Amount('${data.currentDays}', size: 42),
                const GapX(S.sm),
                Muted('days under pace', size: 14),
              ],
            ),
            const Gap(S.md),
            Muted(
              'Pace ${prefs.money(data.avgDailySpend, currency: data.currency)}/day · best ${data.bestStreak}',
              size: 13,
            ),
            const Gap(S.lg),
            SpendStrip(days: [for (final d in data.days) (d.under, d.spent)]),
            const Gap(S.md),
            Muted(
              '${data.daysUnder} of ${data.dayCount} days under your average pace.',
              size: 12,
              maxLines: 2,
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Amount('${data.currentDays}', size: 34),
              const GapX(S.xs),
              Muted('days under pace', size: 12),
              const Spacer(),
              Muted('best ${data.bestStreak}', size: 11),
            ],
          ),
          const Gap(S.sm),
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: SpendStrip(
                days: [for (final d in data.days) (d.under, d.spent)],
              ),
            ),
          ),
          Muted(
            '${data.daysUnder}/${data.dayCount} under · ${prefs.money(data.avgDailySpend, currency: data.currency)}/day',
            size: 11,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

/// `TabWidget`   open lends and borrows with the settle-on-time forecast.
class TabWidgetCard extends StatelessWidget {
  const TabWidgetCard({
    super.key,
    required this.tab,
    required this.money,
    this.onOpen,
  });

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
                AppBadge(
                  '${tab.overdueCount} overdue',
                  tone: BadgeTone.danger,
                  dense: true,
                )
              else
                Icon(
                  Icons.volunteer_activism_outlined,
                  size: 16,
                  color: t.mutedForeground,
                ),
            ],
          ),
          const Gap(S.md),
          Amount(
            money(net.abs()),
            size: 24,
            color: net >= 0 ? t.success : t.danger,
          ),
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
                child: _TinyStat(
                  label: 'You owe',
                  value: money(tab.payable),
                  color: t.danger,
                ),
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

/// `WishlistWidget`   a want is just the idea of a thing, so this counts them
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
                child: Muted(
                  'want${wishlist.activeCount == 1 ? '' : 's'}',
                  size: 11.5,
                ),
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
                    Text(
                      w.emoji ?? '✨',
                      style: const TextStyle(fontSize: AppType.bodySm),
                    ),
                    const GapX(S.xs),
                    Expanded(
                      child: Text(
                        w.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.label,
                          color: t.foreground,
                        ),
                      ),
                    ),
                    if (w.plan != null)
                      AppBadge('planned', tone: BadgeTone.primary, dense: true),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// `CategoryHeatAlerts`   categories running hotter than last month.
class CategoryHeatCard extends StatelessWidget {
  const CategoryHeatCard({
    super.key,
    required this.alerts,
    required this.money,
  });

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
                padding: EdgeInsets.only(
                  bottom: i == alerts.length - 1 ? 0 : 9,
                ),
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

/// `FamilySupportTracker`   money sent to family, a first-class category in
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
                      tone: data.deltaPct! > 0
                          ? BadgeTone.warning
                          : BadgeTone.success,
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
                          style: TextStyle(
                            fontSize: AppType.label,
                            color: t.foreground,
                          ),
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

/// `HouseholdWidget`   shared wallets and the partners who can see them.
class HouseholdCard extends StatelessWidget {
  const HouseholdCard({
    super.key,
    required this.household,
    required this.money,
  });

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
                        style: TextStyle(
                          fontSize: AppType.micro,
                          color: t.mutedForeground,
                        ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: S.md,
                      vertical: S.xs,
                    ),
                    decoration: BoxDecoration(
                      color: t.surfaceMuted.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(R.sm),
                      border: Border(
                        left: BorderSide(
                          color: parseHexColor(a.color) ?? t.primary,
                          width: 3,
                        ),
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

/// `SpendingPace`   where the month's spend sits against a straight-line
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

    final projected = elapsed == 0 ? 0.0 : expense / elapsed * daysInMonth;
    final onTrack = income <= 0 || projected <= income;
    final pctOfMonth = elapsed / daysInMonth * 100;
    final pctSpent = income > 0
        ? (expense / income * 100).clamp(0, 200).toDouble()
        : 0.0;
    final accent = !onTrack ? t.danger : t.primary;

    return InsightPeekFrame(
      icon: Icons.speed_rounded,
      eyebrow: 'SPENDING PACE',
      accent: accent,
      onOpen: () => _openInsightSheet(
        context,
        title: 'Spending pace',
        subtitle: 'Day $elapsed of $daysInMonth',
        builder: (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Muted('Spent so far', size: 12),
                      const Gap(S.hair),
                      Amount(money(expense), size: 26),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Muted('On this pace', size: 12),
                    const Gap(S.hair),
                    Amount(
                      money(projected),
                      size: 26,
                      color: onTrack ? t.foreground : t.danger,
                    ),
                  ],
                ),
              ],
            ),
            const Gap(S.lg),
            Stack(
              alignment: Alignment.centerLeft,
              children: [
                ProgressBar(
                  value: pctSpent,
                  height: 12,
                  tone: !onTrack
                      ? BadgeTone.danger
                      : pctSpent > pctOfMonth
                      ? BadgeTone.warning
                      : BadgeTone.primary,
                ),
                if (income > 0)
                  FractionallySizedBox(
                    widthFactor: (pctOfMonth / 100).clamp(0.0, 1.0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 2,
                        height: 16,
                        color: t.foreground.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
              ],
            ),
            const Gap(S.md),
            Text(
              income > 0
                  ? onTrack
                        ? 'You’re on track   projected spend stays under income.'
                        : 'This pace would overshoot income by month end.'
                  : 'Avg ${money(month.avgDailySpend)}/day so far.',
              style: TextStyle(
                fontSize: AppType.bodySm,
                height: 1.45,
                color: t.foreground,
              ),
            ),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _PeekChip(label: 'Spent', value: money(expense)),
              const GapX(S.sm),
              _PeekChip(
                label: 'Pace →',
                value: money(projected),
                color: onTrack ? t.foreground : t.danger,
              ),
            ],
          ),
          const Gap(S.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ProgressBar(
                  value: pctSpent,
                  height: 9,
                  tone: !onTrack
                      ? BadgeTone.danger
                      : pctSpent > pctOfMonth
                      ? BadgeTone.warning
                      : BadgeTone.primary,
                ),
                const Gap(S.sm),
                Row(
                  children: [
                    Muted('Day $elapsed/$daysInMonth', size: 11),
                    const Spacer(),
                    Muted(
                      income > 0
                          ? '${pctSpent.round()}% of income'
                          : '${money(month.avgDailySpend)}/day',
                      size: 11,
                    ),
                  ],
                ),
              ],
            ),
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
