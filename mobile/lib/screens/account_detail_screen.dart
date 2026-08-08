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
    final typeLabel = account.type.replaceAll('_', ' ').toLowerCase();

    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          SoftCard(
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
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          _icons[account.type] ?? Icons.wallet_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      if (account.isDefault)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Default',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    account.name,
                    style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    typeLabel,
                    style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Free to spend',
                    style: theme.textTheme.labelLarge?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    Money.format(account.available, currency: account.currency),
                    style: theme.textTheme.displaySmall?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SoftCard(
            child: Column(
              children: [
                _row(context, 'In the account', Money.format(account.realBalance, currency: account.currency)),
                _row(context, 'Held in plans', Money.format(account.locked, currency: account.currency)),
                _row(context, 'Currency', account.currency),
                if (account.accountNumber != null)
                  _row(context, 'Account number', account.accountNumber!),
              ],
            ),
          ),
          if (account.hasReservation) ...[
            const SizedBox(height: 14),
            SoftCard(
              color: SantimTheme.warning.withValues(alpha: 0.08),
              child: Text(
                'Some of this wallet is reserved for budget plans. That money still sits here, '
                'but it is not counted as free to spend.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
