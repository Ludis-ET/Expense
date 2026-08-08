import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../state/capture_store.dart';
import '../state/data_store.dart';
import '../state/notification_store.dart';
import '../offline/sync_engine.dart';
import '../widgets/app_drawer.dart';
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
  /// 0 Home, 1 Activity, 2 Wallets, 3 Plans
  int _index = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

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
    await showTransactionFormSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    final pages = const [
      DashboardScreen(),
      TransactionsScreen(),
      AccountsScreen(),
      BudgetsScreen(),
    ];

    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(
        onSelectTab: (i) => setState(() => _index = i),
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: pages,
            ),
          ),
        ],
      ),
      bottomNavigationBar: _WebStyleBottomNav(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
        onAdd: _addTransaction,
        onOpenInbox: () => Navigator.of(context).push(santimRoute(const InboxScreen())),
        onOpenMenu: () => _scaffoldKey.currentState?.openDrawer(),
      ),
    );
  }
}

class _WebStyleBottomNav extends StatelessWidget {
  const _WebStyleBottomNav({
    required this.index,
    required this.onSelect,
    required this.onAdd,
    required this.onOpenInbox,
    required this.onOpenMenu,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onOpenInbox;
  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;
    final needsReview = context.select<CaptureStore, int>((s) => s.needsReview);
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.92),
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.border.withValues(alpha: 0.8))),
          boxShadow: [
            BoxShadow(
              color: theme.brightness == Brightness.light
                  ? const Color(0x0F0C1222)
                  : Colors.black.withValues(alpha: 0.35),
              blurRadius: 30,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        padding: EdgeInsets.only(bottom: bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _Tab(
                    label: 'Home',
                    icon: Icons.dashboard_outlined,
                    activeIcon: Icons.dashboard_rounded,
                    selected: index == 0,
                    onTap: () => onSelect(0),
                    onLongPress: onOpenMenu,
                  ),
                  _Tab(
                    label: 'Activity',
                    icon: Icons.swap_horiz_rounded,
                    activeIcon: Icons.swap_horiz_rounded,
                    selected: index == 1,
                    onTap: () => onSelect(1),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Transform.translate(
                          offset: const Offset(0, -10),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: onAdd,
                              borderRadius: BorderRadius.circular(16),
                              child: Ink(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [colors.primary, colors.accent],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: colors.primary.withValues(alpha: 0.3),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                  border: Border.all(
                                    color: theme.scaffoldBackgroundColor,
                                    width: 4,
                                  ),
                                ),
                                child: Icon(Icons.add_rounded, color: theme.colorScheme.onPrimary, size: 22),
                              ),
                            ),
                          ),
                        ),
                        Text(
                          'Add',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                  _Tab(
                    label: 'Wallets',
                    icon: Icons.account_balance_wallet_outlined,
                    activeIcon: Icons.account_balance_wallet_rounded,
                    selected: index == 2,
                    onTap: () => onSelect(2),
                  ),
                  _Tab(
                    label: 'Plan',
                    icon: Icons.savings_outlined,
                    activeIcon: Icons.savings_rounded,
                    selected: index == 3,
                    onTap: () => onSelect(3),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
              child: Material(
                color: colors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: onOpenInbox,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.sms_rounded, size: 14, color: colors.primary),
                        const SizedBox(width: 8),
                        Text(
                          needsReview > 0 ? 'Inbox · $needsReview to review' : 'Bank SMS inbox',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SantimColors>()!;
    final color = selected ? colors.primary : colors.muted;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: selected ? colors.primary.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(selected ? activeIcon : icon, size: 18, color: color),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color),
              ),
              const SizedBox(height: 2),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 2,
                width: selected ? 20 : 0,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
