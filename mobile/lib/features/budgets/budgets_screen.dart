import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/layout.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../widgets/sync_ui.dart';
import '../../widgets/ui.dart';
import '../shell/app_shell.dart';
import '../wishlist/wishlist_screen.dart';
import 'budget_common.dart';
import 'budget_detail_screen.dart';
import 'budget_form.dart';

/// Budgets & Wishes. A plan is an envelope: you fill it from a wallet, and the
/// money is reserved out of your available balance until you spend it.
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  bool _showClosed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DataState>().loadBudgets();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final data = context.watch<DataState>();
    final prefs = context.watch<PrefsState>();
    final shell = AppShell.of(context);
    final currency = data.activeCurrency;

    String money(Object? v) => prefs.money(v, currency: currency);

    final response = data.budgets.data;
    final all = (response?.items ?? const <BudgetRow>[])
        .where((b) => b.currency == currency)
        .toList();
    final active = all.where((b) => !b.isClosed).toList();
    final closed = all.where((b) => b.isClosed).toList();
    final totals = response?.totals;
    // Not one of `items` any more: spending with no plan behind it is a view
    // over transactions, not an envelope that could never be funded.
    final unplanned = response?.unplanned;

    return RefreshIndicator(
      onRefresh: () =>
          data.loadBudgets(force: true, includeClosed: _showClosed),
      color: t.primary,
      backgroundColor: t.surface,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          14,
          14,
          14,
          ShellLayout.bottomClearance(context),
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          PageHeader(
            title: 'Plans',
            description:
                'A plan is an envelope. Filling it moves money out of '
                'your available balance and reserves it, so what is left over '
                'is genuinely free to spend.',
            action: HeaderAction(
              icon: Icons.add_rounded,
              label: 'New plan',
              onTap: () => _create(context),
            ),
          ),

          const OfflineBanner(),

          if (response == null) ...[
            if (data.budgets.hasError)
              ErrorState(
                message: data.budgets.errorMessage,
                onRetry: () => data.loadBudgets(force: true),
              )
            else
              const PageLoader(rows: 4),
          ] else ...[
            if (totals != null)
              FadeInUp(
                child: _TotalsHero(totals: totals, money: money),
              ),
            const Gap(S.lg),

            AppCard(
              padding: const EdgeInsets.all(S.lg),
              onTap: () => shell.push(const WishlistScreen()),
              child: Row(
                children: [
                  IconTile(
                    icon: Icons.favorite_border,
                    color: t.accent,
                    size: 40,
                  ),
                  const GapX(S.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Wishlist',
                          style: TextStyle(
                            fontSize: AppType.body,
                            fontWeight: FontWeight.w700,
                            color: t.foreground,
                          ),
                        ),
                        const Gap(S.hair),
                        Muted('Things you want', size: 12, maxLines: 1),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 20, color: t.mutedForeground),
                ],
              ),
            ),
            const Gap(S.lg),

            if (active.isEmpty)
              EmptyState(
                icon: Icons.savings_outlined,
                art: EmptyArt.plan,
                title: 'No plans yet',
                description:
                    'Set money aside for what you intend to spend   '
                    'rent, groceries, a trip.',
                action: AppButton(
                  label: 'Create a plan',
                  icon: Icons.add,
                  size: BtnSize.sm,
                  onPressed: () => _create(context),
                ),
              )
            else ...[
              SectionLabel('ACTIVE PLANS'),
              for (var i = 0; i < active.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: S.md),
                  child: FadeInUp.staggered(
                    index: i,
                    child: BudgetCard(
                      budget: active[i],
                      money: money,
                      onTap: () => _open(context, active[i]),
                    ),
                  ),
                ),
            ],

            if (unplanned != null) ...[
              const Gap(S.xs),
              SectionLabel('CATCH-ALL'),
              _UnplannedCard(summary: unplanned, money: money),
            ],

            const Gap(S.lg),
            Center(
              child: AppButton(
                label: _showClosed
                    ? 'Hide closed plans'
                    : 'Show closed plans${totals != null && totals.closedCount > 0 ? ' (${totals.closedCount})' : ''}',
                variant: BtnVariant.ghost,
                size: BtnSize.sm,
                icon: _showClosed ? Icons.expand_less : Icons.expand_more,
                onPressed: () {
                  setState(() => _showClosed = !_showClosed);
                  if (_showClosed) {
                    data.loadBudgets(force: true, includeClosed: true);
                  }
                },
              ),
            ),
            if (_showClosed && closed.isNotEmpty) ...[
              const Gap(S.sm),
              for (final b in closed)
                Padding(
                  padding: const EdgeInsets.only(bottom: S.md),
                  child: Opacity(
                    opacity: 0.65,
                    child: BudgetCard(
                      budget: b,
                      money: money,
                      onTap: () => _open(context, b),
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, BudgetRow b) async {
    await AppShell.of(context).push(BudgetDetailScreen(budgetId: b.id));
    if (context.mounted) {
      await context.read<DataState>().loadBudgets(
        force: true,
        includeClosed: _showClosed,
      );
    }
  }

  Future<void> _create(BuildContext context) async {
    final created = await showBudgetForm(context);
    if (created == true && context.mounted) {
      await context.read<DataState>().refreshAfterWrite();
    }
  }
}

class _TotalsHero extends StatelessWidget {
  const _TotalsHero({required this.totals, required this.money});

  final BudgetTotals totals;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    final planned = toNum(totals.planned);
    final funded = toNum(totals.funded);
    final spent = toNum(totals.spent);
    final fundedPct = planned <= 0
        ? 0.0
        : (funded / planned * 100).clamp(0.0, 100.0);

    return GradientHero(
      padding: const EdgeInsets.all(S.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reserved across ${totals.activeCount} active plan'
            '${totals.activeCount == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: AppType.caption,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
          const Gap(S.xs),
          AnimatedNumber(
            value: toNum(totals.locked),
            builder: (context, v) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                money(v),
                style: const TextStyle(
                  fontSize: AppType.hero,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1.2,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const Gap(S.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(R.pill),
            child: LinearProgressIndicator(
              value: fundedPct / 100,
              minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const Gap(S.sm),
          Text(
            '${money(funded)} filled of ${money(planned)} planned',
            style: TextStyle(
              fontSize: AppType.caption,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const Gap(S.md),
          Row(
            children: [
              Expanded(
                child: _Fig(label: 'Spent from plans', value: money(spent)),
              ),
              const GapX(S.sm),
              Expanded(
                child: _Fig(
                  label: 'Unplanned spend',
                  value: money(totals.unplannedSpent),
                ),
              ),
            ],
          ),
          const Gap(S.sm),
          // Money you have that no plan has claimed. The number envelope
          // budgeting is actually built around, and the only figure here that
          // asks you to do something.
          _Fig(
            label: 'Ready to assign',
            value: money(totals.readyToAssign),
            emphasis: true,
          ),
        ],
      ),
    );
  }
}

/// The catch-all card.
///
/// Deliberately shaped unlike a plan, because it is not one: no pot, no
/// progress bar, nothing to fill. It reports what was spent without setting
/// money aside - a fact about the past, not a container for the future.
class _UnplannedCard extends StatelessWidget {
  const _UnplannedCard({required this.summary, required this.money});

  final UnplannedSummary summary;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final tone = parseHexColor(summary.color) ?? t.mutedForeground;

    return DashedCard(
      child: Row(
        children: [
          IconTile(icon: Icons.more_horiz_rounded, color: tone),
          const GapX(S.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.name,
                  style: TextStyle(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w700,
                    color: t.foreground,
                  ),
                ),
                Text(
                  'No money set aside · nothing to run out of',
                  style: TextStyle(
                    fontSize: AppType.caption,
                    color: t.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                money(summary.spentAmount),
                style: TextStyle(
                  fontSize: AppType.lead,
                  fontWeight: FontWeight.w700,
                  color: t.foreground,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                'this month',
                style: TextStyle(
                  fontSize: AppType.micro,
                  color: t.mutedForeground,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A card that reads as an outline rather than a container, so the catch-all
/// never looks like something you can put money into.
class DashedCard extends StatelessWidget {
  const DashedCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(S.lg),
      decoration: BoxDecoration(
        color: t.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: t.border),
      ),
      child: child,
    );
  }
}

class _Fig extends StatelessWidget {
  const _Fig({
    required this.label,
    required this.value,
    this.emphasis = false,
  });
  final String label;
  final String value;

  /// Full width and a larger figure, for the one number worth acting on.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return GlassChip(
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: AppType.micro,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const Gap(S.xxs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: emphasis ? AppType.figure : AppType.body,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `BudgetPlanCard`   the pot's shape at a glance: how much went in, how much
/// is gone, and one line of plain English about where it stands.
class BudgetCard extends StatelessWidget {
  const BudgetCard({
    super.key,
    required this.budget,
    required this.money,
    this.onTap,
  });

  final BudgetRow budget;
  final String Function(Object?) money;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final b = budget;
    final tint = parseHexColor(b.color) ?? healthColor(context, b.health);
    final planned = toNum(b.plannedAmount) <= 0 ? 0.01 : toNum(b.plannedAmount);
    final spentPct = (toNum(b.spentAmount) / planned * 100).clamp(0.0, 100.0);
    final fundedPct = (toNum(b.fundedAmount) / planned * 100).clamp(0.0, 100.0);

    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(
                icon: b.isUnplanned
                    ? Icons.more_horiz
                    : financeIcon(b.icon ?? b.category?.icon),
                color: tint,
                size: 42,
              ),
              const GapX(S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.name,
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
                          b.health.label,
                          tone: healthTone(b.health),
                          dense: true,
                        ),
                        const GapX(S.xs),
                        Flexible(
                          child: Muted(cadenceLabel(b), size: 11, maxLines: 1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const GapX(S.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Amount(money(b.balance), size: 16, color: tint),
                  const Gap(S.hair),
                  Muted('left', size: 10.5),
                ],
              ),
            ],
          ),
          if (!b.isUnplanned) ...[
            const Gap(S.md),
            // Two bars on one track: how full the pot got, and how much of it
            // has been spent.
            Stack(
              children: [
                ProgressBar(
                  value: fundedPct,
                  height: 8,
                  gradient: [
                    tint.withValues(alpha: 0.35),
                    tint.withValues(alpha: 0.25),
                  ],
                ),
                ProgressBar(
                  value: spentPct,
                  height: 8,
                  tone: healthTone(b.health),
                ),
              ],
            ),
            const Gap(S.sm),
            Row(
              children: [
                Muted('${money(b.spentAmount)} spent', size: 11),
                const Spacer(),
                Muted(
                  '${money(b.fundedAmount)} of ${money(b.plannedAmount)} filled',
                  size: 11,
                ),
              ],
            ),
          ],
          const Gap(S.sm),
          Text(
            healthSentence(b, money),
            style: TextStyle(
              fontSize: AppType.caption,
              height: 1.4,
              color: t.mutedForeground,
            ),
          ),
          if (b.carriedIn != '0' && toNum(b.carriedIn) > 0) ...[
            const Gap(S.xs),
            Row(
              children: [
                Icon(Icons.subdirectory_arrow_right, size: 13, color: t.accent),
                const GapX(S.xxs),
                Muted(
                  '${money(b.carriedIn)} carried over from last cycle',
                  size: 11,
                ),
              ],
            ),
          ],
          if (b.nextResetAt != null) ...[
            const Gap(S.xs),
            Row(
              children: [
                Icon(Icons.autorenew, size: 13, color: t.mutedForeground),
                const GapX(S.xxs),
                Muted('Resets ${relativeTime(b.nextResetAt!)}', size: 11),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
