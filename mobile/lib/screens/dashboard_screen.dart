import 'package:flutter/material.dart';
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
import 'capture/capture_setup_screen.dart';
import 'capture/inbox_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'transaction_detail_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final capture = context.watch<CaptureStore>();
    final unread = context.select<NotificationStore, int>((s) => s.unread);
    final user = context.select<AuthStore, String?>((s) => s.user?.name);
    final d = data.dashboard;
    final theme = Theme.of(context);

    return Scaffold(
      body: RefreshIndicator(
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
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user == null ? 'Santim' : 'Hi, ${user.split(' ').first}',
                    style: theme.textTheme.titleLarge,
                  ),
                  Text(
                    'Your money today',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              actions: [
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Center(child: SyncStatusPill(compact: true)),
                ),
                IconButton(
                  tooltip: 'Notifications',
                  onPressed: () => Navigator.of(context).push(santimRoute(const NotificationsScreen())),
                  icon: Badge(
                    isLabelVisible: unread > 0,
                    label: Text(unread > 9 ? '9+' : '$unread'),
                    child: const Icon(Icons.notifications_none_rounded),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(context).push(santimRoute(const SettingsScreen())),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
              sliver: SliverList.list(
                children: [
                  if (data.loading && d.recent.isEmpty) ...[
                    const ShimmerBlock(height: 180),
                    const SizedBox(height: 14),
                    const ShimmerBlock(height: 100),
                  ] else ...[
                    FadeIn(child: _HeroBalance(data: d)),
                    const SizedBox(height: 14),
                    if (!capture.native.healthy) ...[
                      SoftCard(
                        onTap: () => Navigator.of(context).push(santimRoute(const CaptureSetupScreen())),
                        gradient: LinearGradient(
                          colors: [
                            SantimTheme.seed.withValues(alpha: 0.14),
                            SantimTheme.seed.withValues(alpha: 0.04),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.sms_rounded, color: SantimTheme.seed),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Set up bank SMS capture',
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (capture.needsReview > 0) ...[
                      SoftCard(
                        onTap: () => Navigator.of(context).push(santimRoute(const InboxScreen())),
                        color: SantimTheme.warning.withValues(alpha: 0.1),
                        child: Row(
                          children: [
                            const Icon(Icons.mark_email_unread_rounded, color: SantimTheme.warning),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${capture.needsReview} message${capture.needsReview == 1 ? '' : 's'} need review',
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    _MonthStrip(month: d.month),
                    const SizedBox(height: 18),
                    if (d.budgetsAtRisk.isNotEmpty) ...[
                      const SectionLabel('Plans running low'),
                      ...d.budgetsAtRisk.map(
                        (b) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SoftCard(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(b.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${Money.format(b.potBalance, currency: b.currency)} left',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                StatusPill(
                                  label: '${b.pctSpentOfFunded.round()}%',
                                  tone: PillTone.warn,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SectionLabel('Recent activity'),
                    if (d.recent.isEmpty)
                      const EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'No activity yet',
                        message: 'Add a transaction or pair your phone for bank SMS.',
                      )
                    else
                      ...d.recent.map(
                        (tx) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: SoftCard(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            onTap: () => Navigator.of(context).push(
                              santimRoute(TransactionDetailScreen(tx: tx)),
                            ),
                            child: TransactionTile(tx: tx),
                          ),
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
  const _HeroBalance({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftCard(
      padding: EdgeInsets.zero,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: SantimTheme.heroGradient(theme.brightness),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Free to spend',
              style: theme.textTheme.labelLarge?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            Text(
              Money.format(data.totalBalance, currency: data.displayCurrency),
              style: theme.textTheme.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    label: 'In wallets',
                    value: Money.format(data.realBalance, currency: data.displayCurrency),
                  ),
                ),
                Expanded(
                  child: _HeroStat(
                    label: 'In plans',
                    value: Money.format(data.budgetLocked, currency: data.displayCurrency),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
      ],
    );
  }
}

class _MonthStrip extends StatelessWidget {
  const _MonthStrip({required this.month});

  final MonthSummary month;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('In', style: TextStyle(fontWeight: FontWeight.w700, color: SantimTheme.income)),
                const SizedBox(height: 6),
                Text(
                  Money.format(month.income, currency: month.currency),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Out', style: TextStyle(fontWeight: FontWeight.w700, color: SantimTheme.expense)),
                const SizedBox(height: 6),
                Text(
                  Money.format(month.expense, currency: month.currency),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
      ],
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
    final color = SantimTheme.amountColor(tx.kind, theme.colorScheme);

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Container(
        height: 44,
        width: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          switch (tx.kind) {
            'INCOME' => Icons.south_west_rounded,
            'EXPENSE' => Icons.north_east_rounded,
            _ => Icons.swap_horiz_rounded,
          },
          size: 20,
          color: color,
        ),
      ),
      title: Text(
        tx.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w700,
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
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            Money.signed(tx.amount, tx.kind, currency: tx.currency),
            style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
          if (tx.pendingSync)
            const Icon(Icons.cloud_upload_outlined, size: 14, color: SantimTheme.warning),
        ],
      ),
    );
  }
}
