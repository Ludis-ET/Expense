import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../models/finance.dart';
import '../state/data_store.dart';
import '../widgets/common.dart';
import '../widgets/scoped_tx_list.dart';
import '../widgets/web_chrome.dart';
import 'transfer_sheet.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final accounts = data.activeAccounts.toList();
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;
    final totalAvailable = accounts.fold<double>(0, (s, a) => s + Money.parse(a.available));
    final totalReal = accounts.fold<double>(0, (s, a) => s + Money.parse(a.realBalance));
    final totalLocked = accounts.fold<double>(0, (s, a) => s + Money.parse(a.locked));
    final currency = accounts.isNotEmpty ? accounts.first.currency : 'ETB';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: data.refreshAll,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              floating: true,
              leading: IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
              ),
              title: const Text('Accounts'),
              actions: [
                TextButton.icon(
                  onPressed: accounts.length < 2 ? null : () => showTransferSheet(context),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('Transfer'),
                ),
                const WebTopActions(),
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
                  title: 'No accounts',
                  message: 'Add your first wallet to start tracking.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                sliver: SliverList.list(
                  children: [
                    SoftCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Available to spend · $currency',
                            style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            Money.format(totalAvailable, currency: currency),
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          if (totalLocked > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              '${Money.format(totalReal, currency: currency)} actually in your accounts · '
                              '${Money.format(totalLocked, currency: currency)} set aside in budget plans',
                              style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                            ),
                          ],
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
    final colors = theme.extension<SantimColors>()!;
    final typeLabel = account.type.replaceAll('_', ' ').toLowerCase();

    return SoftCard(
      onTap: () => showSantimSheet(
        context: context,
        title: account.name,
        maxHeightFactor: 0.94,
        builder: (_) => _AccountDetailBody(account: account),
      ),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(_icons[account.type] ?? Icons.wallet_outlined, color: colors.primary, size: 22),
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
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
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
                const SizedBox(height: 4),
                Text(
                  account.hasReservation
                      ? '${Money.format(account.realBalance, currency: account.currency)} real · '
                          '${Money.format(account.locked, currency: account.currency)} in plan pots'
                      : '$typeLabel · ${account.currency}',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
          Text(
            Money.format(account.available, currency: account.currency),
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _AccountDetailBody extends StatefulWidget {
  const _AccountDetailBody({required this.account});
  final Account account;

  @override
  State<_AccountDetailBody> createState() => _AccountDetailBodyState();
}

class _AccountDetailBodyState extends State<_AccountDetailBody> {
  List<Transaction> _txs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await context.read<DataStore>().fetchTransactions(accountId: widget.account.id);
    if (!mounted) return;
    setState(() {
      _txs = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;
    final typeLabel = account.type.replaceAll('_', ' ').toLowerCase();
    final income = _txs.where((t) => t.kind == 'INCOME').fold<double>(0, (s, t) => s + Money.parse(t.amount));
    final expense = _txs.where((t) => t.kind == 'EXPENSE').fold<double>(0, (s, t) => s + Money.parse(t.amount));
    final transfers = _txs.where((t) => t.kind == 'TRANSFER').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(account.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text('$typeLabel · ${account.currency}', style: theme.textTheme.bodySmall?.copyWith(color: colors.muted)),
              const SizedBox(height: 12),
              Text(
                Money.format(account.available, currency: account.currency),
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                '${Money.format(account.realBalance, currency: account.currency)} real · '
                '${Money.format(account.locked, currency: account.currency)} in plan pots',
                style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _stat(context, 'Income', Money.format(income, currency: account.currency)),
                  _stat(context, 'Expenses', Money.format(expense, currency: account.currency)),
                  _stat(context, 'Transfers', '$transfers'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Transactions', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        Text(
          _loading ? 'Loading…' : '${_txs.length} shown',
          style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
        ),
        const SizedBox(height: 10),
        ScopedTransactionList(
          items: _txs,
          loading: _loading,
          popBeforeDetail: true,
          emptyMessage: 'This account has no recorded transactions yet.',
        ),
      ],
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    final colors = Theme.of(context).extension<SantimColors>()!;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceMuted.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: TextStyle(fontSize: 10, letterSpacing: 0.6, color: colors.muted)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
