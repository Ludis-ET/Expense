import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
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
    final active = all.where((b) => !b.isClosed && !b.isUnplanned).toList();
    final unplanned = all.where((b) => b.isUnplanned).firstOrNull;
    final closed = all.where((b) => b.isClosed).toList();
    final totals = response?.totals;

    return RefreshIndicator(
      onRefresh: () => data.loadBudgets(force: true, includeClosed: _showClosed),
      color: t.primary,
      backgroundColor: t.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 130),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          PageHeader(
            title: 'Plans',
            description: 'A plan is an envelope. Filling it moves money out of '
                'your available balance and reserves it, so what is left over '
                'is genuinely free to spend.',
            action: IconPill(
              icon: Icons.add,
              tooltip: 'New plan',
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
              FadeInUp(child: _TotalsHero(totals: totals, money: money)),
            const SizedBox(height: 16),

            AppCard(
              padding: const EdgeInsets.all(14),
              onTap: () => shell.push(const WishlistScreen()),
              child: Row(
                children: [
                  IconTile(icon: Icons.favorite_border, color: t.accent, size: 40),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Wishlist',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: t.foreground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Muted('Things you want. Turn one into a plan when you are ready.',
                            size: 12, maxLines: 2),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 20, color: t.mutedForeground),
                ],
              ),
            ),
            const SizedBox(height: 18),

            if (active.isEmpty)
              EmptyState(
                icon: Icons.savings_outlined,
                title: 'No plans yet',
                description: 'Set money aside for what you intend to spend — '
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
                  padding: const EdgeInsets.only(bottom: 12),
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
              const SizedBox(height: 6),
              SectionLabel('CATCH-ALL'),
              BudgetCard(
                budget: unplanned,
                money: money,
                onTap: () => _open(context, unplanned),
              ),
            ],

            const SizedBox(height: 16),
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
              const SizedBox(height: 10),
              for (final b in closed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
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
      await context.read<DataState>().loadBudgets(force: true, includeClosed: _showClosed);
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
    final fundedPct = planned <= 0 ? 0.0 : (funded / planned * 100).clamp(0.0, 100.0);

    return GradientHero(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reserved across ${totals.activeCount} active plan'
            '${totals.activeCount == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 6),
          AnimatedNumber(
            value: toNum(totals.locked),
            builder: (context, v) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                money(v),
                style: const TextStyle(
                  fontSize: 33,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1.2,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(R.pill),
            child: LinearProgressIndicator(
              value: fundedPct / 100,
              minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${money(funded)} filled of ${money(planned)} planned',
            style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _Fig(label: 'Spent from plans', value: money(spent))),
              const SizedBox(width: 10),
              Expanded(
                child: _Fig(
                  label: 'Unplanned spend',
                  value: money(totals.unplannedSpent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fig extends StatelessWidget {
  const _Fig({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return GlassChip(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 15,
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

/// `BudgetPlanCard` — the pot's shape at a glance: how much went in, how much
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
      padding: const EdgeInsets.all(15),
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.foreground,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        AppBadge(b.health.label, tone: healthTone(b.health), dense: true),
                        const SizedBox(width: 6),
                        Flexible(child: Muted(cadenceLabel(b), size: 11, maxLines: 1)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Amount(money(b.balance), size: 16, color: tint),
                  const SizedBox(height: 2),
                  Muted('left', size: 10.5),
                ],
              ),
            ],
          ),
          if (!b.isUnplanned) ...[
            const SizedBox(height: 14),
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
            const SizedBox(height: 8),
            Row(
              children: [
                Muted('${money(b.spentAmount)} spent', size: 11),
                const Spacer(),
                Muted('${money(b.fundedAmount)} of ${money(b.plannedAmount)} filled', size: 11),
              ],
            ),
          ],
          const SizedBox(height: 9),
          Text(
            healthSentence(b, money),
            style: TextStyle(fontSize: 11.5, height: 1.4, color: t.mutedForeground),
          ),
          if (b.carriedIn != '0' && toNum(b.carriedIn) > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.subdirectory_arrow_right, size: 13, color: t.accent),
                const SizedBox(width: 5),
                Muted('${money(b.carriedIn)} carried over from last cycle', size: 11),
              ],
            ),
          ],
          if (b.nextResetAt != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.autorenew, size: 13, color: t.mutedForeground),
                const SizedBox(width: 5),
                Muted('Resets ${relativeTime(b.nextResetAt!)}', size: 11),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
