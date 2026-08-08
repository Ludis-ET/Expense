import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/capture_store.dart';
import '../state/data_store.dart';
import '../state/notification_store.dart';
import '../offline/sync_engine.dart';
import '../widgets/sync_status.dart';
import 'accounts_screen.dart';
import 'budgets_screen.dart';
import 'capture/cash_account_sheet.dart';
import 'capture/inbox_screen.dart';
import 'dashboard_screen.dart';
import 'transaction_form.dart';
import 'transactions_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final data = context.read<DataStore>();
      final capture = context.read<CaptureStore>();
      final sync = context.read<SyncEngine>();
      final notes = context.read<NotificationStore>();

      await Future.wait([
        data.hydrateFromCache(),
        capture.hydrateFromCache(),
        sync.refreshCounts(),
        notes.hydrateFromCache(),
      ]);
      if (!mounted) return;

      await data.refreshAll();
      if (!mounted) return;
      await Future.wait([capture.refresh(), notes.start(), capture.loadBanks()]);
      if (!mounted) return;

      if (data.cashAccountId == null && data.activeAccounts.isNotEmpty) {
        await CashAccountSheet.show(context);
      }
    });
  }

  Future<void> _addTransaction() async {
    await Navigator.of(context).push(santimRoute(const TransactionForm()));
  }

  @override
  Widget build(BuildContext context) {
    final needsReview = context.select<CaptureStore, int>((s) => s.needsReview);
    final theme = Theme.of(context);

    return Scaffold(
      extendBody: true,
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const [
                DashboardScreen(),
                TransactionsScreen(),
                InboxScreen(),
                BudgetsScreen(),
                AccountsScreen(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _index == 2
          ? null
          : FloatingActionButton.extended(
              onPressed: _addTransaction,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
              backgroundColor: SantimTheme.seed,
              foregroundColor: Colors.white,
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.96),
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: needsReview > 0,
              label: Text('$needsReview'),
              child: const Icon(Icons.mark_email_unread_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: needsReview > 0,
              label: Text('$needsReview'),
              child: const Icon(Icons.mark_email_unread_rounded),
            ),
            label: 'Inbox',
          ),
          const NavigationDestination(
            icon: Icon(Icons.pie_chart_outline_rounded),
            selectedIcon: Icon(Icons.pie_chart_rounded),
            label: 'Plans',
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet_rounded),
            label: 'Wallets',
          ),
        ],
      ),
    );
  }
}
