import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../models/finance.dart';
import '../widgets/common.dart';

class AccountDetailScreen extends StatelessWidget {
  const AccountDetailScreen({super.key, required this.account});

  final Account account;

  static const _icons = {
    'CASH': Icons.payments_rounded,
    'BANK': Icons.account_balance_rounded,
    'MOBILE_MONEY': Icons.smartphone_rounded,
    'CARD': Icons.credit_card_rounded,
    'OTHER': Icons.wallet_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;
    final typeLabel = account.type.replaceAll('_', ' ').toLowerCase();

    return Scaffold(
      appBar: AppBar(title: Text(account.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
                      ),
                      child: Icon(
                        _icons[account.type] ?? Icons.wallet_rounded,
                        color: colors.primary,
                        size: 26,
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
                                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (account.isDefault) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    'default',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: colors.primary),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            '$typeLabel · ${account.currency}',
                            style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  Money.format(account.available, currency: account.currency),
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${Money.format(account.realBalance, currency: account.currency)} real · '
                  '${Money.format(account.locked, currency: account.currency)} in plan pots',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SoftCard(
            child: Column(
              children: [
                _row(context, 'Available to spend', Money.format(account.available, currency: account.currency)),
                _row(context, 'In the account', Money.format(account.realBalance, currency: account.currency)),
                _row(context, 'Set aside in plans', Money.format(account.locked, currency: account.currency)),
                if (account.accountNumber != null)
                  _row(context, 'Account number', account.accountNumber!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: colors.muted))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
