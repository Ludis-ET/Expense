import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../models/dashboard.dart';
import '../models/finance.dart';
import '../state/auth_store.dart';
import '../state/capture_store.dart';
import '../state/data_store.dart';
import '../state/notification_store.dart';
import '../widgets/common.dart';
import '../widgets/sync_status.dart';
import '../widgets/web_chrome.dart';
import 'capture/capture_setup_screen.dart';
import 'capture/inbox_screen.dart';
import 'transaction_detail_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final capture = context.watch<CaptureStore>();
    final user = context.select<AuthStore, String?>((s) => s.user?.name);
    final d = data.dashboard;
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;

    return Scaffold(
      body: RefreshIndicator(
        color: colors.primary,
        onRefresh: () async {
          await data.refreshAll();
          if (!context.mounted) return;
          await capture.refresh();
          if (!context.mounted) return;
          await context.read<NotificationStore>().refresh();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              floating: true,
              leading: IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
              ),
              title: const Text('Dashboard'),
              actions: const [
                Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Center(child: SyncStatusPill(compact: true)),
                ),
                WebTopActions(),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
              sliver: SliverList.list(
                children: [
                  if (data.loading && d.recent.isEmpty) ...[
                    const ShimmerBlock(height: 200),
                    const SizedBox(height: 12),
                    const ShimmerBlock(height: 88),
                  ] else ...[
                    FadeIn(child: _HeroBalance(data: d, userName: user?.split(' ').first)),
                    const SizedBox(height: 12),
                    if (!capture.native.healthy) ...[
                      SoftCard(
                        onTap: () => Navigator.of(context).push(santimRoute(const CaptureSetupScreen())),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.sms_rounded, color: colors.primary, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Set up bank SMS capture',
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: colors.muted),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (capture.needsReview > 0) ...[
                      SoftCard(
                        onTap: () => Navigator.of(context).push(santimRoute(const InboxScreen())),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: colors.warning.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.mark_email_unread_rounded, color: colors.warning, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${capture.needsReview} message${capture.needsReview == 1 ? '' : 's'} need review',
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: colors.muted),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _SmartInsight(data: d),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SoftCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Income', style: TextStyle(fontSize: 12, color: colors.muted, fontWeight: FontWeight.w500)),
                                const SizedBox(height: 6),
                                Text(
                                  Money.format(d.month.income, currency: d.month.currency),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colors.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SoftCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Spent', style: TextStyle(fontSize: 12, color: colors.muted, fontWeight: FontWeight.w500)),
                                const SizedBox(height: 6),
                                Text(
                                  Money.format(d.month.expense, currency: d.month.currency),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colors.danger,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (d.budgetsAtRisk.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const SectionLabel('Plans running low'),
                      ...d.budgetsAtRisk.map(
                        (b) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SoftCard(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${Money.format(b.potBalance, currency: b.currency)} left',
                                        style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                                      ),
                                    ],
                                  ),
                                ),
                                StatusPill(label: '${b.pctSpentOfFunded.round()}%', tone: PillTone.warn),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const SectionLabel('Recent activity'),
                    if (d.recent.isEmpty)
                      const EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No activity yet',
                        message: 'Add a transaction or pair your phone for bank SMS.',
                      )
                    else
                      SoftCard(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                        child: Column(
                          children: [
                            for (final tx in d.recent)
                              TransactionTile(
                                tx: tx,
                                onTap: () => showTransactionDetailSheet(context, tx),
                              ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroBalance extends StatelessWidget {
  const _HeroBalance({required this.data, this.userName});

  final DashboardData data;
  final String? userName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final greg = DateFormat('EEEE, d MMMM yyyy').format(now);
    final locked = Money.parse(data.budgetLocked);

    return SoftCard(
      padding: EdgeInsets.zero,
      gradient: SantimTheme.heroGradient(theme.brightness),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName == null ? greeting : '$greeting, $userName',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white70),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined, size: 13, color: Colors.white60),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                greg,
                                style: const TextStyle(fontSize: 12, color: Colors.white60),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Available to spend · ${data.displayCurrency}',
                style: const TextStyle(fontSize: 12, color: Colors.white60),
              ),
              const SizedBox(height: 8),
              Text(
                Money.format(data.totalBalance, currency: data.displayCurrency),
                style: theme.textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
              if (locked > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '${Money.format(data.realBalance, currency: data.displayCurrency)} in your accounts · '
                  '${Money.format(data.budgetLocked, currency: data.displayCurrency)} set aside in budget plans',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _HeroChip(label: 'Income', value: Money.format(data.month.income, currency: data.month.currency)),
                  _HeroChip(label: 'Spent', value: Money.format(data.month.expense, currency: data.month.currency)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.white70)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SmartInsight extends StatelessWidget {
  const _SmartInsight({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;
    final income = Money.parse(data.month.income);
    final net = Money.parse(data.month.income) - Money.parse(data.month.expense);
    String insight;
    if (data.budgetsAtRisk.isNotEmpty) {
      insight = '${data.budgetsAtRisk.length} budget plan${data.budgetsAtRisk.length == 1 ? ' is' : 's are'} running low.';
    } else if (Money.parse(data.budgetLocked) > 0) {
      insight =
          '${Money.format(data.budgetLocked, currency: data.displayCurrency)} is set aside in budget plans and excluded from your available balance.';
    } else if (income > 0 && net / income < 0.1) {
      insight = 'Your savings rate is below 10% this month. Consider cutting unnecessary expenses.';
    } else if (net > 0) {
      insight = "You're saving ${Money.format(net, currency: data.displayCurrency)} this month — keep it up!";
    } else {
      insight = 'Add transactions and set budgets to unlock personalized insights.';
    }

    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.lightbulb_outline_rounded, color: colors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SMART INSIGHT',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: colors.muted),
                ),
                const SizedBox(height: 4),
                Text(insight, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.tx, this.onTap});

  final Transaction tx;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;
    final color = SantimTheme.amountColor(tx.kind, theme.colorScheme);

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Container(
        height: 40,
        width: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          switch (tx.kind) {
            'INCOME' => Icons.south_west_rounded,
            'EXPENSE' => Icons.north_east_rounded,
            _ => Icons.swap_horiz_rounded,
          },
          size: 18,
          color: color,
        ),
      ),
      title: Text(
        tx.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: tx.pendingSync ? theme.colorScheme.onSurface.withValues(alpha: 0.55) : null,
        ),
      ),
      subtitle: Text(
        [
          if (tx.categoryName != null) tx.categoryName!,
          if (tx.accountName != null) tx.accountName!,
          Dates.day(tx.date),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: colors.muted),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            Money.signed(tx.amount, tx.kind, currency: tx.currency),
            style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          if (tx.pendingSync) Icon(Icons.cloud_upload_outlined, size: 14, color: colors.warning),
        ],
      ),
    );
  }
}
