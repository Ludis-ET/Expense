import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../offline/sync_engine.dart';
import '../state/capture_store.dart';
import '../state/data_store.dart';
import '../widgets/sync_status.dart';
import 'accounts_screen.dart';
import 'budgets_screen.dart';
import 'capture/inbox_screen.dart';
import 'dashboard_screen.dart';
import 'transaction_form.dart';
import 'transactions_screen.dart';

/// The signed-in frame: five tabs and one add button.
///
/// Tabs are kept alive in an IndexedStack so switching back to a list does not
/// refetch and lose scroll position - on a phone that churn is very visible.
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
    // Paint cached data first so a cold start offline is useful immediately,
    // then refresh from the network when there is one.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final data = context.read<DataStore>();
      final capture = context.read<CaptureStore>();
      final sync = context.read<SyncEngine>();

      await Future.wait([
        data.hydrateFromCache(),
        capture.hydrateFromCache(),
        sync.refreshCounts(),
      ]);
      if (!mounted) return;

      await data.refreshAll();
      if (!mounted) return;
      await capture.refresh();
      if (!mounted) return;
      await capture.loadBanks();
    });
  }

  Future<void> _addTransaction() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TransactionForm()),
    );
    if (created == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final needsReview = context.select<CaptureStore, int>((s) => s.needsReview);

    return Scaffold(
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
          : FloatingActionButton(
              onPressed: _addTransaction,
              tooltip: 'Add transaction',
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
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
              child: const Icon(Icons.mark_email_unread),
            ),
            label: 'Inbox',
          ),
          const NavigationDestination(
            icon: Icon(Icons.pie_chart_outline),
            selectedIcon: Icon(Icons.pie_chart),
            label: 'Plans',
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Wallets',
          ),
        ],
      ),
    );
  }
}
