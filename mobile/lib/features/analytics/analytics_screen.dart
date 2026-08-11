import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/analytics.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../widgets/charts.dart';
import '../../widgets/ui.dart';

/// Analytics. The overview is one `/analytics/page` payload — seven cards that
/// each answer a single question — with the chart sections fetched separately
/// so switching tabs never re-costs the overview.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

enum _Section { overview, trends, categories, seasons }

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  _Section _section = _Section.overview;

  AnalyticsPageData? _page;
  IncomeVsExpense? _trends;
  CategoryTotals? _categories;
  CategoryMovers? _movers;
  SeasonalReport? _seasons;
  SpendHeatmapData? _heatmap;
  TopPayees? _payees;

  bool _loading = true;
  Object? _error;
  DateTime _month = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final json = await context.read<ApiClient>().get<Map<String, dynamic>>(
        '/analytics/page',
        query: {'month': monthKey(_month)},
      );
      if (!mounted) return;
      setState(() {
        _page = AnalyticsPageData.fromJson(json);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Each chart section pays for itself the first time it is opened.
  Future<void> _loadSection(_Section section) async {
    final api = context.read<ApiClient>();
    try {
      switch (section) {
        case _Section.trends:
          if (_trends != null) return;
          final results = await Future.wait([
            api.get<Map<String, dynamic>>('/analytics/income-vs-expense', query: {'months': 12}),
            api.get<Map<String, dynamic>>('/analytics/heatmap',
                query: {'year': DateTime.now().year}),
          ]);
          if (!mounted) return;
          setState(() {
            _trends = IncomeVsExpense.fromJson(results[0]);
            _heatmap = SpendHeatmapData.fromJson(results[1]);
          });
        case _Section.categories:
          if (_categories != null) return;
          final results = await Future.wait([
            api.get<Map<String, dynamic>>('/analytics/categories',
                query: {'month': monthKey(_month), 'kind': 'EXPENSE'}),
            api.get<Map<String, dynamic>>('/analytics/movers',
                query: {'month': monthKey(_month)}),
            api.get<Map<String, dynamic>>('/analytics/payees',
                query: {'month': monthKey(_month), 'limit': 8}),
          ]);
          if (!mounted) return;
          setState(() {
            _categories = CategoryTotals.fromJson(results[0]);
            _movers = CategoryMovers.fromJson(results[1]);
            _payees = TopPayees.fromJson(results[2]);
          });
        case _Section.seasons:
          if (_seasons != null) return;
          final json = await api.get<Map<String, dynamic>>('/analytics/seasonal');
          if (!mounted) return;
          setState(() => _seasons = SeasonalReport.fromJson(json));
        case _Section.overview:
          break;
      }
    } catch (_) {
      // Section fetches fail quietly — the overview stays usable.
    }
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
      _categories = null;
      _movers = null;
      _payees = null;
    });
    _load();
    if (_section == _Section.categories) _loadSection(_Section.categories);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final prefs = context.watch<PrefsState>();
    final data = context.watch<DataState>();
    final currency = _page?.currency ?? data.activeCurrency;

    String money(Object? v) => prefs.money(v, currency: currency);
    String compact(Object? v) => prefs.money(v, currency: currency, compact: true);

    final canGoForward = DateTime(_month.year, _month.month)
        .isBefore(DateTime(DateTime.now().year, DateTime.now().month));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Analytics',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.foreground),
        ),
      ),
      body: MeshBackground(
        showGrid: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                children: [
                  IconPill(icon: Icons.chevron_left, size: 34, onTap: () => _shiftMonth(-1)),
                  Expanded(
                    child: Center(
                      child: Column(
                        children: [
                          Text(
                            formatMonthKey(monthKey(_month)),
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: t.foreground,
                            ),
                          ),
                          if (_page != null && _page!.inProgress)
                            Muted(
                              'day ${_page!.daysElapsed} of ${_page!.daysInMonth}',
                              size: 10.5,
                            ),
                        ],
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: canGoForward ? 1 : 0.3,
                    child: IconPill(
                      icon: Icons.chevron_right,
                      size: 34,
                      onTap: canGoForward ? () => _shiftMonth(1) : null,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: _SectionTabs(
                value: _section,
                onChanged: (s) {
                  setState(() => _section = s);
                  _loadSection(s);
                },
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: t.primary,
                backgroundColor: t.surface,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 40),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (_loading && _page == null)
                      const PageLoader(rows: 4)
                    else if (_error != null && _page == null)
                      ErrorState(
                        message: _error is ApiError
                            ? (_error as ApiError).message
                            : 'Could not load analytics.',
                        onRetry: _load,
                      )
                    else if (_page != null)
                      ...switch (_section) {
                        _Section.overview => _overview(context, _page!, money, compact),
                        _Section.trends => _trendsSection(context, money, compact),
                        _Section.categories => _categoriesSection(context, money),
                        _Section.seasons => _seasonsSection(context, money, compact),
                      },
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Overview — the seven cards
  // -------------------------------------------------------------------------

  List<Widget> _overview(
    BuildContext context,
    AnalyticsPageData p,
    String Function(Object?) money,
    String Function(Object?) compact,
  ) {
    final t = context.t;
    return [
      if (!p.scopeComplete && p.missingRates.isNotEmpty) ...[
        AppCard(
          padding: const EdgeInsets.all(13),
          color: t.warning.withValues(alpha: 0.08),
          borderColor: t.warning.withValues(alpha: 0.25),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: t.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${p.missingRates.join(', ')} left out — no exchange rate into '
                  '${p.currency}. Add one in Settings.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: t.foreground),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],

      // 1. Cash flow
      FadeInUp(
        child: _Card(
          title: 'Cash flow',
          icon: Icons.swap_vert_rounded,
          hint: 'Income minus spending for the month, against the same figures '
              'last month. Savings rate is what share of income you kept.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Muted('Net', size: 11),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Amount(
                            money(p.net),
                            size: 26,
                            color: toNum(p.net) >= 0 ? t.success : t.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (p.deltaNetPct != null)
                    AppBadge(
                      formatPct(p.deltaNetPct),
                      tone: p.deltaNetPct! >= 0 ? BadgeTone.success : BadgeTone.danger,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _Fig(label: 'Income', value: money(p.income), color: t.success)),
                  const SizedBox(width: 10),
                  Expanded(child: _Fig(label: 'Spent', value: money(p.expense), color: t.danger)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _Fig(
                      label: 'Savings rate',
                      value: p.savingsRate == null ? '-' : '${p.savingsRate!.round()}%',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Fig(label: 'Last month net', value: money(p.prevNet)),
                  ),
                ],
              ),
              if (p.deltaExpensePct != null) ...[
                const SizedBox(height: 10),
                Muted(
                  'Spending is ${formatPct(p.deltaExpensePct)} on last month '
                  '(${money(p.prevExpense)}).',
                  size: 11.5,
                  height: 1.4,
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),

      // 2. Where your cash sits
      FadeInUp(
        delay: const Duration(milliseconds: 50),
        child: _Card(
          title: 'Where your cash sits',
          icon: Icons.account_balance_wallet_outlined,
          hint: 'Real is what is physically in your accounts. Locked is what '
              'budget plans have reserved. Available is what is genuinely free.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _Fig(label: 'Real', value: money(p.cashReal))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Fig(
                      label: 'Locked in plans',
                      value: money(p.cashLocked),
                      color: t.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Fig(label: 'Available', value: money(p.cashAvailable)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ProgressBar(value: p.lockedPct, height: 8, tone: BadgeTone.info),
              const SizedBox(height: 8),
              Muted(
                '${p.lockedPct.round()}% of your money is reserved across '
                '${p.accountCount} wallet${p.accountCount == 1 ? '' : 's'}.',
                size: 11.5,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),

      // 3. Unplanned spending
      FadeInUp(
        delay: const Duration(milliseconds: 90),
        child: _Card(
          title: 'Unplanned spending',
          icon: Icons.more_horiz,
          hint: 'Spending that never went through a funded plan. A high share '
              'means your plans are not covering how you actually spend.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Amount(
                    money(p.unplannedAmount),
                    size: 24,
                    color: p.unplannedPct > 50 ? t.warning : t.foreground,
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: AppBadge(
                      '${p.unplannedPct.round()}% of spend',
                      tone: p.unplannedPct > 50 ? BadgeTone.warning : BadgeTone.neutral,
                      dense: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ProgressBar(
                value: p.unplannedPct,
                height: 8,
                tone: p.unplannedPct > 50 ? BadgeTone.warning : BadgeTone.primary,
              ),
              const SizedBox(height: 8),
              Muted(
                'of ${money(p.unplannedTotalExpense)} spent this month.',
                size: 11.5,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),

      // 4. Plans
      FadeInUp(
        delay: const Duration(milliseconds: 130),
        child: _Card(
          title: 'Plans this month',
          icon: Icons.savings_outlined,
          hint: 'Spend is measured against what each cycle opened with, so a '
              'mid-cycle raise cannot quietly hide an overspend.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _Fig(label: 'Opened at', value: money(p.planOpening))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Fig(
                      label: 'Adjusted',
                      value: money(p.planAdjusted),
                      color: toNum(p.planAdjusted) >= 0 ? t.success : t.warning,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _Fig(label: 'Spent', value: money(p.planSpent))),
                ],
              ),
              if (p.overspentCount > 0 || p.adjustedCount > 0) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (p.overspentCount > 0)
                      AppBadge(
                        '${p.overspentCount} overspent',
                        tone: BadgeTone.danger,
                        icon: Icons.warning_amber_rounded,
                      ),
                    if (p.adjustedCount > 0)
                      AppBadge(
                        '${p.adjustedCount} adjusted mid-cycle',
                        tone: BadgeTone.warning,
                      ),
                  ],
                ),
              ],
              if (p.plans.isNotEmpty) ...[
                const SizedBox(height: 14),
                for (var i = 0; i < math.min(p.plans.length, 6); i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 11),
                    child: _PlanRow(plan: p.plans[i], money: money),
                  ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),

      // 5. Commitments
      FadeInUp(
        delay: const Duration(milliseconds: 170),
        child: _Card(
          title: 'Fixed commitments',
          icon: Icons.repeat,
          hint: 'Every recurring rule normalised to a monthly figure, so a '
              'weekly bill and a yearly one can be compared.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Fig(
                      label: 'Out per month',
                      value: money(p.monthlyOut),
                      color: t.danger,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Fig(
                      label: 'In per month',
                      value: money(p.monthlyIn),
                      color: t.success,
                    ),
                  ),
                ],
              ),
              if (p.shareOfIncome != null) ...[
                const SizedBox(height: 12),
                ProgressBar(
                  value: p.shareOfIncome!,
                  height: 8,
                  tone: p.shareOfIncome! > 60 ? BadgeTone.danger : BadgeTone.primary,
                ),
                const SizedBox(height: 8),
                Muted(
                  '${p.shareOfIncome!.round()}% of your income is already spoken for.',
                  size: 11.5,
                ),
              ],
              if (p.commitments.isNotEmpty) ...[
                const SizedBox(height: 14),
                for (final c in p.commitments.take(6))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        IconTile(
                          icon: financeIcon(c.category?.icon),
                          color: parseHexColor(c.category?.color),
                          size: 32,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: t.foreground,
                                ),
                              ),
                              Muted(
                                '${c.frequency.label} · next ${formatDayMonth(c.nextRun)}',
                                size: 10.5,
                              ),
                            ],
                          ),
                        ),
                        Amount(money(c.monthlyEquivalent), size: 12.5),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),

      // 6. Wishlist
      FadeInUp(
        delay: const Duration(milliseconds: 200),
        child: _Card(
          title: 'Wishlist',
          icon: Icons.favorite_border,
          hint: 'How wants move through the list: how long they sit before you '
              'plan them, and how long a plan takes to become a purchase.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _Fig(label: 'Wanting', value: '${p.wishWanting}')),
                  const SizedBox(width: 8),
                  Expanded(child: _Fig(label: 'Planned', value: '${p.wishPlanned}')),
                  const SizedBox(width: 8),
                  Expanded(child: _Fig(label: 'Bought', value: '${p.wishBought}')),
                  const SizedBox(width: 8),
                  Expanded(child: _Fig(label: 'Dropped', value: '${p.wishDropped}')),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Fig(label: 'Planned value', value: money(p.wishPlannedValue)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Fig(
                      label: 'Want → plan',
                      value: p.avgDaysToPlan == null
                          ? '-'
                          : '${p.avgDaysToPlan!.round()} days',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Fig(
                      label: 'Plan → bought',
                      value: p.avgDaysToBuy == null
                          ? '-'
                          : '${p.avgDaysToBuy!.round()} days',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),

      // 7. Money Tab
      FadeInUp(
        delay: const Duration(milliseconds: 230),
        child: _Card(
          title: 'Money Tab',
          icon: Icons.volunteer_activism_outlined,
          hint: 'What is outstanding either way. Expected items are ones you '
              'are counting on but have not moved yet.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Fig(
                      label: 'Lent (${p.lentCount})',
                      value: money(p.lent),
                      color: t.success,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Fig(
                      label: 'Borrowed (${p.borrowedCount})',
                      value: money(p.borrowed),
                      color: t.danger,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _Fig(label: 'Expected in', value: money(p.ledgerExpectedIn)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Fig(label: 'Expected out', value: money(p.ledgerExpectedOut)),
                  ),
                ],
              ),
              if (p.overdueCount > 0) ...[
                const SizedBox(height: 12),
                AppBadge(
                  '${p.overdueCount} overdue',
                  tone: BadgeTone.danger,
                  icon: Icons.warning_amber_rounded,
                ),
              ],
              if (p.counterparties.isNotEmpty) ...[
                const SizedBox(height: 14),
                for (final c in p.counterparties.take(6))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Avatar(name: c.name, size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: t.foreground,
                                ),
                              ),
                              Muted(
                                c.dueDate == null
                                    ? c.kind.label
                                    : '${c.kind.label} · due ${formatDayMonth(c.dueDate)}',
                                size: 10.5,
                              ),
                            ],
                          ),
                        ),
                        Amount(
                          money(c.outstanding),
                          size: 12.5,
                          color: c.overdue
                              ? t.danger
                              : c.kind.inbound
                                  ? t.success
                                  : t.foreground,
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  // -------------------------------------------------------------------------
  // Chart sections
  // -------------------------------------------------------------------------

  List<Widget> _trendsSection(
    BuildContext context,
    String Function(Object?) money,
    String Function(Object?) compact,
  ) {
    if (_trends == null) return [const PageLoader(rows: 3, hero: false)];
    return [
      _Card(
        title: 'Income vs spending',
        icon: Icons.show_chart,
        hint: 'The last twelve months. Drag across the chart to read a month.',
        child: IncomeExpenseLine(
          points: [
            for (final p in _trends!.points)
              SeriesPoint(
                label: formatMonthKey(p.month).split(' ').first.substring(0, 3),
                income: toNum(p.income),
                expense: toNum(p.expense),
              ),
          ],
          format: compact,
        ),
      ),
      const SizedBox(height: 12),
      _Card(
        title: 'Savings rate',
        icon: Icons.percent,
        hint: 'What share of each month\'s income you kept.',
        child: ColumnChart(
          data: [
            for (final p in _trends!.points.take(8))
              BarDatum(
                label: formatMonthKey(p.month).split(' ').first.substring(0, 3),
                value: (p.savingsRate ?? 0).clamp(0, 100).toDouble(),
              ),
          ],
          format: (v) => '${v.round()}%',
        ),
      ),
      if (_heatmap != null) ...[
        const SizedBox(height: 12),
        _Card(
          title: 'Spending heatmap ${_heatmap!.year}',
          icon: Icons.grid_view_rounded,
          hint: 'One square per day, darker where you spent more.',
          child: SpendHeatmap(
            days: {
              for (final d in _heatmap!.days)
                DateTime(d.date.year, d.date.month, d.date.day): toNum(d.total),
            },
            format: compact,
            onTapDay: (day, amount) => toast(
              context,
              '${formatDate(day)} · ${money(amount)}',
            ),
          ),
        ),
      ],
    ];
  }

  List<Widget> _categoriesSection(BuildContext context, String Function(Object?) money) {
    final t = context.t;
    if (_categories == null) return [const PageLoader(rows: 3, hero: false)];

    final slices = [
      for (final item in _categories!.items.take(8))
        Slice(
          label: item.category?.name ?? 'Uncategorised',
          value: toNum(item.amount),
          color: parseHexColor(item.category?.color) ?? t.mutedForeground,
        ),
    ];

    return [
      _Card(
        title: 'Where it went',
        icon: Icons.donut_large_outlined,
        hint: 'Tap a segment to read its total.',
        child: slices.isEmpty
            ? const EmptyState(title: 'No spending this month', compact: true)
            : Center(
                child: DonutChart(
                  data: slices,
                  format: money,
                  centerLabel: 'spent',
                ),
              ),
      ),
      if (_movers != null && _movers!.hasPrevious) ...[
        const SizedBox(height: 12),
        _Card(
          title: 'Biggest movers',
          icon: Icons.trending_up,
          hint: 'Categories that changed most against last month. New ones show '
              'no percentage — a percentage off zero says nothing.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_movers!.up.isNotEmpty) ...[
                SectionLabel('UP'),
                RankedBars(
                  data: [
                    for (final m in _movers!.up.take(5))
                      BarDatum(
                        label: m.category?.name ?? 'Uncategorised',
                        value: toNum(m.change).abs(),
                        color: t.danger,
                        caption: m.isNew
                            ? 'new this month'
                            : '${money(m.previous)} → ${money(m.current)} '
                                '(${formatPct(m.changePct)})',
                      ),
                  ],
                  format: money,
                ),
              ],
              if (_movers!.down.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionLabel('DOWN'),
                RankedBars(
                  data: [
                    for (final m in _movers!.down.take(5))
                      BarDatum(
                        label: m.category?.name ?? 'Uncategorised',
                        value: toNum(m.change).abs(),
                        color: t.success,
                        caption: m.stopped
                            ? 'stopped this month'
                            : '${money(m.previous)} → ${money(m.current)} '
                                '(${formatPct(m.changePct)})',
                      ),
                  ],
                  format: money,
                ),
              ],
            ],
          ),
        ),
      ],
      if (_payees != null && _payees!.items.isNotEmpty) ...[
        const SizedBox(height: 12),
        _Card(
          title: 'Top payees',
          icon: Icons.storefront_outlined,
          child: RankedBars(
            data: [
              for (final p in _payees!.items)
                BarDatum(
                  label: p.payee ?? 'Unnamed',
                  value: toNum(p.total),
                  caption: '${p.count} transaction${p.count == 1 ? '' : 's'}',
                ),
            ],
            format: money,
          ),
        ),
      ],
    ];
  }

  List<Widget> _seasonsSection(
    BuildContext context,
    String Function(Object?) money,
    String Function(Object?) compact,
  ) {
    final t = context.t;
    final s = _seasons;
    if (s == null) return [const PageLoader(rows: 3, hero: false)];

    if (s.monthsObserved < 2) {
      return [
        const EmptyState(
          icon: Icons.calendar_month_outlined,
          title: 'Not enough history yet',
          description: 'Seasonal patterns need at least two months of data.',
        ),
      ];
    }

    return [
      _Card(
        title: 'Month by month',
        icon: Icons.calendar_month_outlined,
        hint: 'Average spend for each calendar month across '
            '${s.monthsObserved} months of history.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RankedBars(
              data: [
                for (final m in s.months.where((m) => m.samples > 0))
                  BarDatum(
                    label: m.name,
                    value: toNum(m.avgExpense),
                    caption: '${m.samples} year${m.samples == 1 ? '' : 's'} of data',
                  ),
              ],
              format: money,
            ),
            if (s.dearestMonth != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.local_fire_department_outlined, size: 15, color: t.warning),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Muted(
                      '${s.dearestMonth!.name} is your dearest month '
                      '(${money(s.dearestMonth!.avgExpense)} on average)'
                      '${s.cheapestMonth != null ? '; ${s.cheapestMonth!.name} the cheapest' : ''}.',
                      size: 11.5,
                      height: 1.4,
                      maxLines: 3,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      _Card(
        title: 'Day of the week',
        icon: Icons.view_week_outlined,
        hint: 'Average spend per weekday — useful for spotting the day your '
            'money quietly disappears.',
        child: ColumnChart(
          data: [
            for (final d in s.daysOfWeek)
              BarDatum(
                label: d.name.substring(0, 3),
                value: toNum(d.avgSpend),
                color: s.heaviestDay?.day == d.day ? t.danger : null,
              ),
          ],
          format: compact,
        ),
      ),
      if (s.years.isNotEmpty) ...[
        const SizedBox(height: 12),
        _Card(
          title: 'By year',
          icon: Icons.history,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final y in s.years)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 46,
                        child: Text(
                          '${y.year}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: t.foreground,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Muted('in ${money(y.income)}', size: 11),
                                const SizedBox(width: 10),
                                Muted('out ${money(y.expense)}', size: 11),
                                const Spacer(),
                                if (y.savingsRate != null)
                                  AppBadge(
                                    '${y.savingsRate!.round()}% saved',
                                    tone: y.savingsRate! >= 20
                                        ? BadgeTone.success
                                        : BadgeTone.neutral,
                                    dense: true,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            ProgressBar(
                              value: toNum(y.income) <= 0
                                  ? 0
                                  : (toNum(y.expense) / toNum(y.income) * 100)
                                      .clamp(0, 100)
                                      .toDouble(),
                              height: 5,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    ];
  }
}

/// The four section tabs across the top of the page.
class _SectionTabs extends StatelessWidget {
  const _SectionTabs({required this.value, required this.onChanged});

  final _Section value;
  final ValueChanged<_Section> onChanged;

  static const _labels = {
    _Section.overview: 'Overview',
    _Section.trends: 'Trends',
    _Section.categories: 'Categories',
    _Section.seasons: 'Seasons',
  };

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final s in _Section.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PressableScale(
                onTap: () => onChanged(s),
                child: AnimatedContainer(
                  duration: Motion.fast,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: s == value ? t.primary.withValues(alpha: 0.12) : t.surface,
                    borderRadius: BorderRadius.circular(R.pill),
                    border: Border.all(
                      color: s == value ? t.primary.withValues(alpha: 0.35) : t.border,
                    ),
                  ),
                  child: Text(
                    _labels[s]!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: s == value ? FontWeight.w700 : FontWeight.w500,
                      color: s == value ? t.primary : t.foreground,
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

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.icon,
    required this.child,
    this.hint,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitleRow(title: title, icon: icon, hint: hint),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _Fig extends StatelessWidget {
  const _Fig({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: t.surfaceMuted.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Muted(label, size: 10, maxLines: 1),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Amount(value, size: 14, color: color),
          ),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.plan, required this.money});

  final AnalyticsPlanRow plan;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final over = plan.pctOfOpening > 100;
    final adjusted = toNum(plan.adjusted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconTile(
              icon: financeIcon(plan.icon),
              color: parseHexColor(plan.color) ?? t.primary,
              size: 28,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                plan.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: t.foreground,
                ),
              ),
            ),
            Amount(
              money(plan.spent),
              size: 12.5,
              color: over ? t.danger : t.foreground,
            ),
          ],
        ),
        const SizedBox(height: 6),
        ProgressBar(
          value: plan.pctOfOpening.clamp(0, 100).toDouble(),
          height: 6,
          tone: over ? BadgeTone.danger : BadgeTone.primary,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Muted(
              'of ${money(plan.openingPlanned)} opened '
              '(${plan.pctOfOpening.round()}%)',
              size: 10.5,
            ),
            const Spacer(),
            if (adjusted != 0)
              Muted(
                '${adjusted >= 0 ? 'raised' : 'cut'} ${money(adjusted.abs())}',
                size: 10.5,
              ),
          ],
        ),
      ],
    );
  }
}
