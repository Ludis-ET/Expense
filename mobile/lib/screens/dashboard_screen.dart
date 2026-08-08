import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../models/dashboard.dart';
import '../models/finance.dart';
import '../state/auth_store.dart';
import '../state/capture_store.dart';
import '../state/data_store.dart';
import '../widgets/common.dart';
import '../widgets/sync_status.dart';
import 'capture/capture_setup_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final capture = context.watch<CaptureStore>();
    final user = context.select<AuthStore, String?>((s) => s.user?.name);
    final d = data.dashboard;

    return Scaffold(
      appBar: AppBar(
        title: Text(user == null ? 'Santim' : 'Hi, ${user.split(' ').first}'),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Center(child: SyncStatusPill(compact: true)),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await data.refreshAll();
          await capture.refresh();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            _BalanceCard(
              available: d.totalBalance,
              real: d.realBalance,
              locked: d.budgetLocked,
              currency: d.displayCurrency,
            ),
            const SizedBox(height: 14),

            // Only shown until capture is actually running - once it is, this
            // becomes noise on the screen the user sees most often.
            if (!capture.native.healthy) ...[
              const _CaptureNudge(),
              const SizedBox(height: 14),
            ],

            if (capture.needsReview > 0) ...[
              _ReviewBanner(count: capture.needsReview),
              const SizedBox(height: 14),
            ],

            _MonthCard(month: d.month),
            const SizedBox(height: 14),

            if (d.budgetsAtRisk.isNotEmpty) ...[
              SectionCard(
                title: 'Plans running low',
                subtitle: 'Nearly out of the money you set aside',
                child: Column(
                  children: [
                    for (final b in d.budgetsAtRisk) _BudgetRow(budget: b),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            SectionCard(
              title: 'Recent activity',
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: d.recent.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Nothing recorded yet.', textAlign: TextAlign.center),
                    )
                  : Column(
                      children: [
                        for (final tx in d.recent.take(6)) TransactionTile(tx: tx),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The headline figure is *available* money, not the raw balance - it is the
/// number the overdraw guard enforces, so it is the only one that answers
/// "can I spend this?".
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.available,
    required this.real,
    required this.locked,
    required this.currency,
  });

  final String available;
  final String real;
  final String locked;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasReservations = Money.parse(locked) > 0;

    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.82)],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Free to spend',
                  style: theme.textTheme.labelLarge?.copyWith(color: Colors.white70),
                ),
                const Spacer(),
                if (hasReservations)
                  const InfoHintLight(
                    title: 'Free to spend',
                    message:
                        'Your accounts hold more than this. The difference is money already '
                        'set aside in budget plans — it is still yours, it is just spoken for.',
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              Money.format(available, currency: currency),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (hasReservations) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _MiniStat(label: 'In accounts', value: Money.format(real, currency: currency)),
                  const SizedBox(width: 18),
                  _MiniStat(label: 'Set aside', value: Money.format(locked, currency: currency)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: Colors.white70)),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Same idea as [InfoHint], tinted for the coloured balance card.
class InfoHintLight extends StatelessWidget {
  const InfoHintLight({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it')),
          ],
        ),
      ),
      child: const Icon(Icons.info_outline, size: 18, color: Colors.white70),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.month});

  final MonthSummary month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SectionCard(
      title: 'This month',
      child: Row(
        children: [
          Expanded(
            child: _Figure(
              label: 'In',
              value: Money.format(month.income, currency: month.currency),
              color: SantimTheme.income,
              deltaPct: month.incomeDeltaPct,
              deltaIsGoodWhenUp: true,
            ),
          ),
          Container(width: 1, height: 46, color: theme.dividerColor),
          Expanded(
            child: _Figure(
              label: 'Out',
              value: Money.format(month.expense, currency: month.currency),
              color: SantimTheme.expense,
              deltaPct: month.expenseDeltaPct,
              deltaIsGoodWhenUp: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.color,
    required this.deltaIsGoodWhenUp,
    this.deltaPct,
  });

  final String label;
  final String value;
  final Color color;
  final double? deltaPct;

  /// Income rising is good; spending rising is not. Without this the same
  /// arrow would be green in both places.
  final bool deltaIsGoodWhenUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delta = deltaPct;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        )),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
        // A null delta means there is no previous month to compare with, which
        // is different from "no change" and must not render as 0%.
        if (delta != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                delta >= 0 ? Icons.trending_up : Icons.trending_down,
                size: 14,
                color: (delta >= 0) == deltaIsGoodWhenUp ? SantimTheme.income : SantimTheme.expense,
              ),
              const SizedBox(width: 4),
              Text(
                '${delta.abs().toStringAsFixed(0)}% vs last month',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CaptureNudge extends StatelessWidget {
  const _CaptureNudge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CaptureSetupScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.sms_outlined, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stop typing transactions',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Let Santim read your bank SMS and fill them in for you.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SantimTheme.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SantimTheme.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.mark_email_unread_outlined, color: SantimTheme.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              count == 1
                  ? '1 bank message is waiting for you'
                  : '$count bank messages are waiting for you',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.budget});

  final Budget budget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(budget.name, style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                )),
              ),
              Text(
                '${Money.format(budget.potBalance, currency: budget.currency)} left',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: budget.progress,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(
                budget.progress >= 1 ? SantimTheme.expense : SantimTheme.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row in any transaction list.
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
      contentPadding: EdgeInsets.zero,
      leading: Container(
        height: 40,
        width: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          switch (tx.kind) {
            'INCOME' => Icons.south_west,
            'EXPENSE' => Icons.north_east,
            _ => Icons.swap_horiz,
          },
          size: 19,
          color: color,
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              tx.title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: tx.pendingSync
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.55)
                    : null,
              ),
            ),
          ),
          if (tx.pendingSync) ...[
            const SizedBox(width: 6),
            Icon(Icons.cloud_upload_outlined, size: 14, color: SantimTheme.warning),
          ],
          // Worth flagging: these rows were written from an SMS, not typed.
          if (tx.fromBankMessage) ...[
            const SizedBox(width: 6),
            Icon(Icons.bolt, size: 14, color: theme.colorScheme.primary),
          ],
        ],
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
      trailing: Text(
        Money.signed(tx.amount, tx.kind, currency: tx.currency),
        style: theme.textTheme.bodyLarge?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
