import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/haptics.dart';
import '../../core/layout.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/prefs_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';
import '../analytics/analytics_screen.dart';
import '../assistant/assistant_screen.dart';
import '../budgets/budget_detail_screen.dart';
import '../guides/guides_screen.dart';
import '../ledger/tab_screen.dart';
import '../recurring/recurring_screen.dart';
import '../settings/settings_screen.dart';
import '../shell/app_shell.dart';
import '../transactions/transaction_detail.dart';
import '../wishlist/wishlist_screen.dart';

/// Powerful unified search — `GET /search` with deep-links that survive the
/// root-navigator push from the shell topbar.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key, this.shell});

  /// Captured from [AppShell] before this route is pushed above it.
  final AppShellState? shell;

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _SearchHit {
  _SearchHit({
    required this.id,
    required this.type,
    required this.title,
    required this.screen,
    this.subtitle,
    this.amount,
    this.currency,
    this.icon,
    this.color,
    this.entityId,
    this.params = const {},
  });

  final String id;
  final String type;
  final String title;
  final String? subtitle;
  final String? amount;
  final String? currency;
  final String? icon;
  final String? color;
  final String screen;
  final String? entityId;
  final Map<String, String> params;
}

class _SearchGroup {
  _SearchGroup({required this.type, required this.label, required this.items});
  final String type;
  final String label;
  final List<_SearchHit> items;
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _controller = TextEditingController();

  Timer? _debounce;
  String _query = '';
  List<_SearchGroup> _groups = const [];
  bool _searching = false;
  String? _error;
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      setState(() {
        _groups = const [];
        _searching = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 260), () => _fetch(q));
  }

  Future<void> _fetch(String q) async {
    final id = ++_requestId;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final res = await context.read<ApiClient>().get<Map<String, dynamic>>(
        '/search',
        query: {'q': q, 'limit': '12'},
      );
      if (!mounted || id != _requestId || q != _query.trim()) return;

      final groups = <_SearchGroup>[];
      for (final g in asList(res['groups'])) {
        final items = <_SearchHit>[];
        for (final raw in asList(g['items'])) {
          final href = asMap(raw['href']);
          final params = <String, String>{};
          final paramsRaw = href['params'];
          if (paramsRaw is Map) {
            paramsRaw.forEach((k, v) {
              if (v != null) params['$k'] = '$v';
            });
          }
          items.add(
            _SearchHit(
              id: asStr(raw['id']),
              type: asStr(g['type'], asStr(raw['type'])),
              title: asStr(raw['title'], 'Untitled'),
              subtitle: asStrOrNull(raw['subtitle']),
              amount: asStrOrNull(raw['amount']),
              currency: asStrOrNull(raw['currency']),
              icon: asStrOrNull(raw['icon']),
              color: asStrOrNull(raw['color']),
              screen: asStr(href['screen'], 'home'),
              entityId: asStrOrNull(href['id']),
              params: params,
            ),
          );
        }
        if (items.isNotEmpty) {
          groups.add(
            _SearchGroup(
              type: asStr(g['type']),
              label: asStr(g['label'], asStr(g['type'])),
              items: items,
            ),
          );
        }
      }

      setState(() {
        _groups = groups;
        _searching = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _searching = false;
        _error = e is ApiError ? e.message : 'Could not reach the server.';
        _groups = const [];
      });
    }
  }

  AppShellState? get _shell {
    if (widget.shell != null && widget.shell!.mounted) return widget.shell;
    return context.findAncestorStateOfType<AppShellState>();
  }

  Future<void> _afterClose(FutureOr<void> Function() action) async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await action();
  }

  Future<void> _open(_SearchHit hit) async {
    Haptics.select();
    final shell = _shell;

    switch (hit.screen) {
      case 'transaction':
        try {
          final page = await context.read<ApiClient>().get<Map<String, dynamic>>(
            '/transactions',
            query: {'q': hit.title, 'pageSize': '20'},
          );
          if (!mounted) return;
          final items = mapList(page['items'], Transaction.fromJson);
          final tx = items.where((t) => t.id == (hit.entityId ?? hit.id)).firstOrNull ??
              items.firstOrNull;
          if (tx != null) {
            await showTransactionDetail(context, tx);
            return;
          }
        } catch (_) {}
        await _afterClose(() async => shell?.goTo(ShellTab.activity));
      case 'budget':
        await _afterClose(() async {
          if (shell == null) return;
          shell.goTo(ShellTab.plan);
          await Future<void>.delayed(const Duration(milliseconds: 40));
          if (!shell.mounted) return;
          await shell.push(
            BudgetDetailScreen(budgetId: hit.entityId ?? hit.id),
          );
        });
      case 'wallets':
        await _afterClose(() async => shell?.goTo(ShellTab.wallets));
      case 'plan':
      case 'plans':
      case 'budgets':
        await _afterClose(() async => shell?.goTo(ShellTab.plan));
      case 'activity':
      case 'transactions':
        await _afterClose(() async => shell?.goTo(ShellTab.activity));
      case 'home':
      case 'dashboard':
        await _afterClose(() async => shell?.goTo(ShellTab.home));
      case 'wishlist':
        await _afterClose(() async {
          if (shell == null) return;
          await shell.push(const WishlistScreen());
        });
      case 'recurring':
        await _afterClose(() async {
          if (shell == null) return;
          await shell.push(const RecurringScreen());
        });
      case 'tab':
      case 'ledger':
        await _afterClose(() async {
          if (shell == null) return;
          await shell.push(
            TabScreen(focusEntryId: hit.params['e'] ?? hit.entityId),
          );
        });
      case 'assistant':
        await _afterClose(() async {
          await Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(builder: (_) => const AssistantScreen()),
          );
        });
      case 'settings':
        await _afterClose(() async {
          if (shell == null) return;
          await shell.push(const SettingsScreen());
        });
      case 'guide':
        await _afterClose(() async {
          if (shell == null) return;
          await shell.push(const GuidesScreen());
        });
      case 'analytics':
        await _afterClose(() async {
          if (shell == null) return;
          await shell.push(const AnalyticsScreen());
        });
      default:
        await _afterClose(() async => shell?.goTo(ShellTab.home));
    }
  }

  int get _total => _groups.fold(0, (n, g) => n + g.items.length);

  IconData _iconFor(_SearchHit hit) {
    switch (hit.type) {
      case 'transaction':
        return financeIcon(hit.icon);
      case 'budget':
        return Icons.savings_outlined;
      case 'account':
        return financeIcon(hit.icon);
      case 'category':
        return financeIcon(hit.icon);
      case 'recurring':
        return Icons.event_repeat_outlined;
      case 'wishlist':
        return Icons.favorite_border_rounded;
      case 'ledger':
        return Icons.volunteer_activism_outlined;
      case 'guide':
        return Icons.menu_book_outlined;
      case 'command':
        return Icons.north_east_rounded;
      default:
        return Icons.search_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final prefs = context.watch<PrefsState>();
    final q = _query.trim();

    return Scaffold(
      backgroundColor: t.background,
      body: MeshBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 12, 8),
                child: Row(
                  children: [
                    IconPill(
                      icon: Icons.arrow_back_rounded,
                      background: Colors.transparent,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: t.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: t.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: t.isDark ? 0.22 : 0.045,
                              ),
                              blurRadius: 18,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: AppTextField(
                          controller: _controller,
                          placeholder: 'Search money, plans, people…',
                          prefixIcon: Icons.search_rounded,
                          autofocus: true,
                          onChanged: _onChanged,
                          textInputAction: TextInputAction.search,
                          suffix: _controller.text.isEmpty
                              ? null
                              : IconPill(
                                  icon: Icons.close_rounded,
                                  size: 28,
                                  background: Colors.transparent,
                                  onTap: () {
                                    _controller.clear();
                                    _onChanged('');
                                  },
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    4,
                    16,
                    ShellLayout.bottomClearance(context),
                  ),
                  children: [
                    if (q.length < 2) ...[
                      const Gap(S.xl),
                      const _HeroHint(),
                      const Gap(S.xl),
                      _SuggestionGrid(
                        onPick: (s) {
                          _controller.text = s;
                          _controller.selection = TextSelection.collapsed(
                            offset: s.length,
                          );
                          _onChanged(s);
                        },
                      ),
                    ] else ...[
                      if (_error != null) ...[
                        _ErrorBanner(message: _error!),
                        const Gap(S.md),
                      ],
                      if (_searching && _total == 0)
                        const Padding(
                          padding: EdgeInsets.only(top: 28),
                          child: PageLoader(rows: 3, hero: false),
                        ),
                      if (!_searching && _total == 0 && _error == null)
                        EmptyState(
                          icon: Icons.search_off_rounded,
                          art: EmptyArt.search,
                          title: 'Nothing matches “$q”',
                          description:
                              'Try a payee, plan name, person on your Money Tab, or a guide topic.',
                        ),
                      if (_total > 0) ...[
                        Row(
                          children: [
                            Text(
                              '$_total result${_total == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: t.mutedForeground,
                              ),
                            ),
                            if (_searching) ...[
                              const GapX(8),
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.6,
                                  color: t.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const Gap(S.md),
                        for (final group in _groups) ...[
                          _SectionHeader(
                            label: group.label,
                            count: group.items.length,
                          ),
                          const Gap(S.sm),
                          for (final hit in group.items) ...[
                            _HitCard(
                              title: hit.title,
                              subtitle: hit.subtitle,
                              icon: _iconFor(hit),
                              color: parseHexColor(hit.color) ?? t.primary,
                              trailing: hit.amount != null
                                  ? prefs.money(
                                      hit.amount!,
                                      currency: hit.currency ?? 'ETB',
                                    )
                                  : null,
                              onTap: () => _open(hit),
                            ),
                            const Gap(S.sm),
                          ],
                          const Gap(S.md),
                        ],
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroHint extends StatelessWidget {
  const _HeroHint();

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                t.primary.withValues(alpha: 0.16),
                t.accent.withValues(alpha: 0.1),
              ],
            ),
            border: Border.all(color: t.primary.withValues(alpha: 0.22)),
          ),
          child: Icon(Icons.travel_explore_rounded, color: t.primary, size: 26),
        ),
        const Gap(S.lg),
        Text(
          'Search everything',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: t.foreground,
          ),
        ),
        const Gap(S.sm),
        Text(
          'Transactions, plans, wallets, people you owe, wishlist wants, guides — one field.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppType.bodySm,
            height: 1.45,
            color: t.mutedForeground,
          ),
        ),
      ],
    );
  }
}

class _SuggestionGrid extends StatelessWidget {
  const _SuggestionGrid({required this.onPick});
  final void Function(String) onPick;

  static const _ideas = [
    ('Salary', Icons.payments_outlined),
    ('Rent', Icons.home_outlined),
    ('Wishlist', Icons.favorite_border),
    ('Ask Santim', Icons.auto_awesome),
    ('Who owes me', Icons.volunteer_activism_outlined),
    ('Emergency', Icons.shield_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick finds',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: t.mutedForeground,
          ),
        ),
        const Gap(S.sm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, icon) in _ideas)
              Material(
                color: t.surface,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  onTap: () => onPick(label),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: t.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 14, color: t.primary),
                        const GapX(6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: t.foreground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: t.foreground,
          ),
        ),
        const GapX(8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: t.surfaceMuted,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: t.mutedForeground,
            ),
          ),
        ),
      ],
    );
  }
}

class _HitCard extends StatelessWidget {
  const _HitCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.lg),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: t.border.withValues(alpha: 0.85)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const GapX(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.bodySm,
                        fontWeight: FontWeight.w700,
                        color: t.foreground,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const Gap(2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: t.mutedForeground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const GapX(8),
                Text(
                  trailing!,
                  style: TextStyle(
                    fontSize: AppType.bodySm,
                    fontWeight: FontWeight.w700,
                    color: t.foreground,
                  ),
                ),
              ] else
                Icon(Icons.chevron_right_rounded, color: t.mutedForeground, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: t.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, size: 16, color: t.danger),
          const GapX(8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: t.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
