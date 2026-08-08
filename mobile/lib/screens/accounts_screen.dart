import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../models/finance.dart';
import '../state/data_store.dart';
import '../widgets/common.dart';
import 'account_detail_screen.dart';

/// Wallets and their balances.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final accounts = data.activeAccounts.toList();
    final theme = Theme.of(context);

    final totalAvailable = accounts.fold<double>(0, (s, a) => s + Money.parse(a.available));
    final totalLocked = accounts.fold<double>(0, (s, a) => s + Money.parse(a.locked));

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: data.refreshAll,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverAppBar(
              floating: true,
              title: Text('Wallets'),
              actions: [
                InfoHint(
                  title: 'Free vs held',
                  message:
                      'Each wallet shows what is genuinely free to spend. Money filled into a '
                      'budget plan still sits in the account, but it is reserved — so it is '
                      'listed separately rather than counted as spendable.',
                ),
              ],
            ),
            if (data.loading && accounts.isEmpty)
              const SliverPadding(
                padding: EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(child: ShimmerBlock(height: 160)),
              )
            else if (accounts.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'No wallets',
                  message: 'Add accounts in the Santim web app and they will appear here.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                sliver: SliverList.list(
                  children: [
                    SoftCard(
                      gradient: LinearGradient(
                        colors: [
                          SantimTheme.seed.withValues(alpha: 0.14),
                          SantimTheme.seed.withValues(alpha: 0.04),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Free to spend', style: theme.textTheme.labelLarge),
                                const SizedBox(height: 6),
                                Text(
                                  Money.format(totalAvailable),
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: SantimTheme.income,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (totalLocked > 0)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Held in plans', style: theme.textTheme.labelLarge),
                                  const SizedBox(height: 6),
                                  Text(
                                    Money.format(totalLocked),
                                    style: theme.textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: SantimTheme.warning,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (final a in accounts) ...[
                      _AccountCard(account: a),
                      const SizedBox(height: 10),
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

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account});

  final Account account;

  static const _icons = {
    'CASH': Icons.payments_outlined,
    'BANK': Icons.account_balance_outlined,
    'MOBILE_MONEY': Icons.smartphone_outlined,
    'CARD': Icons.credit_card_outlined,
    'OTHER': Icons.wallet_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SoftCard(
      onTap: () => Navigator.of(context).push(santimRoute(AccountDetailScreen(account: account))),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              _icons[account.type] ?? Icons.wallet_outlined,
              color: theme.colorScheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        account.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (account.isDefault) ...[
                      const SizedBox(width: 8),
                      const StatusPill(label: 'Default', tone: PillTone.neutral),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  account.hasReservation
                      ? '${Money.format(account.realBalance, currency: account.currency)} in account · '
                          '${Money.format(account.locked, currency: account.currency)} held'
                      : account.type.replaceAll('_', ' ').toLowerCase(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Money.format(account.available, currency: account.currency),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ],
      ),
    );
  }
}
