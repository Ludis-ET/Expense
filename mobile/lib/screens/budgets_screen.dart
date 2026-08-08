import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../models/extra.dart';
import '../models/finance.dart';
import '../state/data_store.dart';
import '../widgets/common.dart';
import '../widgets/web_chrome.dart';
import 'budget_detail_screen.dart';
import 'money_tab_screen.dart';

/// Budgets page: Plans + Wishlist tabs (website parity).
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  int _tab = 0; // 0 plans, 1 wishlist

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SantimColors>()!;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => context.read<DataStore>().refreshAll(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              floating: true,
              leading: IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
              ),
              title: const Text('Budgets'),
              actions: [
                IconButton(
                  tooltip: 'Money Tab',
                  onPressed: () => Navigator.of(context).push(santimRoute(const MoneyTabScreen())),
                  icon: Icon(Icons.handshake_outlined, color: colors.muted),
                ),
                const WebTopActions(),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tab == 0
                          ? 'Envelopes you fill from your accounts, then spend only from.'
                          : 'Things you want, with no money attached. Plan one when you are ready.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted),
                    ),
                    const SizedBox(height: 12),
                    SegmentedTabs(
                      labels: const ['Plans', 'Wishlist'],
                      index: _tab,
                      onChanged: (i) => setState(() => _tab = i),
                    ),
                  ],
                ),
              ),
            ),
            if (_tab == 0) const _PlansSliver() else const _WishlistSliver(),
          ],
        ),
      ),
    );
  }
}

class _PlansSliver extends StatelessWidget {
  const _PlansSliver();

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final plans = data.budgets.where((b) => b.state == 'ACTIVE' && !b.isUnplanned).toList();
    final unplanned = data.budgets.where((b) => b.isUnplanned).firstOrNull;

    if (data.loading && plans.isEmpty && unplanned == null) {
      return const SliverPadding(
        padding: EdgeInsets.all(16),
        sliver: SliverToBoxAdapter(child: ShimmerBlock(height: 140)),
      );
    }
    if (plans.isEmpty && unplanned == null) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.savings_outlined,
          title: 'No plans yet',
          message: 'Create a plan to set money aside, then spend only from it.',
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      sliver: SliverList.list(
        children: [
          for (final b in plans) ...[
            _BudgetCard(budget: b),
            const SizedBox(height: 12),
          ],
          if (unplanned != null) _UnplannedCard(budget: unplanned),
        ],
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.budget});
  final Budget budget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;
    final left = Money.parse(budget.potBalance);
    final drained = left <= 0;
    final accent = drained
        ? colors.danger
        : budget.progress >= 0.8
            ? colors.warning
            : colors.success;

    return SoftCard(
      onTap: () => Navigator.of(context).push(
        santimRoute(BudgetDetailScreen(budgetId: budget.id, seed: budget)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(budget.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Text(
                Money.format(budget.potBalance, currency: budget.currency),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: accent),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: budget.progress,
              minHeight: 8,
              backgroundColor: colors.surfaceMuted,
              color: accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${Money.format(budget.spentAmount, currency: budget.currency)} spent of '
            '${Money.format(budget.fundedAmount, currency: budget.currency)} funded',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
          ),
        ],
      ),
    );
  }
}

class _UnplannedCard extends StatelessWidget {
  const _UnplannedCard({required this.budget});
  final Budget budget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;
    return SoftCard(
      onTap: () => Navigator.of(context).push(
        santimRoute(BudgetDetailScreen(budgetId: budget.id, seed: budget)),
      ),
      child: Row(
        children: [
          Icon(Icons.all_inbox_outlined, color: colors.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(budget.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text('Catch-all for spending not set aside', style: theme.textTheme.bodySmall?.copyWith(color: colors.muted)),
              ],
            ),
          ),
          Text(
            Money.format(budget.spentAmount, currency: budget.currency),
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _WishlistSliver extends StatefulWidget {
  const _WishlistSliver();

  @override
  State<_WishlistSliver> createState() => _WishlistSliverState();
}

class _WishlistSliverState extends State<_WishlistSliver> {
  String _status = 'WANTING';
  List<WishlistItem> _items = const [];
  WishlistStats _stats = const WishlistStats();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await context.read<DataStore>().fetchWishlist(status: _status);
      final items = ((data['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(WishlistItem.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _items = items;
        _stats = WishlistStats.fromJson(data['stats'] as Map<String, dynamic>?);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SantimColors>()!;
    final tabs = <(String, String, int)>[
      ('WANTING', 'Wanting', _stats.wanting),
      ('PLANNED', 'Planned', _stats.planned),
      ('BOUGHT', 'Bought', _stats.bought),
      ('DROPPED', 'Dropped', _stats.dropped),
      ('all', 'All', _stats.total),
    ];

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      sliver: SliverList.list(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final t in tabs)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('${t.$2}${t.$3 > 0 ? ' (${t.$3})' : ''}'),
                      selected: _status == t.$1,
                      onSelected: (_) {
                        setState(() => _status = t.$1);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const ShimmerBlock(height: 120)
          else if (_items.isEmpty)
            const EmptyState(
              icon: Icons.auto_awesome,
              title: 'No wishes here',
              message: 'Add wants on the website, or switch status tabs.',
            )
          else
            for (final w in _items) ...[
              SoftCard(
                child: Row(
                  children: [
                    Text(w.emoji ?? '✨', style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(w.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            [
                              'Priority ${w.priority}',
                              w.status.toLowerCase(),
                              if (w.planName != null) 'Plan: ${w.planName}',
                            ].join(' · '),
                            style: TextStyle(fontSize: 12, color: colors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}
