import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatting.dart';
import '../../core/theme.dart';
import '../../state/data_store.dart';
import '../../widgets/common.dart';

/// Asks which wallet holds physical cash.
///
/// This cannot be guessed. Wallets are named by the user and an account typed
/// `CASH` might still be a mobile-money float. Getting it wrong would book
/// every ATM withdrawal as spending, so the app asks rather than assumes — and
/// only asks once.
class CashAccountSheet extends StatelessWidget {
  const CashAccountSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => const CashAccountSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = context.watch<DataStore>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: SantimTheme.income.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.local_atm, color: SantimTheme.income),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Which wallet is your cash?',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'When you take money out of an ATM it has not been spent — it has moved '
              'from your bank into your pocket. Santim records that as a transfer into '
              'this wallet, so the spending only counts once you actually spend it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 18),
            if (data.activeAccounts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No wallets yet. Create one first and come back.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              ...data.activeAccounts.map((a) {
                final selected = data.cashAccountId == a.id;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => _choose(context, a.id),
                  leading: Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    color: selected ? SantimTheme.income : theme.colorScheme.outline,
                  ),
                  title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${a.type.toLowerCase().replaceAll('_', ' ')} · '
                    '${Money.format(a.available, currency: a.currency)}',
                  ),
                );
              }),

            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _choose(BuildContext context, String accountId) async {
    final data = context.read<DataStore>();

    try {
      await data.setCashAccount(accountId);
      if (!context.mounted) return;
      Navigator.pop(context);
      showOk(context, 'ATM withdrawals will move into ${data.accountById(accountId)?.name}');
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e.message);
    }
  }
}
