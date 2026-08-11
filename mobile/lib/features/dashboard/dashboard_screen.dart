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
import '../shell/app_shell.dart';
import '../transactions/transaction_detail.dart';
import '../transactions/transaction_list.dart';
import '../wishlist/wishlist_screen.dart';
import 'dashboard_widgets.dart';

/// The dashboard, laid out as one scrolling column. The web page arranges the
/// same blocks across a 3-column grid; on a phone the order is preserved and
/// everything stacks.
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
        padding: EdgeInsets.fromLTRB(14, 14, 14, ShellLayout.bottomClearance(context)),
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
    final scoped = raw.recentTransactions.where((tx) => tx.currency == currency).toList();

    return [
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
      const SizedBox(height: 14),
      FadeInUp(
        delay: const Duration(milliseconds: 60),
        child: SmartInsightCard(data: raw, money: money),
      ),
      const SizedBox(height: 14),
      FadeInUp(
        delay: const Duration(milliseconds: 90),
        child: FinancialHealthCard(data: raw, money: money),
      ),
      const SizedBox(height: 14),

      // The four widget cards the web app shows in a 4-up grid.
      FadeInUp(
        delay: const Duration(milliseconds: 120),
        child: WeeklySnapshotCard(data: raw.weeklySnapshot, prefs: prefs),
      ),
      const SizedBox(height: 14),
      FadeInUp(
        delay: const Duration(milliseconds: 140),
        child: SpendingStreaksCard(data: raw.spendingStreak, prefs: prefs),
      ),
      const SizedBox(height: 14),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: FadeInUp(
              delay: const Duration(milliseconds: 160),
              child: TabWidgetCard(
                tab: raw.tab,
                money: money,
                onOpen: () => shell.push(const TabScreen()),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FadeInUp(
              delay: const Duration(milliseconds: 180),
              child: WishlistWidgetCard(
                wishlist: raw.wishlist,
                onOpen: () => shell.push(const WishlistScreen()),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      FadeInUp(
        delay: const Duration(milliseconds: 200),
        child: FamilySupportCard(data: raw.familySupport, money: money),
      ),
      const SizedBox(height: 14),
      FadeInUp(
        delay: const Duration(milliseconds: 210),
        child: CategoryHeatCard(alerts: raw.categoryHeatAlerts, money: money),
      ),
      if (raw.household != null) ...[
        const SizedBox(height: 14),
        FadeInUp(
          delay: const Duration(milliseconds: 220),
          child: HouseholdCard(household: raw.household!, money: money),
        ),
      ],
      const SizedBox(height: 14),

      // Mini stats, 2×2.
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
          const SizedBox(width: 12),
          Expanded(
            child: StatMini(
              label: 'Avg daily spend',
              value: money(month.avgDailySpend),
              icon: Icons.trending_down,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
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
          const SizedBox(width: 12),
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
      const SizedBox(height: 14),
      FadeInUp(child: SpendingPaceCard(month: month, money: money)),
      const SizedBox(height: 14),

      // Recent transactions.
      AppCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardTitleRow(
              title: 'Recent transactions',
              trailingLabel: 'View all',
              onTrailingTap: () => shell.goTo(ShellTab.activity),
            ),
            const SizedBox(height: 6),
            if (scoped.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: EmptyState(title: 'No transactions yet', compact: true),
              )
            else
              TransactionList(
                items: scoped.take(6).toList(),
                money: moneyIn,
                compact: true,
                onTap: (tx) => showTransactionDetail(context, tx),
              ),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // Budget plans.
      AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardTitleRow(
              title: 'Budget plans',
              trailingLabel: 'Manage',
              onTrailingTap: () => shell.goTo(ShellTab.plan),
            ),
            const SizedBox(height: 14),
            if (raw.budgets.isEmpty)
              const EmptyState(
                icon: Icons.savings_outlined,
                title: 'No plans yet',
                description: 'Set money aside for what you intend to spend.',
                compact: true,
              )
            else
              for (var i = 0; i < raw.budgets.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i == raw.budgets.length - 1 ? 0 : 14),
                  child: _BudgetMiniRow(
                    budget: raw.budgets[i],
                    money: moneyIn,
                    onTap: () => shell.push(BudgetDetailScreen(budgetId: raw.budgets[i].id)),
                  ),
                ),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // Set aside.
      AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardTitleRow(
              title: 'Set aside',
              hint: 'Every balance on this page is shown after this money is taken out.',
              trailingLabel: 'All plans',
              onTrailingTap: () => shell.goTo(ShellTab.plan),
            ),
            const SizedBox(height: 12),
            Amount(money(raw.budgetTotals.locked), size: 24, color: t.primary),
            const SizedBox(height: 2),
            Muted(
              'locked in ${raw.budgetTotals.activeCount} active plan'
              '${raw.budgetTotals.activeCount == 1 ? '' : 's'}',
              size: 11.5,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Muted('Filled this cycle', size: 11),
                      const SizedBox(height: 2),
                      Amount(money(raw.budgetTotals.funded), size: 14),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Muted('Spent from plans', size: 11),
                      const SizedBox(height: 2),
                      Amount(money(raw.budgetTotals.spent), size: 14),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),

      // Upcoming recurring.
      if (raw.upcomingRecurring.isNotEmpty) ...[
        const SizedBox(height: 14),
        AppCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CardTitleRow(
                title: 'Upcoming recurring (7 days)',
                trailingLabel: 'Manage',
                onTrailingTap: () => shell.push(const RecurringScreen()),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < raw.upcomingRecurring.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == raw.upcomingRecurring.length - 1 ? 0 : 8,
                  ),
                  child: FadeInUp.staggered(
                    index: i,
                    offset: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: t.surfaceMuted.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(R.md),
                        border: Border.all(color: t.border),
                      ),
                      child: Row(
                        children: [
                          IconTile(
                            icon: financeIcon(raw.upcomingRecurring[i].category?.icon),
                            color: parseHexColor(raw.upcomingRecurring[i].category?.color),
                            size: 34,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  raw.upcomingRecurring[i].name,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: t.foreground,
                                  ),
                                ),
                                Muted(formatDate(raw.upcomingRecurring[i].nextRun), size: 11),
                              ],
                            ),
                          ),
                          Amount(
                            moneyIn(
                              raw.upcomingRecurring[i].amount,
                              raw.upcomingRecurring[i].currency,
                            ),
                            size: 13.5,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 14),

      // Analytics entry point.
      AppCard(
        padding: const EdgeInsets.all(16),
        onTap: () => shell.push(const AnalyticsScreen()),
        child: Row(
          children: [
            IconTile(icon: Icons.bar_chart_rounded, color: t.primary, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Full analytics',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: t.foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Muted('Trends, heatmap, burn rate, payees & more', size: 12),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, size: 18, color: t.mutedForeground),
          ],
        ),
      ),
    ];
  }
}

class _BudgetMiniRow extends StatelessWidget {
  const _BudgetMiniRow({required this.budget, required this.money, this.onTap});

  final BudgetRow budget;
  final String Function(Object?, String) money;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final planned = toNum(budget.plannedAmount) <= 0 ? 0.01 : toNum(budget.plannedAmount);
    final spentPct = (toNum(budget.spentAmount) / planned * 100).clamp(0.0, 100.0);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
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
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: context.t.foreground,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Muted('${money(budget.balance, budget.currency)} left', size: 11.5),
            ],
          ),
          const SizedBox(height: 6),
          ProgressBar(
            value: spentPct,
            tone: switch (budget.health) {
              BudgetHealth.drained => BadgeTone.danger,
              BudgetHealth.low => BadgeTone.warning,
              _ => BadgeTone.primary,
            },
          ),
          const SizedBox(height: 5),
          Muted(
            '${money(budget.spentAmount, budget.currency)} spent of '
            '${money(budget.fundedAmount, budget.currency)} filled',
            size: 11,
          ),
        ],
      ),
    );
  }
}
