import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/haptics.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../models/money.dart';
import '../../state/data_state.dart';
import '../../state/sync_state.dart';
import '../../widgets/ui.dart';

/// The Money Doctor.
///
/// Santim proves its own books balance after every write, and this is where the
/// proof is visible. Shipping it in the open rather than hiding it is
/// deliberate: it turns the scariest class of bug - a number quietly being
/// wrong - into something a person can see and fix in one tap.
///
/// The healthy state is what people will nearly always see, so it is designed
/// first: a calm, complete picture of where their money is, not an empty page
/// with nothing to report.
class MoneyDoctorScreen extends StatefulWidget {
  const MoneyDoctorScreen({super.key});

  @override
  State<MoneyDoctorScreen> createState() => _MoneyDoctorScreenState();
}

class _MoneyDoctorScreenState extends State<MoneyDoctorScreen> {
  MoneyHealth? _health;
  bool _loading = true;
  bool _fixing = false;
  String? _settling;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = context.read<DataState>();
      final health = await context.read<SyncState>().moneyHealth(
        currency: data.activeCurrency,
      );
      if (!mounted) return;
      setState(() {
        _health = health;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiError ? e.message : 'Could not run the check.';
        _loading = false;
      });
    }
  }

  Future<void> _fix() async {
    setState(() => _fixing = true);
    Haptics.commit();
    try {
      final health = await context.read<SyncState>().repairMoney();
      if (!mounted) return;
      await context.read<DataState>().refreshAfterWrite();
      if (!mounted) return;
      setState(() => _health = health);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            health.healthy
                ? 'Everything balances again.'
                : 'Some of it needed a closer look - see below.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiError ? e.message : 'Could not repair.')),
      );
    } finally {
      if (mounted) setState(() => _fixing = false);
    }
  }

  Future<void> _settle(WalletDrift row) async {
    final data = context.read<DataState>();
    final category = data.categoriesOfKind(TxKind.expense).firstOrNull;
    if (category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Create an expense category first, so the difference has somewhere to be filed.',
          ),
        ),
      );
      return;
    }

    setState(() => _settling = row.account.id);
    try {
      await context.read<SyncState>().settleDrift(
        accountId: row.account.id,
        categoryId: category.id,
      );
      if (!mounted) return;
      await context.read<DataState>().refreshAfterWrite();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recorded. This wallet matches the bank now.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiError ? e.message : 'Could not settle that.')),
      );
    } finally {
      if (mounted) setState(() => _settling = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final health = _health;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Money check'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Re-check',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(S.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: t.mutedForeground),
                    ),
                    const Gap(S.md),
                    TextButton(onPressed: _load, child: const Text('Try again')),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.lg, S.lg, S.lg, S.huge),
                children: [
                  _Verdict(
                    health: health!,
                    fixing: _fixing,
                    onFix: _fix,
                  ),
                  const Gap(S.lg),
                  _MoneySplit(health: health),
                  if (health.drift.isNotEmpty) ...[
                    const Gap(S.lg),
                    _DriftSection(
                      drift: health.drift,
                      settling: _settling,
                      onSettle: _settle,
                    ),
                  ],
                  const Gap(S.lg),
                  _WalletBreakdown(health: health),
                  const Gap(S.lg),
                  _PlanHoldings(health: health),
                ],
              ),
            ),
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.health, required this.fixing, required this.onFix});

  final MoneyHealth health;
  final bool fixing;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final ok = health.healthy;
    final tone = ok ? t.success : t.warning;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  ok ? Icons.verified_rounded : Icons.health_and_safety_outlined,
                  color: tone,
                ),
              ),
              const GapX(S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ok ? 'Your money adds up' : 'Something does not add up',
                      style: TextStyle(
                        fontSize: AppType.lead,
                        fontWeight: FontWeight.w700,
                        color: t.foreground,
                      ),
                    ),
                    const Gap(S.hair),
                    Text(
                      ok
                          ? "Every plan's money is backed by a wallet that really holds it."
                          : health.problems.length == 1
                          ? '1 thing needs putting right.'
                          : '${health.problems.length} things need putting right.',
                      style: TextStyle(
                        fontSize: AppType.bodySm,
                        height: 1.4,
                        color: t.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!ok) ...[
            const Gap(S.md),
            for (final problem in health.problems)
              Padding(
                padding: const EdgeInsets.only(bottom: S.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: t.warning),
                    const GapX(S.sm),
                    Expanded(
                      child: Text(
                        problem.message,
                        style: TextStyle(
                          fontSize: AppType.bodySm,
                          height: 1.45,
                          color: t.foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Gap(S.xs),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: fixing ? null : onFix,
                icon: fixing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.healing_rounded, size: 18),
                label: Text(fixing ? 'Fixing…' : 'Fix it'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MoneySplit extends StatelessWidget {
  const _MoneySplit({required this.health});

  final MoneyHealth health;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cells = [
      ('In your wallets', health.real, t.foreground, Icons.account_balance_wallet_outlined),
      ('Set aside', health.reserved, t.primary, Icons.lock_outline_rounded),
      ('Ready to assign', health.readyToAssign, t.success, Icons.savings_outlined),
    ];

    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const GapX(S.sm),
          Expanded(
            child: AppCard(
              padding: const EdgeInsets.all(S.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(cells[i].$4, size: 15, color: t.mutedForeground),
                  const Gap(S.xs),
                  Text(
                    cells[i].$1,
                    style: TextStyle(
                      fontSize: AppType.micro,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                      color: t.mutedForeground,
                    ),
                  ),
                  const Gap(S.hair),
                  Text(
                    formatMoney(cells[i].$2, currency: health.currency),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w700,
                      color: cells[i].$3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// What the bank says, versus what we say.
///
/// Every parsed bank message carries the balance the bank thinks you have. Until
/// now that figure was read and thrown away; comparing it is drift detection for
/// free, and it is something only an app that reads your bank SMS can do well.
class _DriftSection extends StatelessWidget {
  const _DriftSection({
    required this.drift,
    required this.settling,
    required this.onSettle,
  });

  final List<WalletDrift> drift;
  final String? settling;
  final ValueChanged<WalletDrift> onSettle;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_rounded, size: 18, color: t.primary),
              const GapX(S.sm),
              Expanded(
                child: Text(
                  'Your bank says something different',
                  style: TextStyle(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w700,
                    color: t.foreground,
                  ),
                ),
              ),
            ],
          ),
          const Gap(S.md),
          for (final row in drift) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.account.name,
                        style: TextStyle(
                          fontSize: AppType.bodySm,
                          fontWeight: FontWeight.w600,
                          color: t.foreground,
                        ),
                      ),
                      Text(
                        'Santim ${formatMoney(row.santimBalance)} · '
                        'bank ${formatMoney(row.bankBalance)}',
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
                      formatMoney(row.difference),
                      style: TextStyle(
                        fontSize: AppType.bodySm,
                        fontWeight: FontWeight.w700,
                        color: t.warning,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      row.missingSpending
                          ? 'spending not recorded'
                          : 'money not recorded',
                      style: TextStyle(
                        fontSize: AppType.micro,
                        color: t.mutedForeground,
                      ),
                    ),
                  ],
                ),
                const GapX(S.sm),
                settling == row.account.id
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        onPressed: () => onSettle(row),
                        child: const Text('Record'),
                      ),
              ],
            ),
            if (row != drift.last) const Divider(height: S.lg),
          ],
        ],
      ),
    );
  }
}

class _WalletBreakdown extends StatelessWidget {
  const _WalletBreakdown({required this.health});

  final MoneyHealth health;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Wallet by wallet',
            style: TextStyle(
              fontSize: AppType.body,
              fontWeight: FontWeight.w700,
              color: t.foreground,
            ),
          ),
          const Gap(S.md),
          for (final w in health.wallets) ...[
            Row(
              children: [
                Icon(
                  financeIcon(w.icon ?? 'wallet'),
                  size: 16,
                  color: parseHexColor(w.color) ?? t.mutedForeground,
                ),
                const GapX(S.sm),
                Expanded(
                  child: Text(
                    w.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.bodySm,
                      fontWeight: FontWeight.w600,
                      color: t.foreground,
                    ),
                  ),
                ),
                Text(
                  '${formatMoney(w.free, currency: w.currency)} free',
                  style: TextStyle(
                    fontSize: AppType.caption,
                    color: t.mutedForeground,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const Gap(S.xs),
            // The bar is the point: how much of this wallet is spoken for.
            ClipRRect(
              borderRadius: BorderRadius.circular(R.pill),
              child: LinearProgressIndicator(
                value: asNum(w.real) > 0
                    ? (asNum(w.reserved) / asNum(w.real)).clamp(0.0, 1.0)
                    : 0,
                minHeight: 5,
                backgroundColor: t.surfaceMuted,
                valueColor: AlwaysStoppedAnimation(t.primary.withValues(alpha: 0.7)),
              ),
            ),
            if (w != health.wallets.last) const Gap(S.md),
          ],
        ],
      ),
    );
  }
}

class _PlanHoldings extends StatelessWidget {
  const _PlanHoldings({required this.health});

  final MoneyHealth health;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What each plan is holding',
            style: TextStyle(
              fontSize: AppType.body,
              fontWeight: FontWeight.w700,
              color: t.foreground,
            ),
          ),
          const Gap(S.md),
          if (health.plans.isEmpty)
            Text(
              'No plan is holding money right now. Everything you have is free to assign.',
              style: TextStyle(
                fontSize: AppType.bodySm,
                height: 1.45,
                color: t.mutedForeground,
              ),
            )
          else
            for (final p in health.plans)
              Padding(
                padding: const EdgeInsets.only(bottom: S.sm),
                child: Row(
                  children: [
                    Icon(
                      financeIcon(p.icon ?? 'savings'),
                      size: 16,
                      color: parseHexColor(p.color) ?? t.primary,
                    ),
                    const GapX(S.sm),
                    Expanded(
                      child: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.bodySm,
                          fontWeight: FontWeight.w600,
                          color: t.foreground,
                        ),
                      ),
                    ),
                    Text(
                      formatMoney(p.holding, currency: p.currency),
                      style: TextStyle(
                        fontSize: AppType.bodySm,
                        color: t.mutedForeground,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
