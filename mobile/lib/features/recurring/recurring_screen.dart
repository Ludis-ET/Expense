import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/layout.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../core/utils/monthly_outlook.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../widgets/ui.dart';
import '../outlook/monthly_outlook_screen.dart';
import 'recurring_form.dart';

export 'recurring_form.dart' show showRecurringForm, RecurringPrefill;

/// Recurring plans   rent, salary, subscriptions. Auto-posting rules write
/// themselves into your ledger when they come due; the rest wait for a tap.
class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final data = context.watch<DataState>();
    final prefs = context.watch<PrefsState>();

    final rules = (data.recurring.data ?? const <RecurringRule>[])
        .where((r) => r.currency == data.activeCurrency)
        .toList();
    final active = rules.where((r) => r.active).toList()
      ..sort((a, b) => a.nextRun.compareTo(b.nextRun));
    final paused = rules.where((r) => !r.active).toList();

    final monthlyOut = active
        .where((r) => r.kind == TxKind.expense)
        .fold<double>(
          0,
          (s, r) =>
              s +
              monthlyEquivalentAmount(toNum(r.amount), r.frequency, r.interval),
        );
    final monthlyIn = active
        .where((r) => r.kind == TxKind.income)
        .fold<double>(
          0,
          (s, r) =>
              s +
              monthlyEquivalentAmount(toNum(r.amount), r.frequency, r.interval),
        );

    String money(Object? v) => prefs.money(v, currency: data.activeCurrency);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Recurring',
          style: TextStyle(
            fontSize: AppType.lead,
            fontWeight: FontWeight.w700,
            color: t.foreground,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: S.sm),
            child: Center(
              child: HeaderAction(
                icon: Icons.add_rounded,
                label: 'New rule',
                onTap: () async {
                  final saved = await showRecurringForm(context);
                  if (saved == true && context.mounted) {
                    await context.read<DataState>().loadRecurring(force: true);
                  }
                },
              ),
            ),
          ),
        ],
      ),
      body: MeshBackground(
        showGrid: false,
        child: RefreshIndicator(
          onRefresh: () => data.loadRecurring(force: true),
          color: t.primary,
          backgroundColor: t.surface,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              14,
              4,
              14,
              ShellLayout.bottomClearance(context),
            ),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (!data.recurring.hasData) ...[
                if (data.recurring.hasError)
                  ErrorState(
                    message: data.recurring.errorMessage,
                    onRetry: () => data.loadRecurring(force: true),
                  )
                else
                  const PageLoader(rows: 4),
              ] else ...[
                FadeInUp(
                  child: Row(
                    children: [
                      Expanded(
                        child: _Stat(
                          label: 'Committed out',
                          value: money(monthlyOut),
                          hint: 'per month',
                          color: t.danger,
                          icon: Icons.north_east_rounded,
                        ),
                      ),
                      const GapX(S.sm),
                      Expanded(
                        child: _Stat(
                          label: 'Expected in',
                          value: money(monthlyIn),
                          hint: 'per month',
                          color: t.success,
                          icon: Icons.south_west_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(S.sm),
                AppButton(
                  label: 'Open monthly outlook',
                  icon: Icons.insights_rounded,
                  expand: true,
                  variant: BtnVariant.outline,
                  size: BtnSize.sm,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MonthlyOutlookScreen(),
                    ),
                  ),
                ),
                const Gap(S.lg),

                if (active.isEmpty && paused.isEmpty)
                  EmptyState(
                    icon: Icons.repeat,
                    art: EmptyArt.calendar,
                    title: 'No recurring plans yet',
                    description:
                        'Set up rent, salary or a subscription once and '
                        'let it post itself.',
                    action: AppButton(
                      label: 'Add a rule',
                      icon: Icons.add,
                      size: BtnSize.sm,
                      onPressed: () async {
                        final saved = await showRecurringForm(context);
                        if (saved == true && context.mounted) {
                          await context.read<DataState>().loadRecurring(
                            force: true,
                          );
                        }
                      },
                    ),
                  ),

                if (active.isNotEmpty) ...[
                  SectionLabel('ACTIVE'),
                  for (var i = 0; i < active.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: S.md),
                      child: FadeInUp.staggered(
                        index: i,
                        child: _RuleCard(rule: active[i], money: money),
                      ),
                    ),
                ],

                if (paused.isNotEmpty) ...[
                  const Gap(S.sm),
                  SectionLabel('PAUSED'),
                  for (final r in paused)
                    Padding(
                      padding: const EdgeInsets.only(bottom: S.md),
                      child: Opacity(
                        opacity: 0.6,
                        child: _RuleCard(rule: r, money: money),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.hint,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final String hint;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const GapX(S.xs),
              Expanded(child: Muted(label, size: 11.5, maxLines: 1)),
            ],
          ),
          const Gap(S.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Amount(value, size: 19, color: color),
          ),
          const Gap(S.hair),
          Muted(hint, size: 10.5),
        ],
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.rule, required this.money});

  final RecurringRule rule;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final r = rule;
    final isIncome = r.kind == TxKind.income;
    final tint =
        parseHexColor(r.category?.color) ??
        (isIncome ? t.success : t.mutedForeground);
    final due = r.nextRun.difference(DateTime.now()).inDays;

    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      onTap: () => _menu(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(
                icon: financeIcon(r.category?.icon),
                color: tint,
                size: 42,
              ),
              const GapX(S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.body,
                        fontWeight: FontWeight.w700,
                        color: t.foreground,
                      ),
                    ),
                    const Gap(S.xxs),
                    Row(
                      children: [
                        AppBadge(
                          r.cadence,
                          tone: BadgeTone.neutral,
                          dense: true,
                        ),
                        const GapX(S.xs),
                        if (r.autoPost)
                          AppBadge(
                            'Auto',
                            tone: BadgeTone.primary,
                            dense: true,
                            icon: Icons.bolt,
                          )
                        else
                          AppBadge(
                            'Manual',
                            tone: BadgeTone.warning,
                            dense: true,
                          ),
                        if (!isIncome) ...[
                          const GapX(S.xs),
                          if (r.budget != null)
                            AppBadge(
                              r.budget!.name,
                              tone: BadgeTone.info,
                              dense: true,
                              icon: Icons.account_balance_wallet_outlined,
                            )
                          else
                            AppBadge(
                              'Needs a plan',
                              tone: BadgeTone.warning,
                              dense: true,
                            ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const GapX(S.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Amount(
                    '${isIncome ? '+' : '−'}${money(r.amount)}',
                    size: 15,
                    color: isIncome ? t.success : t.foreground,
                  ),
                  const Gap(S.hair),
                  Muted(r.account?.name ?? '', size: 10.5, maxLines: 1),
                ],
              ),
            ],
          ),
          const Gap(S.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: S.md,
              vertical: S.sm,
            ),
            decoration: BoxDecoration(
              color: due <= 2 && r.active
                  ? t.warning.withValues(alpha: 0.1)
                  : t.surfaceMuted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(R.sm + 2),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.event_outlined,
                  size: 14,
                  color: due <= 2 && r.active ? t.warning : t.mutedForeground,
                ),
                const GapX(S.sm),
                Expanded(
                  child: Text(
                    r.active
                        ? 'Next ${formatDate(r.nextRun)} · ${relativeTime(r.nextRun)}'
                        : 'Paused',
                    style: TextStyle(
                      fontSize: AppType.caption,
                      color: due <= 2 && r.active
                          ? t.warning
                          : t.mutedForeground,
                    ),
                  ),
                ),
                if (r.postedCount > 0)
                  Muted('${r.postedCount} posted', size: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _menu(BuildContext context) async {
    final api = context.read<ApiClient>();
    final data = context.read<DataState>();

    final action = await showAppSheet<String>(
      context,
      title: rule.name,
      subtitle: rule.cadence,
      scrollable: false,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: 16 + MediaQuery.of(ctx).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              onTap: () => Navigator.pop(ctx, 'run'),
              leading: const Icon(Icons.play_arrow_rounded, size: 21),
              title: const Text(
                'Post it now',
                style: TextStyle(fontSize: AppType.body),
              ),
              subtitle: const Text(
                'Writes the transaction and moves the next run forward.',
                style: TextStyle(fontSize: AppType.caption),
              ),
            ),
            ListTile(
              onTap: () => Navigator.pop(ctx, 'edit'),
              leading: const Icon(Icons.edit_outlined, size: 20),
              title: const Text(
                'Edit',
                style: TextStyle(fontSize: AppType.body),
              ),
            ),
            ListTile(
              onTap: () => Navigator.pop(ctx, 'toggle'),
              leading: Icon(
                rule.active
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
                size: 20,
              ),
              title: Text(
                rule.active ? 'Pause' : 'Resume',
                style: const TextStyle(fontSize: AppType.body),
              ),
            ),
            ListTile(
              onTap: () => Navigator.pop(ctx, 'delete'),
              leading: Icon(
                Icons.delete_outline,
                size: 20,
                color: ctx.t.danger,
              ),
              title: Text(
                'Delete',
                style: TextStyle(fontSize: AppType.body, color: ctx.t.danger),
              ),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    try {
      switch (action) {
        case 'run':
          await api.post('/recurring/${rule.id}/run-now');
          await data.loadRecurring(force: true);
          await data.refreshAfterWrite();
          if (context.mounted) toast(context, 'Posted');
        case 'edit':
          final saved = await showRecurringForm(context, existing: rule);
          if (saved == true) await data.loadRecurring(force: true);
        case 'toggle':
          await api.put(
            '/recurring/${rule.id}',
            body: {'active': !rule.active},
          );
          await data.loadRecurring(force: true);
        case 'delete':
          if (!context.mounted) return;
          final ok = await confirm(
            context,
            title: 'Delete ${rule.name}?',
            message: 'Transactions it already posted stay in your history.',
          );
          if (!ok) return;
          await api.delete('/recurring/${rule.id}');
          await data.loadRecurring(force: true);
      }
    } on ApiError catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }
}

// Form lives in recurring_form.dart (showRecurringForm / RecurringPrefill).
