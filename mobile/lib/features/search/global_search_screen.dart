import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/haptics.dart';
import '../../core/layout.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';
import '../budgets/budget_detail_screen.dart';
import '../recurring/recurring_screen.dart';
import '../shell/app_shell.dart';
import '../transactions/transaction_detail.dart';
import '../wishlist/wishlist_screen.dart';

/// One field over everything the app knows about.
///
/// The Activity tab could already filter transactions, but nothing searched
/// across budgets, accounts, categories or recurring rules   finding a plan by
/// name meant remembering which tab it lived in. This is the mobile answer to
/// the web app's command palette.
///
/// Accounts, budgets, categories and recurring rules are matched locally from
/// [DataState] (they are already loaded); transactions go to the server, since
/// only the most recent handful are held on the client.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _controller = TextEditingController();

  Timer? _debounce;
  String _query = '';
  List<Transaction> _transactions = const [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _transactions = const [];
        _searching = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _fetch(value.trim()),
    );
  }

  Future<void> _fetch(String q) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final res = await context.read<ApiClient>().get<Map<String, dynamic>>(
        '/transactions',
        query: {'q': q, 'pageSize': '12'},
      );
      if (!mounted || q != _query.trim()) return;
      setState(() {
        _transactions = mapList(res['items'], Transaction.fromJson);
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Local results still stand, so this is a partial failure, not a dead
        // end   say which half is missing.
        _error = 'Could not reach the server, showing local matches only.';
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final data = context.watch<DataState>();
    final prefs = context.watch<PrefsState>();
    final shell = AppShell.of(context);
    final q = _query.trim().toLowerCase();

    bool hit(String? s) => s != null && s.toLowerCase().contains(q);

    final accounts = q.isEmpty
        ? const <Account>[]
        : (data.accounts.data ?? const []).where((a) => hit(a.name)).toList();
    final budgets = q.isEmpty
        ? const <BudgetRow>[]
        : (data.budgets.data?.items ?? const [])
              .where((b) => hit(b.name))
              .toList();
    final categories = q.isEmpty
        ? const <TxCategory>[]
        : (data.categories.data ?? const []).where((c) => hit(c.name)).toList();
    final recurring = q.isEmpty
        ? const <RecurringRule>[]
        : (data.recurring.data ?? const []).where((r) => hit(r.name)).toList();

    final total =
        accounts.length +
        budgets.length +
        categories.length +
        recurring.length +
        _transactions.length;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: S.md),
          child: AppTextField(
            controller: _controller,
            placeholder: 'Search anything',
            prefixIcon: Icons.search,
            // The user tapped search to type   the keyboard should be up.
            autofocus: true,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            suffix: _controller.text.isEmpty
                ? null
                : IconPill(
                    icon: Icons.close_rounded,
                    size: 28,
                    background: Colors.transparent,
                    tooltip: 'Clear search',
                    onTap: () {
                      _controller.clear();
                      _onChanged('');
                    },
                  ),
          ),
        ),
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          S.lg,
          S.md,
          S.lg,
          ShellLayout.bottomClearance(context),
        ),
        children: [
          if (q.length < 2)
            const EmptyState(
              icon: Icons.search,
              art: EmptyArt.search,
              title: 'Search everything',
              description:
                  'Transactions, plans, wallets, categories and '
                  'recurring bills. Type at least two letters.',
            )
          else ...[
            if (_error != null) ...[_Notice(_error!), const Gap(S.md)],
            if (_searching && total == 0) const PageLoader(rows: 2),
            if (!_searching && total == 0 && _error == null)
              EmptyState(
                icon: Icons.search_off,
                art: EmptyArt.search,
                title: 'Nothing matches “${_query.trim()}”',
                description: 'Try a payee, a plan name, or part of a note.',
              ),
            _Group<Transaction>(
              label: 'Transactions',
              items: _transactions,
              builder: (tx) => _Row(
                icon: financeIcon(tx.category?.icon),
                color: parseHexColor(tx.category?.color),
                title: tx.payee?.isNotEmpty == true
                    ? tx.payee!
                    : (tx.note ?? 'Transaction'),
                subtitle:
                    '${formatDate(tx.date)} · ${tx.category?.name ?? 'Uncategorised'}',
                trailing: prefs.money(tx.amount, currency: tx.currency),
                onTap: () => showTransactionDetail(context, tx),
              ),
            ),
            _Group<BudgetRow>(
              label: 'Plans',
              items: budgets,
              builder: (b) => _Row(
                icon: Icons.savings_outlined,
                color: t.primary,
                title: b.name,
                subtitle:
                    '${prefs.money(b.balance, currency: b.currency)} left',
                onTap: () {
                  Navigator.of(context).pop();
                  shell.push(BudgetDetailScreen(budgetId: b.id));
                },
              ),
            ),
            _Group<Account>(
              label: 'Wallets',
              items: accounts,
              builder: (a) => _Row(
                icon: financeIcon(a.icon),
                color: parseHexColor(a.color),
                title: a.name,
                subtitle: a.type.label,
                trailing: prefs.money(a.balance, currency: a.currency),
                onTap: () {
                  Navigator.of(context).pop();
                  shell.goTo(ShellTab.wallets);
                },
              ),
            ),
            _Group<RecurringRule>(
              label: 'Recurring',
              items: recurring,
              builder: (r) => _Row(
                icon: Icons.event_repeat_outlined,
                color: t.accent,
                title: r.name,
                subtitle: 'next ${formatDate(r.nextRun)}',
                trailing: prefs.money(r.amount, currency: r.currency),
                onTap: () {
                  Navigator.of(context).pop();
                  shell.push(const RecurringScreen());
                },
              ),
            ),
            _Group<TxCategory>(
              label: 'Categories',
              items: categories,
              builder: (c) => _Row(
                icon: financeIcon(c.icon),
                color: parseHexColor(c.color),
                title: c.name,
                subtitle: c.isIncome ? 'Income category' : 'Expense category',
                onTap: () {
                  Navigator.of(context).pop();
                  shell.goTo(ShellTab.activity);
                },
              ),
            ),
            if ('wishlist'.contains(q) || 'wish'.contains(q))
              _Group<String>(
                label: 'Jump to',
                items: const ['Wishlist'],
                builder: (_) => _Row(
                  icon: Icons.card_giftcard_outlined,
                  color: t.accent,
                  title: 'Wishlist',
                  subtitle: 'Things you are saving for',
                  onTap: () {
                    Navigator.of(context).pop();
                    shell.push(const WishlistScreen());
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
      decoration: BoxDecoration(
        color: t.warning.withValues(alpha: t.isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 16, color: t.warning),
          const GapX(S.sm),
          Expanded(child: Muted(message, size: AppType.label)),
        ],
      ),
    );
  }
}

class _Group<T> extends StatelessWidget {
  const _Group({
    required this.label,
    required this.items,
    required this.builder,
  });

  final String label;
  final List<T> items;
  final Widget Function(T) builder;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Gap(S.md),
        SectionLabel('$label · ${items.length}'),
        for (var i = 0; i < items.length; i++)
          FadeInUp.staggered(index: i, offset: 6, child: builder(items[i])),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final Color? color;
  final String title;
  final String subtitle;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.sm),
      child: PressableScale(
        onTap: () {
          Haptics.select();
          onTap();
        },
        child: Semantics(
          button: true,
          label: '$title. $subtitle.${trailing == null ? '' : ' $trailing.'}',
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: S.md,
                vertical: S.md,
              ),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: t.border),
              ),
              child: Row(
                children: [
                  IconTile(icon: icon, color: color, size: 36),
                  const GapX(S.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppType.bodySm,
                            fontWeight: W.semibold,
                            color: t.foreground,
                          ),
                        ),
                        Muted(subtitle, size: AppType.caption, maxLines: 1),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const GapX(S.sm),
                    Amount(trailing!, size: AppType.bodySm),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
