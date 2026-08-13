import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../core/home_widget.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../state/auth_state.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../state/sms_state.dart';
import '../../widgets/sync_ui.dart';
import '../../widgets/ui.dart';
import '../accounts/accounts_screen.dart';
import '../analytics/analytics_screen.dart';
import '../assistant/assistant_screen.dart';
import '../budgets/budgets_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../guides/guides_screen.dart';
import '../ledger/tab_screen.dart';
import '../outlook/monthly_outlook_screen.dart';
import '../review/month_in_review_screen.dart';
import '../search/global_search_screen.dart';
import '../settings/settings_screen.dart';
import '../sms/sms_inbox_hub.dart';
import '../wishlist/wishlist_screen.dart';
import '../transactions/transaction_form.dart';
import '../transactions/transactions_screen.dart';
import '../update/app_update_sheet.dart';
import 'notifications_sheet.dart';

/// The five bottom-nav destinations, matching `mobile-bottom-nav.tsx`. The
/// middle slot is the raised "Add" button rather than a tab.
enum ShellTab { home, activity, wallets, plan }

/// Signed-in container: topbar, swipeable tab body, drawer and bottom bar.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => AppShellState();

  /// Lets any descendant jump tabs   used by "View all →" style links.
  static AppShellState of(BuildContext context) =>
      context.findAncestorStateOfType<AppShellState>()!;
}

class AppShellState extends State<AppShell>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _navKeys = {
    for (final t in ShellTab.values) t: GlobalKey<NavigatorState>(),
  };
  late final _routeObservers = {
    for (final t in ShellTab.values)
      t: _RouteDepthObserver(onChanged: () => _syncBrandBar(forTab: t)),
  };
  ShellTab _tab = ShellTab.home;
  bool _brandBarVisible = true;

  /// Drives the shared-axis transition between tabs. Switching destinations
  /// used to be a bare `setState` swap   an instant cut on the move users make
  /// more than any other.
  late final AnimationController _swap = AnimationController(
    vsync: this,
    duration: Motion.enter,
    value: 1,
  );

  /// +1 when moving right through the tab bar, -1 when moving left, so the
  /// incoming screen enters from the side it came from.
  int _swapDirection = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DataState>().primeAll();
      context.read<SmsState>().refreshStats();
      _syncBrandBar(forTab: _tab);
      _handleWidgetLaunch();
      maybePromptAppUpdate(context);
    });
  }

  /// Opens the add sheet when the app was launched from the home-screen
  /// widget's "+" rather than its body.
  Future<void> _handleWidgetLaunch() async {
    final action = await HomeWidget.consumeLaunchAction();
    if (action == HomeWidget.addAction && mounted) {
      await openAddTransaction(presetKind: 'EXPENSE');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _swap.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<SmsState>().refreshStats();
      context.read<SmsState>().flushUploads();
    }
  }

  void _syncBrandBar({ShellTab? forTab}) {
    final tab = forTab ?? _tab;
    if (tab != _tab) return;
    final canPop = _navKeys[tab]?.currentState?.canPop() ?? false;
    final visible = !canPop;
    if (_brandBarVisible != visible && mounted) {
      setState(() => _brandBarVisible = visible);
    }
  }

  void goTo(ShellTab tab) {
    if (_tab == tab) {
      // Tapping the active tab pops its stack back to the root.
      _navKeys[tab]!.currentState?.popUntil((r) => r.isFirst);
      _syncBrandBar(forTab: tab);
      return;
    }
    Haptics.select();
    setState(() {
      _swapDirection =
          ShellTab.values.indexOf(tab) > ShellTab.values.indexOf(_tab) ? 1 : -1;
      _tab = tab;
    });
    _swap
      ..value = 0
      ..forward();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncBrandBar(forTab: tab),
    );
  }

  /// Pushes a route inside the active tab so the bottom bar stays put.
  Future<T?> push<T>(Widget page) => _navKeys[_tab]!.currentState!.push<T>(
    MaterialPageRoute(builder: (_) => page),
  );

  Future<void> openAddTransaction({String? presetKind}) async {
    // Opening a sheet is not a commit   the buzz belongs on the save.
    Haptics.toggle();
    final created = await showTransactionForm(context, presetKind: presetKind);
    if (created == true && mounted) {
      await context.read<DataState>().refreshAfterWrite();
    }
  }

  /// Long-pressing the add button: pick the kind first, so logging an expense
  /// is one gesture and one tap rather than opening the full sheet blind.
  Future<void> openQuickAdd() async {
    Haptics.select();
    final kind = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SheetShell(
        title: 'Log what?',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.lg, 0, S.lg, S.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (kind, label, icon, tone) in const [
                (
                  'EXPENSE',
                  'Expense',
                  Icons.north_east_rounded,
                  BadgeTone.danger,
                ),
                (
                  'INCOME',
                  'Income',
                  Icons.south_west_rounded,
                  BadgeTone.success,
                ),
                (
                  'TRANSFER',
                  'Transfer',
                  Icons.swap_horiz_rounded,
                  BadgeTone.info,
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: S.sm),
                  child: _QuickKindRow(
                    label: label,
                    icon: icon,
                    tone: tone,
                    onTap: () => Navigator.of(ctx).pop(kind),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (kind != null && mounted) await openAddTransaction(presetKind: kind);
  }

  /// Android/iOS back: close drawer → pop tab stack → Home tab → leave app.
  void _handleSystemBack() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold?.isDrawerOpen ?? false) {
      scaffold!.closeDrawer();
      return;
    }
    final nav = _navKeys[_tab]?.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return;
    }
    if (_tab != ShellTab.home) {
      goTo(ShellTab.home);
      return;
    }
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return PopScope(
      // Nested tab Navigators do not receive the OS back button; intercept here.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleSystemBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: t.background,
        extendBody: true,
        drawer: const _AppDrawer(),
        body: MeshBackground(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                AnimatedSize(
                  duration: Motion.fast,
                  curve: Motion.easeOut,
                  alignment: Alignment.topCenter,
                  clipBehavior: Clip.hardEdge,
                  child: _brandBarVisible
                      ? _Topbar(
                          onMenu: () => _scaffoldKey.currentState?.openDrawer(),
                        )
                      : const SizedBox.shrink(),
                ),
                Expanded(
                  // The stack itself keeps every tab alive, so the animation
                  // rides on top of it rather than rebuilding the destination.
                  child: AnimatedBuilder(
                    animation: _swap,
                    builder: (context, child) {
                      if (MediaQuery.disableAnimationsOf(context))
                        return child!;
                      final v = Motion.shared.transform(_swap.value);
                      return Opacity(
                        opacity: v,
                        child: Transform.translate(
                          offset: Offset(_swapDirection * 26 * (1 - v), 0),
                          child: child,
                        ),
                      );
                    },
                    child: IndexedStack(
                      index: ShellTab.values.indexOf(_tab),
                      children: [
                        for (final tab in ShellTab.values)
                          RepaintBoundary(
                            child: _TabNavigator(
                              navigatorKey: _navKeys[tab]!,
                              observers: [_routeObservers[tab]!],
                              child: switch (tab) {
                                ShellTab.home => const DashboardScreen(),
                                ShellTab.activity => const TransactionsScreen(),
                                ShellTab.wallets => const AccountsScreen(),
                                ShellTab.plan => const BudgetsScreen(),
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _BottomNav(
          active: _tab,
          onSelect: goTo,
          onAdd: openAddTransaction,
          onAddLongPress: openQuickAdd,
          onAsk: () {
            Haptics.select();
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => const AssistantScreen(),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Each tab keeps its own navigation stack, so pushing a detail screen inside
/// "Plan" does not reset "Home".
class _TabNavigator extends StatelessWidget {
  const _TabNavigator({
    required this.navigatorKey,
    required this.observers,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final List<NavigatorObserver> observers;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      observers: observers,
      onGenerateRoute: (settings) =>
          MaterialPageRoute(settings: settings, builder: (_) => child),
    );
  }
}

/// Notifies the shell when a tab pushes or pops so the brand bar can hide.
class _RouteDepthObserver extends NavigatorObserver {
  _RouteDepthObserver({required this.onChanged});
  final VoidCallback onChanged;

  void _notify() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => onChanged());

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _notify();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _notify();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _notify();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _notify();
}

// ---------------------------------------------------------------------------
// Topbar
// ---------------------------------------------------------------------------

class _Topbar extends StatelessWidget {
  const _Topbar({required this.onMenu});
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final data = context.watch<DataState>();
    final prefs = context.watch<PrefsState>();
    final user = context.watch<AuthState>().user;

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: S.md),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(
          bottom: BorderSide(color: t.border.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(
        children: [
          IconPill(
            icon: Icons.menu_rounded,
            background: Colors.transparent,
            onTap: onMenu,
          ),
          const GapX(S.hair),
          const BrandMark(size: 26),
          const GapX(S.sm),
          const BrandWord(fontSize: AppType.lead),
          const Spacer(),
          const SyncStatusPill(),
          const GapX(S.xs),
          IconPill(
            icon: Icons.search_rounded,
            background: Colors.transparent,
            tooltip: 'Search',
            onTap: () {
              Haptics.select();
              final shell = AppShell.of(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GlobalSearchScreen(shell: shell),
                ),
              );
            },
          ),
          if (data.currencies.length > 1) ...[
            _CurrencySwitcher(data: data),
            const GapX(S.xs),
          ],
          IconPill(
            icon: prefs.amountsHidden
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            background: Colors.transparent,
            tooltip: prefs.amountsHidden ? 'Show amounts' : 'Hide amounts',
            onTap: () {
              Haptics.select();
              prefs.toggleAmounts();
            },
          ),
          IconPill(
            icon: Icons.mark_email_unread_outlined,
            background: Colors.transparent,
            badge: context.watch<SmsState>().needsReview,
            tooltip: 'Message inbox',
            onTap: () {
              Haptics.select();
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SmsInboxHub()));
            },
          ),
          IconPill(
            icon: Icons.notifications_none_rounded,
            background: Colors.transparent,
            badge: data.unreadCount,
            onTap: () => showNotificationsSheet(context),
          ),
          const GapX(S.xxs),
          GestureDetector(
            onTap: onMenu,
            child: Avatar(
              name: user?.name ?? '?',
              avatarId: user?.avatarId,
              size: 30,
            ),
          ),
          const GapX(S.xxs),
        ],
      ),
    );
  }
}

/// `CurrencyBadge`   only rendered when the user actually holds more than one
/// currency, since totals are never mixed.
class _CurrencySwitcher extends StatelessWidget {
  const _CurrencySwitcher({required this.data});
  final DataState data;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return PressableScale(
      onTap: () async {
        final picked = await showAppSheet<String>(
          context,
          title: 'Currency',
          subtitle: 'Totals are never mixed across currencies.',
          scrollable: false,
          builder: (ctx) => Padding(
            padding: EdgeInsets.only(
              bottom: 20 + MediaQuery.of(ctx).padding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in data.currencies)
                  ListTile(
                    onTap: () => Navigator.pop(ctx, c),
                    selected: c == data.activeCurrency,
                    selectedTileColor: t.primary.withValues(alpha: 0.08),
                    title: Text(
                      c,
                      style: TextStyle(
                        fontSize: AppType.body,
                        fontWeight: FontWeight.w600,
                        color: t.foreground,
                      ),
                    ),
                    trailing: c == data.activeCurrency
                        ? Icon(Icons.check_circle, size: 20, color: t.primary)
                        : null,
                  ),
              ],
            ),
          ),
        );
        if (picked != null) data.setActiveCurrency(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.xs),
        decoration: BoxDecoration(
          color: t.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              data.activeCurrency,
              style: TextStyle(
                fontSize: AppType.caption,
                fontWeight: FontWeight.w700,
                color: t.primary,
              ),
            ),
            Icon(Icons.expand_more, size: 14, color: t.primary),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom navigation
// ---------------------------------------------------------------------------

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.active,
    required this.onSelect,
    required this.onAdd,
    required this.onAddLongPress,
    required this.onAsk,
  });

  final ShellTab active;
  final ValueChanged<ShellTab> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onAddLongPress;
  final VoidCallback onAsk;

  static const _items = <(ShellTab, IconData, String)>[
    (ShellTab.home, Icons.space_dashboard_outlined, 'Home'),
    (ShellTab.activity, Icons.swap_horiz_rounded, 'Activity'),
    (ShellTab.wallets, Icons.account_balance_wallet_outlined, 'Wallets'),
    (ShellTab.plan, Icons.savings_outlined, 'Plan'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    const fabSize = 56.0;
    const fabOverlap = fabSize / 2;
    const navRowHeight = 58.0;
    const askBarHeight = 34.0;
    const askBarPadding = 8.0;

    return SizedBox(
      height:
          fabOverlap +
          navRowHeight +
          askBarHeight +
          askBarPadding +
          bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            top: fabOverlap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.surface,
                border: Border(
                  top: BorderSide(color: t.border.withValues(alpha: 0.8)),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: t.isDark ? 0.28 : 0.05,
                    ),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomInset),
                child: Column(
                  children: [
                    SizedBox(
                      height: navRowHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          for (var i = 0; i < 2; i++)
                            Expanded(
                              child: _NavItem(
                                item: _items[i],
                                active: active,
                                onSelect: onSelect,
                              ),
                            ),
                          const SizedBox(width: fabSize + 12),
                          for (var i = 2; i < 4; i++)
                            Expanded(
                              child: _NavItem(
                                item: _items[i],
                                active: active,
                                onSelect: onSelect,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        12,
                        0,
                        12,
                        askBarPadding,
                      ),
                      child: PressableScale(
                        scale: 0.99,
                        onTap: onAsk,
                        child: Container(
                          height: askBarHeight,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: t.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(R.md),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 14,
                                color: t.primary,
                              ),
                              const GapX(S.xs),
                              Text(
                                'Ask Santim',
                                style: TextStyle(
                                  fontSize: AppType.label,
                                  fontWeight: FontWeight.w700,
                                  color: t.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // FAB   top half floats above the bar, fully inside this widget's bounds
          Positioned(
            top: 0,
            child: _AddButton(
              onTap: onAdd,
              onLongPress: onAddLongPress,
              size: fabSize,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.active,
    required this.onSelect,
  });

  final (ShellTab, IconData, String) item;
  final ShellTab active;
  final ValueChanged<ShellTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final isActive = item.$1 == active;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect(item.$1),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.easeOut,
            width: 34,
            height: 28,
            decoration: BoxDecoration(
              color: isActive
                  ? t.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(R.sm + 2),
            ),
            child: Icon(
              item.$2,
              size: 19,
              color: isActive ? t.primary : t.mutedForeground,
            ),
          ),
          const Gap(S.hair),
          Text(
            item.$3,
            style: TextStyle(
              fontSize: AppType.micro,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              color: isActive ? t.primary : t.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

/// The raised circular FAB that floats above the bottom bar.
/// One row of the long-press quick-add sheet.
class _QuickKindRow extends StatelessWidget {
  const _QuickKindRow({
    required this.label,
    required this.icon,
    required this.tone,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final BadgeTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final (bg, fg) = AppBadge.colorsFor(context, tone);

    return PressableScale(
      onTap: () {
        Haptics.select();
        onTap();
      },
      child: Semantics(
        button: true,
        label: 'Log $label',
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: S.lg,
              vertical: S.md,
            ),
            decoration: BoxDecoration(
              color: t.surfaceMuted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: t.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Icon(icon, size: 18, color: fg),
                ),
                const GapX(S.md),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: AppType.body,
                      fontWeight: W.semibold,
                      color: t.foreground,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: t.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap, this.onLongPress, this.size = 56});
  final VoidCallback onTap;

  /// Long press skips the kind picker   expense, income or transfer straight
  /// away, for the entries logged over and over.
  final VoidCallback? onLongPress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      width: size + 8,
      height: size + 8,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: t.primary.withValues(alpha: 0.32),
            blurRadius: 14,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Semantics(
        button: true,
        label: 'Add transaction',
        hint: 'Long press for expense, income or transfer',
        child: ExcludeSemantics(
          child: PressableScale(
            scale: 0.9,
            onTap: onTap,
            onLongPress: onLongPress,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [t.primary, t.accent],
                ),
                border: Border.all(color: t.background, width: 4),
              ),
              child: Icon(
                Icons.add_rounded,
                size: size * 0.48,
                color: t.primaryForeground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Drawer
// ---------------------------------------------------------------------------

class _AppDrawer extends StatelessWidget {
  const _AppDrawer();

  static const _groups = <(String, List<(String, IconData, String)>)>[
    ('Overview', [('dashboard', Icons.space_dashboard_outlined, 'Dashboard')]),
    (
      'Money',
      [
        ('transactions', Icons.swap_horiz_rounded, 'Transactions'),
        ('accounts', Icons.account_balance_wallet_outlined, 'Accounts'),
      ],
    ),
    (
      'Insights',
      [
        ('analytics', Icons.bar_chart_rounded, 'Analytics'),
        ('outlook', Icons.insights_rounded, 'Monthly outlook'),
        ('review', Icons.auto_awesome_rounded, 'Month in review'),
        ('guides', Icons.menu_book_outlined, 'Guides'),
      ],
    ),
    (
      'Plan',
      [
        ('budgets', Icons.savings_outlined, 'Budgets & Plans'),
        ('wishlist', Icons.favorite_border, 'Wishlist'),
        ('tab', Icons.volunteer_activism_outlined, 'Money Tab'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final user = context.watch<AuthState>().user;
    final shell = AppShell.of(context);

    void go(String key) {
      Navigator.pop(context);
      switch (key) {
        case 'dashboard':
          shell.goTo(ShellTab.home);
        case 'transactions':
          shell.goTo(ShellTab.activity);
        case 'accounts':
          shell.goTo(ShellTab.wallets);
        case 'budgets':
          shell.goTo(ShellTab.plan);
        case 'wishlist':
          shell.push(const WishlistScreen());
        case 'analytics':
          shell.push(const AnalyticsScreen());
        case 'outlook':
          shell.push(const MonthlyOutlookScreen());
        case 'review':
          shell.push(const MonthInReviewScreen());
        case 'guides':
          shell.push(const GuidesScreen());
        case 'tab':
          shell.push(const TabScreen());
        case 'settings':
          shell.push(const SettingsScreen());
      }
    }

    return Drawer(
      width: 282,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(S.xl, S.lg, S.md, S.sm),
              child: Row(
                children: [
                  const BrandMark(size: 32),
                  const GapX(S.sm),
                  const BrandWord(fontSize: AppType.heading),
                  const Spacer(),
                  IconPill(
                    icon: Icons.close,
                    size: 32,
                    background: Colors.transparent,
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: S.md),
                children: [
                  for (var g = 0; g < _groups.length; g++) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        S.md,
                        S.md,
                        S.md,
                        S.xs,
                      ),
                      child: Eyebrow(_groups[g].$1),
                    ),
                    for (final item in _groups[g].$2)
                      _DrawerItem(
                        icon: item.$2,
                        label: item.$3,
                        onTap: () => go(item.$1),
                      ),
                  ],
                ],
              ),
            ),
            Divider(color: t.border, height: 1),
            _DrawerItem(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () => go('settings'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.md, S.xs, S.md, S.md),
              child: Container(
                padding: const EdgeInsets.all(S.md),
                decoration: BoxDecoration(
                  color: t.surfaceMuted.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(R.md),
                ),
                child: Row(
                  children: [
                    Avatar(
                      name: user?.name ?? '?',
                      avatarId: user?.avatarId,
                      size: 36,
                    ),
                    const GapX(S.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.name ?? '',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppType.bodySm,
                              fontWeight: FontWeight.w700,
                              color: t.foreground,
                            ),
                          ),
                          Muted(user?.email ?? '', size: 11, maxLines: 1),
                        ],
                      ),
                    ),
                    IconPill(
                      icon: Icons.logout_rounded,
                      size: 32,
                      tooltip: 'Sign out',
                      background: Colors.transparent,
                      onTap: () async {
                        final ok = await confirm(
                          context,
                          title: 'Sign out?',
                          message:
                              'You will need your email and password to get back in.',
                          confirmLabel: 'Sign out',
                        );
                        if (ok && context.mounted) {
                          await context.read<AuthState>().logout();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.hair, vertical: S.hair),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(R.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: S.md,
              vertical: S.md,
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: t.mutedForeground),
                const GapX(S.md),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w500,
                    color: t.foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
