import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../screens/analytics_screen.dart';
import '../screens/guides_screen.dart';
import '../screens/money_tab_screen.dart';
import '../screens/settings_screen.dart';

/// Website sidebar replica for mobile.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.onSelectTab});

  /// 0 Home, 1 Activity, 2 Wallets, 3 Plans
  final ValueChanged<int> onSelectTab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;

    Widget group(String label, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: colors.muted,
                  ),
                ),
              ),
              ...children,
            ],
          ),
        );

    Widget item(IconData icon, String label, VoidCallback onTap) => ListTile(
          leading: Icon(icon, size: 20, color: colors.muted),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
        );

    return Drawer(
      backgroundColor: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  const BrandRow(),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: colors.muted),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.border),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                children: [
                  group('Overview', [
                    item(Icons.dashboard_outlined, 'Dashboard', () => onSelectTab(0)),
                  ]),
                  group('Money', [
                    item(Icons.swap_horiz_rounded, 'Transactions', () => onSelectTab(1)),
                    item(Icons.account_balance_wallet_outlined, 'Accounts', () => onSelectTab(2)),
                  ]),
                  group('Insights', [
                    item(Icons.bar_chart_rounded, 'Analytics', () {
                      Navigator.of(context).push(santimRoute(const AnalyticsScreen()));
                    }),
                    item(Icons.menu_book_outlined, 'Guides', () {
                      Navigator.of(context).push(santimRoute(const GuidesScreen()));
                    }),
                  ]),
                  group('Plan', [
                    item(Icons.savings_outlined, 'Budgets & Wishes', () => onSelectTab(3)),
                    item(Icons.handshake_outlined, 'Money Tab', () {
                      Navigator.of(context).push(santimRoute(const MoneyTabScreen()));
                    }),
                  ]),
                ],
              ),
            ),
            Divider(height: 1, color: colors.border),
            item(Icons.settings_outlined, 'Settings', () {
              Navigator.of(context).push(santimRoute(const SettingsScreen()));
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
