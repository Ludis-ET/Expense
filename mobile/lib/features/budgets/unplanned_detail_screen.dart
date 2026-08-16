import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../widgets/ui.dart';
import '../transactions/transaction_detail.dart';
import '../transactions/transaction_form.dart';
import '../transactions/transaction_list.dart';

/// Virtual detail for Unplanned spending — not a pot, just this month's
/// catch-all expenses and a way to log another.
class UnplannedDetailScreen extends StatefulWidget {
  const UnplannedDetailScreen({super.key, required this.summary});

  final UnplannedSummary summary;

  @override
  State<UnplannedDetailScreen> createState() => _UnplannedDetailScreenState();
}

class _UnplannedDetailScreenState extends State<UnplannedDetailScreen> {
  final List<Transaction> _items = [];
  bool _loading = true;
  Object? _error;
  int _seenEpoch = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final currency = context.read<DataState>().activeCurrency;
      final json = await context.read<ApiClient>().get<Map<String, dynamic>>(
        '/transactions',
        query: {
          'budgetId': UnplannedSummary.id,
          'kind': 'EXPENSE',
          'currency': currency,
          'pageSize': 50,
          'sort': 'date_desc',
        },
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(TransactionPage.fromJson(json).items);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _addSpend() async {
    final done = await showTransactionForm(
      context,
      presetKind: 'EXPENSE',
      presetBudgetId: UnplannedSummary.id,
    );
    if (done == true && mounted) {
      await context.read<DataState>().refreshAfterWrite();
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final prefs = context.watch<PrefsState>();
    final data = context.watch<DataState>();
    final summary = widget.summary;
    final tone = parseHexColor(summary.color) ?? t.mutedForeground;

    final epoch = data.writeEpoch;
    if (_seenEpoch >= 0 && epoch != _seenEpoch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
    _seenEpoch = epoch;

    String money(Object? v) => prefs.money(v, currency: summary.currency);

    return Scaffold(
      backgroundColor: t.background,
      body: RefreshIndicator(
        onRefresh: _reload,
        color: t.primary,
        backgroundColor: t.surface,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: t.background,
              foregroundColor: t.foreground,
              title: Text(
                summary.name,
                style: TextStyle(
                  fontSize: AppType.lead,
                  fontWeight: FontWeight.w800,
                  color: t.foreground,
                ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: _addSpend,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add spend'),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  AppCard(
                    padding: const EdgeInsets.all(S.lg),
                    child: Row(
                      children: [
                        IconTile(
                          icon: Icons.more_horiz_rounded,
                          color: tone,
                        ),
                        const GapX(S.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'No money set aside',
                                style: TextStyle(
                                  fontSize: AppType.body,
                                  fontWeight: FontWeight.w700,
                                  color: t.foreground,
                                ),
                              ),
                              Text(
                                'Spends with no plan behind them. Cash leaves '
                                'whatever wallet you pick.',
                                style: TextStyle(
                                  fontSize: AppType.caption,
                                  color: t.mutedForeground,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(S.lg),
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          label: 'This month',
                          value: money(summary.spentAmount),
                        ),
                      ),
                      const GapX(S.sm),
                      Expanded(
                        child: _StatTile(
                          label: 'Lifetime',
                          value: money(summary.lifetimeSpent),
                        ),
                      ),
                      const GapX(S.sm),
                      Expanded(
                        child: _StatTile(
                          label: 'Entries',
                          value: '${summary.txCount}',
                        ),
                      ),
                    ],
                  ),
                  const Gap(S.xl),
                  SectionLabel('RECENT UNPLANNED'),
                  if (_loading && _items.isEmpty)
                    const Column(
                      children: [
                        Skeleton(height: 54, radius: R.md),
                        Gap(S.sm),
                        Skeleton(height: 54, radius: R.md),
                        Gap(S.sm),
                        Skeleton(height: 54, radius: R.md),
                      ],
                    )
                  else if (_error != null && _items.isEmpty)
                    EmptyState(
                      title: 'Could not load spends',
                      description: _error is ApiError
                          ? (_error as ApiError).message
                          : 'Something went wrong.',
                      action: AppButton(
                        label: 'Retry',
                        onPressed: _reload,
                      ),
                    )
                  else if (_items.isEmpty)
                    const EmptyState(
                      title: 'Nothing unplanned this month',
                      description:
                          'When you spend without a plan, those entries land here.',
                      compact: true,
                    )
                  else
                    AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: S.sm,
                        vertical: S.xxs,
                      ),
                      child: TransactionList(
                        items: _items,
                        money: (v, c) => prefs.money(v, currency: c),
                        onTap: (tx) async {
                          final data = context.read<DataState>();
                          final changed =
                              await showTransactionDetail(context, tx);
                          if (changed == true && mounted) {
                            await data.refreshAfterWrite();
                            if (mounted) await _reload();
                          }
                        },
                      ),
                    ),
                  const Gap(S.xxl),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AppCard(
      padding: const EdgeInsets.all(S.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: AppType.micro,
              fontWeight: FontWeight.w600,
              color: t.mutedForeground,
            ),
          ),
          const Gap(S.xs),
          Text(
            value,
            style: TextStyle(
              fontSize: AppType.lead,
              fontWeight: FontWeight.w800,
              color: t.foreground,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
