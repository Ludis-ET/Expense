import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/layout.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../state/sync_state.dart';
import '../../data/outbox_store.dart';
import '../../widgets/ui.dart';
import '../transactions/transaction_detail.dart';
import '../transactions/transaction_form.dart';
import 'budget_common.dart';
import 'budget_cycles.dart';
import 'budget_form.dart';
import 'budget_transactions.dart';
import 'move_sheet.dart';

/// One plan in full   parity with the web budget detail page: hero, banners,
/// stats, holdings, cycle cards / transaction list, movements timeline.
class BudgetDetailScreen extends StatefulWidget {
  const BudgetDetailScreen({super.key, required this.budgetId});
  final String budgetId;

  @override
  State<BudgetDetailScreen> createState() => _BudgetDetailScreenState();
}

class _BudgetDetailScreenState extends State<BudgetDetailScreen> {
  BudgetDetail? _detail;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final json = await context.read<ApiClient>().get<Map<String, dynamic>>(
        '/budgets/${widget.budgetId}',
      );
      if (!mounted) return;
      setState(() {
        _detail = BudgetDetail.fromJson(json);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _afterWrite() async {
    await _load();
    if (mounted) await context.read<DataState>().refreshAfterWrite();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final prefs = context.watch<PrefsState>();
    final detail = _detail;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          detail?.row.name ?? 'Plan',
          style: TextStyle(
            fontSize: AppType.lead,
            fontWeight: FontWeight.w700,
            color: t.foreground,
          ),
        ),
        actions: [
          if (detail != null && !detail.row.isUnplanned)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: t.foreground),
              color: t.surfaceElevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(R.md),
              ),
              onSelected: (v) => _menuAction(v, detail),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit plan')),
                const PopupMenuItem(
                  value: 'adjust',
                  child: Text('Add / Deduct'),
                ),
                PopupMenuItem(
                  value: detail.row.isClosed ? 'reopen' : 'close',
                  child: Text(
                    detail.row.isClosed ? 'Reopen plan' : 'Close plan',
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete plan'),
                ),
              ],
            ),
          const GapX(S.xxs),
        ],
      ),
      body: MeshBackground(
        showGrid: false,
        child: _loading && detail == null
            ? const Padding(
                padding: EdgeInsets.all(S.lg),
                child: PageLoader(rows: 4),
              )
            : _error != null && detail == null
            ? Padding(
                padding: const EdgeInsets.all(S.lg),
                child: ErrorState(
                  message: _error is ApiError
                      ? (_error as ApiError).message
                      : 'Could not load this plan.',
                  onRetry: _load,
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                color: t.primary,
                backgroundColor: t.surface,
                child: _body(context, detail!, prefs),
              ),
      ),
    );
  }

  Widget _body(BuildContext context, BudgetDetail detail, PrefsState prefs) {
    final t = context.t;
    final b = detail.row;
    final tint = parseHexColor(b.color) ?? healthColor(context, b.health);
    String money(Object? v) => prefs.money(v, currency: b.currency);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        14,
        4,
        14,
        ShellLayout.bottomClearance(context),
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        FadeInUp(
          child: _Hero(
            detail: detail,
            tint: tint,
            money: money,
            onAction: _heroAction,
          ),
        ),

        if (b.isClosed) ...[
          const Gap(S.md),
          FadeInUp(
            delay: const Duration(milliseconds: 40),
            child: _Banner(
              icon: Icons.archive_outlined,
              color: t.mutedForeground,
              text:
                  'This plan is closed   it no longer appears when you add a '
                  'transaction. Its history is kept below, and you can reopen it any time.',
            ),
          ),
        ],

        if (!b.isUnplanned && !b.started) ...[
          const Gap(S.md),
          FadeInUp(
            delay: const Duration(milliseconds: 40),
            child: _Banner(
              icon: Icons.schedule_rounded,
              color: const Color(0xFF6366F1),
              text:
                  'This plan starts on ${formatDate(b.startsAt)}. You can fill it now, '
                  'but nothing can be spent from it until then.',
            ),
          ),
        ],

        const Gap(S.md),
        FadeInUp(
          delay: const Duration(milliseconds: 60),
          child: b.isUnplanned
              ? _UnplannedStats(detail: detail, money: money)
              : _FundedStats(b: b, detail: detail, money: money),
        ),

        if (!b.isUnplanned && detail.sources.isNotEmpty) ...[
          const Gap(S.md),
          FadeInUp(
            delay: const Duration(milliseconds: 90),
            child: _HoldingsCard(detail: detail, money: money),
          ),
        ],

        const Gap(S.md),
        FadeInUp(
          delay: const Duration(milliseconds: 120),
          child: b.kind == BudgetKind.recurring && !b.isUnplanned
              ? BudgetCycleSections(
                  plan: detail,
                  money: money,
                  onChanged: _afterWrite,
                )
              : BudgetTransactionsPanel(plan: detail, onChanged: _afterWrite),
        ),

        if (!b.isUnplanned) ...[
          const Gap(S.md),
          FadeInUp(
            delay: const Duration(milliseconds: 150),
            child: _MovementsCard(
              detail: detail,
              money: money,
              onSpendTap: (tx) async {
                final changed = await showTransactionDetail(context, tx);
                if (changed == true) await _afterWrite();
              },
            ),
          ),
        ],

        if (b.isUnplanned) ...[
          const Gap(S.md),
          FadeInUp(
            delay: const Duration(milliseconds: 150),
            child: _LifetimeCard(detail: detail, money: money),
          ),
        ],
      ],
    );
  }

  Future<void> _heroAction(String action, BudgetDetail detail) async {
    final b = detail.row;
    switch (action) {
      case 'fund':
        final done = await showFundSheet(
          context,
          detail: detail,
          release: false,
        );
        if (done == true) await _afterWrite();
      case 'release':
        final done = await showFundSheet(
          context,
          detail: detail,
          release: true,
        );
        if (done == true) await _afterWrite();
      case 'spend':
        final done = await showTransactionForm(
          context,
          presetKind: 'EXPENSE',
          presetBudgetId: b.id,
        );
        if (done == true) await _afterWrite();
      case 'move':
        final done = await showMoveSheet(context, detail: detail);
        if (done == true) await _afterWrite();
      case 'adjust':
        final done = await showAdjustSheet(context, budget: b);
        if (done == true) await _afterWrite();
      case 'edit':
        final saved = await showBudgetForm(context, existing: b);
        if (saved == true) await _afterWrite();
      case 'reopen':
        try {
          final result = await context.read<SyncState>().budgetAction(
            budgetId: b.id,
            action: OutboxAction.reopen,
            label: 'Reopen plan',
            detail: b.name,
          );
          if (result.queued && mounted) {
            toast(
              context,
              'Queued offline   will sync when you are back online',
            );
          }
          await _afterWrite();
        } on ApiError catch (e) {
          if (mounted) toast(context, e.message, error: true);
        }
    }
  }

  Future<void> _menuAction(String action, BudgetDetail detail) async {
    final sync = context.read<SyncState>();
    final b = detail.row;

    switch (action) {
      case 'edit':
        final saved = await showBudgetForm(context, existing: b);
        if (saved == true) await _afterWrite();
      case 'adjust':
        final done = await showAdjustSheet(context, budget: b);
        if (done == true) await _afterWrite();
      case 'close':
        if (!mounted) return;
        final ok = await confirm(
          context,
          title: 'Close ${b.name}?',
          message:
              'Anything still in the pot goes back to the wallets that '
              'funded it. The plan stops running but stays on record.',
          confirmLabel: 'Close plan',
          danger: false,
        );
        if (!ok) return;
        try {
          final result = await sync.budgetAction(
            budgetId: b.id,
            action: OutboxAction.close,
            label: 'Close plan',
            detail: b.name,
          );
          if (result.queued && mounted) {
            toast(
              context,
              'Queued offline   will sync when you are back online',
            );
          }
          await _afterWrite();
        } on ApiError catch (e) {
          if (mounted) toast(context, e.message, error: true);
        }
      case 'reopen':
        try {
          final result = await sync.budgetAction(
            budgetId: b.id,
            action: OutboxAction.reopen,
            label: 'Reopen plan',
            detail: b.name,
          );
          if (result.queued && mounted) {
            toast(
              context,
              'Queued offline   will sync when you are back online',
            );
          }
          await _afterWrite();
        } on ApiError catch (e) {
          if (mounted) toast(context, e.message, error: true);
        }
      case 'delete':
        if (!mounted) return;
        final ok = await confirm(
          context,
          title: 'Delete ${b.name}?',
          message:
              'Expenses already recorded against it stay as ordinary expenses. '
              'Reserved money is released back to your wallets.',
        );
        if (!ok) return;
        try {
          final result = await sync.budgetAction(
            budgetId: b.id,
            action: OutboxAction.delete,
            label: 'Delete plan',
            detail: b.name,
          );
          if (mounted) await context.read<DataState>().refreshAfterWrite();
          if (mounted) {
            if (result.queued) {
              toast(
                context,
                'Delete queued   will sync when you are back online',
              );
            }
            Navigator.pop(context);
          }
        } on ApiError catch (e) {
          if (mounted) toast(context, e.message, error: true);
        }
    }
  }
}

// ─── Hero ────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({
    required this.detail,
    required this.tint,
    required this.money,
    required this.onAction,
  });

  final BudgetDetail detail;
  final Color tint;
  final String Function(Object?) money;
  final Future<void> Function(String, BudgetDetail) onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final b = detail.row;
    final planned = toNum(b.plannedAmount) <= 0 ? 0.01 : toNum(b.plannedAmount);
    final fundedPct = (toNum(b.fundedAmount) / planned * 100).clamp(0.0, 100.0);
    final spentPct = (toNum(b.spentAmount) / planned * 100).clamp(0.0, 100.0);
    final adjusted = toNum(b.adjustedThisCycle);

    if (b.isUnplanned) {
      return GlassCard(
        padding: const EdgeInsets.all(S.xl),
        radius: R.xl,
        opacity: 0.08,
        borderColor: t.border,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconTile(
                  icon: Icons.more_horiz_rounded,
                  color: t.mutedForeground,
                  size: 48,
                ),
                const GapX(S.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.name,
                        style: TextStyle(
                          fontSize: AppType.heading,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: t.foreground,
                        ),
                      ),
                      const Gap(S.xs),
                      AppBadge(
                        'Catch-all',
                        tone: BadgeTone.neutral,
                        dense: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Gap(S.lg),
            Center(
              child: Column(
                children: [
                  AnimatedNumber(
                    value: toNum(b.spentAmount),
                    builder: (context, v) =>
                        Amount(money(v), size: 34, color: t.foreground),
                  ),
                  const Gap(S.xxs),
                  Muted('spent unplanned', size: 12),
                ],
              ),
            ),
            const Gap(S.md),
            Text(
              healthSentence(b, money),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppType.label,
                height: 1.45,
                color: t.mutedForeground,
              ),
            ),
          ],
        ),
      );
    }

    return GlassCard(
      padding: const EdgeInsets.all(S.xl),
      radius: R.xl,
      tint: tint,
      opacity: 0.12,
      borderColor: tint.withValues(alpha: 0.28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(R.lg),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      tint.withValues(alpha: 0.4),
                      tint.withValues(alpha: 0.12),
                    ],
                  ),
                  border: Border.all(color: tint.withValues(alpha: 0.4)),
                  boxShadow: [
                    BoxShadow(
                      color: tint.withValues(alpha: 0.25),
                      blurRadius: 16,
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: Icon(
                  financeIcon(b.icon ?? b.category?.icon),
                  color: tint,
                  size: 26,
                ),
              ),
              const GapX(S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.name,
                      style: TextStyle(
                        fontSize: AppType.heading,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: t.foreground,
                      ),
                    ),
                    const Gap(S.xs),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        AppBadge(
                          b.health.label,
                          tone: healthTone(b.health),
                          dense: true,
                        ),
                        if (b.kind == BudgetKind.recurring)
                          AppBadge(
                            'resets ${b.recurrenceLabel ?? 'periodically'}',
                            tone: BadgeTone.info,
                            dense: true,
                          )
                        else
                          AppBadge(
                            'One-time',
                            tone: BadgeTone.neutral,
                            dense: true,
                          ),
                        if (b.category != null)
                          AppBadge(
                            b.category!.name,
                            tone: BadgeTone.neutral,
                            dense: true,
                          ),
                        if (b.cycleLabel != null)
                          AppBadge(
                            b.cycleLabel!,
                            tone: BadgeTone.info,
                            dense: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (b.note != null && b.note!.isNotEmpty) ...[
            const Gap(S.md),
            Text(
              b.note!,
              style: TextStyle(
                fontSize: AppType.bodySm,
                height: 1.45,
                color: t.mutedForeground,
              ),
            ),
          ],
          const Gap(S.xl),
          Center(
            child: Column(
              children: [
                Muted('LEFT IN THIS PLAN', size: 10.5),
                const Gap(S.xxs),
                AnimatedNumber(
                  value: toNum(b.balance),
                  builder: (context, v) =>
                      Amount(money(v), size: 36, color: tint),
                ),
              ],
            ),
          ),
          const Gap(S.lg),
          Stack(
            children: [
              ProgressBar(
                value: fundedPct,
                height: 10,
                gradient: [
                  tint.withValues(alpha: 0.35),
                  tint.withValues(alpha: 0.22),
                ],
              ),
              ProgressBar(
                value: spentPct,
                height: 10,
                tone: healthTone(b.health),
              ),
            ],
          ),
          const Gap(S.sm),
          Text(
            'Planned ${money(b.plannedAmount)} · filled ${money(b.fundedAmount)} · '
            'spent ${money(b.spentAmount)} · still fits ${money(b.fillable)}',
            style: TextStyle(
              fontSize: AppType.caption,
              height: 1.45,
              color: t.mutedForeground,
            ),
          ),
          if (adjusted != 0) ...[
            const Gap(S.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: AdjustmentChip(amount: b.adjustedThisCycle, money: money),
            ),
          ],
          const Gap(S.sm),
          Text(
            healthSentence(b, money),
            style: TextStyle(
              fontSize: AppType.label,
              height: 1.45,
              color: t.mutedForeground,
            ),
          ),
          if (!b.isClosed) ...[
            const Gap(S.lg),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HeroAction(
                  label: 'Put money in',
                  icon: Icons.add_rounded,
                  filled: true,
                  tint: tint,
                  onTap: () => onAction('fund', detail),
                ),
                if (toNum(b.balance) > 0)
                  _HeroAction(
                    label: 'Give back',
                    icon: Icons.undo_rounded,
                    onTap: () => onAction('release', detail),
                  ),
                if (toNum(b.balance) > 0 && b.started)
                  _HeroAction(
                    label: 'Spend',
                    icon: Icons.shopping_bag_outlined,
                    onTap: () => onAction('spend', detail),
                  ),
                // Moving beats give-back-then-refill: one movement in the
                // history, and the money is never briefly spendable.
                if (toNum(b.balance) > 0)
                  _HeroAction(
                    label: 'Move',
                    icon: Icons.swap_horiz_rounded,
                    onTap: () => onAction('move', detail),
                  ),
                _HeroAction(
                  label: 'Add / Deduct',
                  icon: Icons.tune_rounded,
                  onTap: () => onAction('adjust', detail),
                ),
                _HeroAction(
                  label: 'Edit',
                  icon: Icons.edit_outlined,
                  onTap: () => onAction('edit', detail),
                ),
              ],
            ),
          ] else ...[
            const Gap(S.md),
            AppButton(
              label: 'Reopen plan',
              icon: Icons.unarchive_outlined,
              expand: true,
              size: BtnSize.sm,
              variant: BtnVariant.outline,
              onPressed: () => onAction('reopen', detail),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.tint,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = tint ?? t.primary;
    return Material(
      color: filled ? color : t.surface.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(R.pill),
      child: InkWell(
        onTap: () {
          Haptics.select();
          onTap();
        },
        borderRadius: BorderRadius.circular(R.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.pill),
            border: filled ? null : Border.all(color: t.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: filled ? t.primaryForeground : t.foreground,
              ),
              const GapX(S.xs),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppType.label,
                  fontWeight: FontWeight.w700,
                  color: filled ? t.primaryForeground : t.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Banners & stats ─────────────────────────────────────────────────────────

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(S.lg),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const GapX(S.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppType.bodySm,
                height: 1.45,
                color: t.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FundedStats extends StatelessWidget {
  const _FundedStats({
    required this.b,
    required this.detail,
    required this.money,
  });

  final BudgetRow b;
  final BudgetDetail detail;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(label: 'Planned', value: money(b.plannedAmount)),
        ),
        const GapX(S.sm),
        Expanded(
          child: _StatTile(
            label: 'Filled',
            value: money(b.fundedAmount),
            sub: toNum(b.carriedIn) > 0
                ? 'incl. ${money(b.carriedIn)} carried'
                : null,
          ),
        ),
        const GapX(S.sm),
        Expanded(
          child: _StatTile(
            label: 'Spent',
            value: money(b.spentAmount),
            sub: '${b.pctSpentOfFunded.round()}% of funded',
          ),
        ),
        const GapX(S.sm),
        Expanded(
          child: _StatTile(
            label: 'Lifetime',
            value: money(detail.lifetimeSpent),
            sub:
                '${detail.lifetimeCycleCount} cycle${detail.lifetimeCycleCount == 1 ? '' : 's'}',
          ),
        ),
      ],
    );
  }
}

class _UnplannedStats extends StatelessWidget {
  const _UnplannedStats({required this.detail, required this.money});

  final BudgetDetail detail;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    final b = detail.row;
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Spent unplanned',
            value: money(b.spentAmount),
          ),
        ),
        const GapX(S.sm),
        Expanded(
          child: _StatTile(
            label: 'All time',
            value: money(detail.lifetimeSpent),
            sub: '${detail.lifetimeTxCount} tx',
          ),
        ),
        const GapX(S.sm),
        Expanded(
          child: _StatTile(
            label: 'Since',
            value: detail.firstTxAt != null
                ? formatDate(detail.firstTxAt)
                : ' ',
            sub: 'first expense',
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.sub});

  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.fromLTRB(S.md, S.md, S.md, S.md),
      decoration: BoxDecoration(
        color: t.surfaceElevated,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: t.border.withValues(alpha: 0.7)),
        boxShadow: t.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Muted(label, size: 10, maxLines: 1),
          const Gap(S.xxs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Amount(value, size: 13.5),
          ),
          if (sub != null) ...[
            const Gap(S.xxs),
            Muted(sub!, size: 9.5, maxLines: 2),
          ],
        ],
      ),
    );
  }
}

// ─── Holdings ────────────────────────────────────────────────────────────────

class _HoldingsCard extends StatelessWidget {
  const _HoldingsCard({required this.detail, required this.money});

  final BudgetDetail detail;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitleRow(
            title: 'Money held per account',
            icon: Icons.account_balance_wallet_outlined,
            hint:
                'This money is still physically in these accounts   it just '
                "doesn't count as available until you spend it here or give it back.",
          ),
          const Gap(S.md),
          for (var i = 0; i < detail.sources.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == detail.sources.length - 1 ? 0 : 8,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: S.md,
                  vertical: S.md,
                ),
                decoration: BoxDecoration(
                  color: t.surfaceMuted.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(R.lg),
                ),
                child: Row(
                  children: [
                    IconTile(
                      icon: accountTypeIcon(
                        detail.sources[i].account?.type ?? 'OTHER',
                      ),
                      color: parseHexColor(detail.sources[i].account?.color),
                      size: 34,
                    ),
                    const GapX(S.md),
                    Expanded(
                      child: Text(
                        detail.sources[i].account?.name ?? 'Unknown wallet',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.bodySm,
                          fontWeight: FontWeight.w600,
                          color: t.foreground,
                        ),
                      ),
                    ),
                    Amount(money(detail.sources[i].available), size: 14),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Movements ───────────────────────────────────────────────────────────────

class _MovementsCard extends StatelessWidget {
  const _MovementsCard({
    required this.detail,
    required this.money,
    required this.onSpendTap,
  });

  final BudgetDetail detail;
  final String Function(Object?) money;
  final Future<void> Function(Transaction tx) onSpendTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitleRow(
            title: 'Recent movements',
            icon: Icons.timeline_rounded,
            trailing: detail.timelineTruncated
                ? Muted('latest ${detail.timeline.length}', size: 11)
                : null,
          ),
          const Gap(S.md),
          if (detail.timeline.isEmpty)
            const EmptyState(
              title: 'Nothing yet',
              description:
                  'Put money in from an account to get this plan going.',
              compact: true,
            )
          else
            for (var i = 0; i < detail.timeline.length; i++)
              _TimelineNode(
                entry: detail.timeline[i],
                money: money,
                currentCycle: detail.row.cycleIndex,
                isLast: i == detail.timeline.length - 1,
                onSpendTap: onSpendTap,
              ),
        ],
      ),
    );
  }
}

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({
    required this.entry,
    required this.money,
    required this.currentCycle,
    required this.isLast,
    required this.onSpendTap,
  });

  final BudgetTimelineEntry entry;
  final String Function(Object?) money;
  final int currentCycle;
  final bool isLast;
  final Future<void> Function(Transaction tx) onSpendTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final (icon, color, title, subtitle) = switch (entry.type) {
      'fund' => (
        Icons.south_west_rounded,
        t.success,
        'Filled from ${entry.allocation?.account?.name ?? 'a wallet'}',
        entry.allocation?.note,
      ),
      'release' => (
        Icons.north_east_rounded,
        t.warning,
        'Given back to ${entry.allocation?.account?.name ?? 'a wallet'}',
        entry.allocation?.note,
      ),
      'spend' => (
        Icons.shopping_bag_outlined,
        t.danger,
        entry.transaction?.payee ??
            entry.transaction?.note ??
            entry.transaction?.category?.name ??
            'Spent',
        entry.transaction?.category?.name ?? entry.transaction?.account?.name,
      ),
      _ => (
        toNum(entry.adjustment?.amount) >= 0
            ? Icons.trending_up
            : Icons.trending_down,
        toNum(entry.adjustment?.amount) >= 0 ? t.success : t.warning,
        toNum(entry.adjustment?.amount) >= 0 ? 'Plan raised' : 'Plan cut',
        entry.adjustment?.reason,
      ),
    };

    final amount = toNum(entry.amount);
    final sign = switch (entry.type) {
      'fund' => '+',
      'release' || 'spend' => '−',
      _ => amount >= 0 ? '+' : '−',
    };
    final earlier = entry.cycleIndex != currentCycle;

    final row = Padding(
      padding: const EdgeInsets.only(bottom: S.hair),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.14),
                    border: Border.all(color: color.withValues(alpha: 0.45)),
                  ),
                  child: Icon(icon, size: 14, color: color),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 36,
                    margin: const EdgeInsets.symmetric(vertical: S.xxs),
                    decoration: BoxDecoration(
                      color: t.border,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
              ],
            ),
          ),
          const GapX(S.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: S.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppType.bodySm,
                            fontWeight: FontWeight.w600,
                            color: t.foreground,
                          ),
                        ),
                      ),
                      Amount(
                        '$sign${money(amount.abs())}',
                        size: 13.5,
                        color: entry.type == 'fund'
                            ? t.success
                            : entry.type == 'spend'
                            ? t.danger
                            : color,
                      ),
                    ],
                  ),
                  const Gap(S.xxs),
                  Muted(
                    [
                      formatDayMonth(entry.at),
                      if (subtitle != null && subtitle.isNotEmpty) subtitle,
                      if (earlier) 'earlier cycle',
                    ].join(' · '),
                    size: 11,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (entry.type == 'spend' && entry.transaction != null) {
      return InkWell(
        onTap: () {
          final bt = entry.transaction!;
          final tx = Transaction(
            id: bt.id,
            kind: TxKind.expense,
            amount: bt.amount,
            currency: bt.currency,
            date: bt.date,
            accountId: bt.account?.id ?? '',
            account: bt.account,
            category: bt.category,
            categoryId: bt.category?.id,
            budgetId: null,
            payee: bt.payee,
            note: bt.note,
            tags: bt.tags,
            budgetCycle: bt.budgetCycle,
          );
          onSpendTap(tx);
        },
        borderRadius: BorderRadius.circular(R.md),
        child: row,
      );
    }
    return row;
  }
}

// ─── Lifetime (unplanned fallback) ───────────────────────────────────────────

class _LifetimeCard extends StatelessWidget {
  const _LifetimeCard({required this.detail, required this.money});

  final BudgetDetail detail;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitleRow(title: 'Lifetime', icon: Icons.all_inclusive),
          const Gap(S.md),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Filled',
                  value: money(detail.lifetimeAllocated),
                ),
              ),
              const GapX(S.sm),
              Expanded(
                child: _StatTile(
                  label: 'Spent',
                  value: money(detail.lifetimeSpent),
                ),
              ),
            ],
          ),
          const Gap(S.sm),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Transactions',
                  value: '${detail.lifetimeTxCount}',
                ),
              ),
              const GapX(S.sm),
              Expanded(
                child: _StatTile(
                  label: 'Cycles',
                  value: '${detail.lifetimeCycleCount}',
                ),
              ),
            ],
          ),
          if (detail.firstTxAt != null) ...[
            const Gap(S.sm),
            Muted('First spend ${formatDate(detail.firstTxAt)}', size: 11.5),
          ],
        ],
      ),
    );
  }
}
