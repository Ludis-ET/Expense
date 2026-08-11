import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/layout.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/auth_state.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../widgets/sync_ui.dart';
import '../../widgets/ui.dart';
import '../analytics/analytics_screen.dart';
import '../budgets/budget_detail_screen.dart';
import '../ledger/tab_screen.dart';
import '../recurring/recurring_screen.dart';
import '../outlook/monthly_outlook_screen.dart';
import '../shell/app_shell.dart';
import '../transactions/transaction_detail.dart';
import '../transactions/transaction_list.dart';
import '../wishlist/wishlist_screen.dart';
import 'customise_dashboard_screen.dart';
import 'dashboard_layout.dart';
import 'dashboard_widgets.dart';

/// The dashboard, in tiers rather than as one flat stack.
///
/// It used to render seventeen blocks unconditionally at equal visual weight
/// on a phone that is a single scroll several thousand pixels long where only
/// the balance is above the fold. Now:
///
///   1. the balance, as the one hero card;
///   2. the insight cards, as a swipeable strip one screen tall;
///   3. quick stats and the detail sections, collapsible and remembered;
///   4. secondary cards, auto-hidden when they have nothing to say.
///
/// Every card below the hero can be switched off or reordered in
/// [CustomiseDashboardScreen].
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataState>();
    final prefs = context.watch<PrefsState>();
    final user = context.watch<AuthState>().user;
    final shell = AppShell.of(context);
    final currency = data.activeCurrency;

    String money(Object? v) => prefs.money(v, currency: currency);
    String moneyIn(Object? v, String c) => prefs.money(v, currency: c);

    final async = data.dashboard;
    final raw = async.data;

    return RefreshIndicator(
      onRefresh: () => data.loadDashboard(force: true),
      color: context.t.primary,
      backgroundColor: context.t.surface,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          S.lg,
          S.lg,
          S.lg,
          ShellLayout.bottomClearance(context),
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          PageHeader(
            title: 'Dashboard',
            description: currency.isEmpty
                ? null
                : 'Every figure on this page is in $currency. '
                      'Totals are never mixed across currencies.',
            badge: raw != null && data.currencies.length > 1
                ? AppBadge(currency, tone: BadgeTone.primary)
                : null,
            action: raw == null
                ? null
                : IconPill(
                    icon: Icons.tune_rounded,
                    tooltip: 'Customise dashboard',
                    onTap: () => shell.push(const CustomiseDashboardScreen()),
                  ),
          ),
          const OfflineBanner(),
          if (raw == null) ...[
            if (async.hasError)
              ErrorState(
                message: async.errorMessage,
                onRetry: () => data.loadDashboard(force: true),
              )
            else
              const PageLoader(rows: 3),
          ] else
            ..._content(context, data, prefs, raw, user, shell, money, moneyIn),
        ],
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    DataState data,
    PrefsState prefs,
    DashboardData raw,
    User? user,
    AppShellState shell,
    String Function(Object?) money,
    String Function(Object?, String) moneyIn,
  ) {
    final t = context.t;
    final breakdown = data.activeBreakdown;
    final currency = data.activeCurrency;

    // The active currency's slice replaces the top-level totals, so switching
    // currency never refetches.
    final month = breakdown?.month ?? raw.month;
    final scoped = raw.recentTransactions
        .where((tx) => tx.currency == currency)
        .toList();

    // A card shows when the user has not switched it off *and* it has
    // something to say. The second half is what stops a new user scrolling
    // past four empty states.
    bool shows(String id, {bool hasData = true}) =>
        prefs.isCardVisible(id) && hasData;

    // --- tier 2: the insight strip -------------------------------------------

    final insights = <String, Widget>{
      'insight': SmartInsightCard(data: raw, money: money),
      'health': FinancialHealthCard(data: raw, money: money),
      'outlook': const MonthlyOutlookCard(),
      'pace': SpendingPaceCard(month: month, money: money),
      'weekly': WeeklySnapshotCard(data: raw.weeklySnapshot, prefs: prefs),
      'streaks': SpendingStreaksCard(data: raw.spendingStreak, prefs: prefs),
    };
    final insightPages = [
      for (final id in prefs.applyOrder(
        kInsightCards.map((c) => c.id).toList(),
      ))
        if (shows(id) && insights.containsKey(id)) insights[id]!,
    ];

    // --- tier 3+: body cards ---------------------------------------------------

    final body = <String, Widget>{
      'stats': _QuickStats(raw: raw, month: month, money: money),
      'recentTx': CollapsibleSection(
        id: 'recentTx',
        title: 'Recent transactions',
        summary: '${scoped.length} this period',
        trailingLabel: 'View all activity',
        onTrailingTap: () => shell.goTo(ShellTab.activity),
        padding: const EdgeInsets.fromLTRB(S.md, 0, S.md, S.md),
        child: scoped.isEmpty
            ? const EmptyState(title: 'No transactions yet', compact: true)
            : TransactionList(
                items: scoped.take(6).toList(),
                money: moneyIn,
                compact: true,
                onTap: (tx) => showTransactionDetail(context, tx),
              ),
      ),
      'budgets': CollapsibleSection(
        id: 'budgets',
        title: 'Budget plans',
        summary: '${raw.budgets.length} active',
        trailingLabel: 'Manage plans',
        onTrailingTap: () => shell.goTo(ShellTab.plan),
        child: raw.budgets.isEmpty
            ? const EmptyState(
                icon: Icons.savings_outlined,
                title: 'No plans yet',
                description: 'Set money aside for what you intend to spend.',
                compact: true,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < raw.budgets.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i == raw.budgets.length - 1 ? 0 : S.lg,
                      ),
                      child: _BudgetMiniRow(
                        budget: raw.budgets[i],
                        money: moneyIn,
                        onTap: () => shell.push(
                          BudgetDetailScreen(budgetId: raw.budgets[i].id),
                        ),
                      ),
                    ),
                ],
              ),
      ),
      'setAside': CollapsibleSection(
        id: 'setAside',
        title: 'Set aside',
        summary: money(raw.budgetTotals.locked),
        child: _SetAside(totals: raw.budgetTotals, money: money),
      ),
      'upcoming': CollapsibleSection(
        id: 'upcoming',
        title: 'Upcoming recurring',
        summary: '${raw.upcomingRecurring.length} in 7 days',
        trailingLabel: 'Manage recurring',
        onTrailingTap: () => shell.push(const RecurringScreen()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < raw.upcomingRecurring.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == raw.upcomingRecurring.length - 1 ? 0 : S.sm,
                ),
                child: _UpcomingRow(
                  rule: raw.upcomingRecurring[i],
                  money: moneyIn,
                ),
              ),
          ],
        ),
      ),
      'tabWishlist': Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TabWidgetCard(
              tab: raw.tab,
              money: money,
              onOpen: () => shell.push(const TabScreen()),
            ),
          ),
          const GapX(S.md),
          Expanded(
            child: WishlistWidgetCard(
              wishlist: raw.wishlist,
              onOpen: () => shell.push(const WishlistScreen()),
            ),
          ),
        ],
      ),
      'familySupport': FamilySupportCard(data: raw.familySupport, money: money),
      'categoryHeat': CategoryHeatCard(
        alerts: raw.categoryHeatAlerts,
        money: money,
      ),
      if (raw.household != null)
        'household': HouseholdCard(household: raw.household!, money: money),
      'analytics': AppCard(
        prominence: Prominence.quiet,
        onTap: () => shell.push(const AnalyticsScreen()),
        child: Row(
          children: [
            IconTile(icon: Icons.bar_chart_rounded, color: t.primary, size: 44),
            const GapX(S.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Full analytics',
                    style: TextStyle(
                      fontSize: AppType.body,
                      fontWeight: W.bold,
                      color: t.foreground,
                    ),
                  ),
                  const Gap(S.hair),
                  const Muted('Trends, heatmap, burn rate, payees & more'),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, size: 18, color: t.mutedForeground),
          ],
        ),
      ),
    };

    // Cards that would render as an empty state are dropped instead.
    final hasData = <String, bool>{
      'upcoming': raw.upcomingRecurring.isNotEmpty,
      'categoryHeat': raw.categoryHeatAlerts.isNotEmpty,
      'familySupport': raw.familySupport.count > 0,
      'household': raw.household != null,
      'setAside': toNum(raw.budgetTotals.locked) > 0,
    };

    final bodyIds = [
      for (final id in prefs.applyOrder(kBodyCards.map((c) => c.id).toList()))
        if (body.containsKey(id) && shows(id, hasData: hasData[id] ?? true)) id,
    ];

    return [
      // --- tier 1 ------------------------------------------------------------
      FadeInUp(
        child: HeroBalance(
          data: raw,
          money: money,
          currency: currency,
          breakdown: breakdown,
          userName: user?.firstName,
          onManageAccounts: () => shell.goTo(ShellTab.wallets),
        ),
      ),

      // --- tier 2 ------------------------------------------------------------
      if (insightPages.isNotEmpty) ...[
        const Gap(S.xl),
        const _TierLabel('Worth knowing'),
        const Gap(S.xs),
        Muted('Swipe cards · tap any for the full story', size: 12),
        const Gap(S.md),
        FadeInUp(
          delay: const Duration(milliseconds: 60),
          child: InsightCarousel(pages: insightPages),
        ),
      ],

      // --- tier 3 onwards ----------------------------------------------------
      for (var i = 0; i < bodyIds.length; i++) ...[
        const Gap(S.lg),
        FadeInUp.staggered(index: i, offset: 8, child: body[bodyIds[i]]!),
      ],
    ];
  }
}

/// Quiet uppercase divider between dashboard tiers.
class _TierLabel extends StatelessWidget {
  const _TierLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Row(
      children: [
        Eyebrow(text),
        const GapX(S.md),
        Expanded(child: Divider(color: t.border, height: 1)),
      ],
    );
  }
}

/// The four mini figures, as one 2×2 block rather than four separate cards.
class _QuickStats extends StatelessWidget {
  const _QuickStats({
    required this.raw,
    required this.month,
    required this.money,
  });

  final DashboardData raw;
  final MonthSummary month;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatMini(
                label: 'Net this month',
                value: money(month.net),
                icon: Icons.trending_up,
                positive: toNum(month.net) >= 0,
              ),
            ),
            const GapX(S.md),
            Expanded(
              child: StatMini(
                label: 'Avg daily spend',
                value: money(month.avgDailySpend),
                icon: Icons.trending_down,
              ),
            ),
          ],
        ),
        const Gap(S.md),
        Row(
          children: [
            Expanded(
              child: StatMini(
                label: 'Unnecessary',
                value: money(raw.unnecessary.total),
                icon: Icons.local_fire_department_outlined,
                warning: toNum(raw.unnecessary.total) > 0,
              ),
            ),
            const GapX(S.md),
            Expanded(
              child: StatMini(
                label: 'Upcoming bills',
                value: '${raw.upcomingRecurring.length}',
                icon: Icons.savings_outlined,
                hint: 'next 7 days',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SetAside extends StatelessWidget {
  const _SetAside({required this.totals, required this.money});

  final BudgetTotals totals;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Amount(money(totals.locked), size: AppType.figure, color: t.primary),
        const Gap(S.hair),
        Muted(
          'locked in ${totals.activeCount} active plan'
          '${totals.activeCount == 1 ? '' : 's'}   every balance above is shown '
          'after this money is taken out',
          size: AppType.caption,
        ),
        const Gap(S.lg),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Muted('Filled this cycle', size: AppType.caption),
                  const Gap(S.hair),
                  Amount(money(totals.funded)),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Muted('Spent from plans', size: AppType.caption),
                  const Gap(S.hair),
                  Amount(money(totals.spent)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.rule, required this.money});

  final RecurringRule rule;
  final String Function(Object?, String) money;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.md),
      decoration: BoxDecoration(
        color: t.surfaceMuted.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          IconTile(
            icon: financeIcon(rule.category?.icon),
            color: parseHexColor(rule.category?.color),
            size: 34,
          ),
          const GapX(S.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.bodySm,
                    fontWeight: W.semibold,
                    color: t.foreground,
                  ),
                ),
                Muted(formatDate(rule.nextRun), size: AppType.caption),
              ],
            ),
          ),
          Amount(money(rule.amount, rule.currency), size: AppType.bodySm),
        ],
      ),
    );
  }
}

class _BudgetMiniRow extends StatelessWidget {
  const _BudgetMiniRow({required this.budget, required this.money, this.onTap});

  final BudgetRow budget;
  final String Function(Object?, String) money;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final planned = toNum(budget.plannedAmount) <= 0
        ? 0.01
        : toNum(budget.plannedAmount);
    final spentPct = (toNum(budget.spentAmount) / planned * 100).clamp(
      0.0,
      100.0,
    );
    final spent = money(budget.spentAmount, budget.currency);
    final filled = money(budget.fundedAmount, budget.currency);
    final left = money(budget.balance, budget.currency);

    return PressableScale(
      onTap: onTap,
      child: Semantics(
        button: onTap != null,
        label: '${budget.name}. $spent spent of $filled filled. $left left.',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      budget.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.bodySm,
                        fontWeight: W.semibold,
                        color: context.t.foreground,
                      ),
                    ),
                  ),
                  const GapX(S.sm),
                  Muted('$left left', size: AppType.caption),
                ],
              ),
              const Gap(S.xs),
              ProgressBar(
                value: spentPct,
                tone: switch (budget.health) {
                  BudgetHealth.drained => BadgeTone.danger,
                  BudgetHealth.low => BadgeTone.warning,
                  _ => BadgeTone.primary,
                },
              ),
              const Gap(S.xxs),
              Muted('$spent spent of $filled filled', size: AppType.caption),
            ],
          ),
        ),
      ),
    );
  }
}
