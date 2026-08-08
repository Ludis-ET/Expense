import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/formatting.dart';
import '../core/theme.dart';
import '../models/finance.dart';
import '../state/data_store.dart';
import '../widgets/common.dart';
import '../widgets/scoped_tx_list.dart';
import '../widgets/web_chrome.dart';

/// Full plan detail — matches website `/budgets/[id]`.
class BudgetDetailScreen extends StatefulWidget {
  const BudgetDetailScreen({super.key, required this.budgetId, this.seed});

  final String budgetId;
  final Budget? seed;

  @override
  State<BudgetDetailScreen> createState() => _BudgetDetailScreenState();
}

class _BudgetDetailScreenState extends State<BudgetDetailScreen> {
  BudgetDetail? _detail;
  List<Transaction> _txs = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  Budget get plan => _detail?.plan ?? widget.seed!;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = context.read<DataStore>();
      final detail = await data.fetchBudgetDetail(widget.budgetId);
      final txs = await data.fetchTransactions(budgetId: widget.budgetId, pageSize: 50);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _txs = txs;
        _loading = false;
        if (detail == null && widget.seed == null) _error = 'Plan not found';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Could not load plan';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;

    if (_loading && _detail == null && widget.seed == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Plan')),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              ShimmerBlock(height: 180),
              SizedBox(height: 12),
              ShimmerBlock(height: 100),
            ],
          ),
        ),
      );
    }

    if (_error != null && _detail == null && widget.seed == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Plan')),
        body: EmptyState(
          icon: Icons.savings_outlined,
          title: 'Plan not found',
          message: _error,
          action: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
        ),
      );
    }

    final b = plan;
    final accent = parseHexColor(b.color) ?? colors.primary;
    final closed = b.state == 'CLOSED';
    final left = Money.parse(b.potBalance);
    final planned = Money.parse(b.plannedAmount).clamp(0.01, double.infinity);
    final spentPct = ((Money.parse(b.spentAmount) / planned) * 100).clamp(0, 100);
    final balancePct = ((left / planned) * 100).clamp(0, 100 - spentPct);

    return Scaffold(
      appBar: AppBar(
        title: Text(b.isUnplanned ? 'Catch-all' : 'Plan'),
        actions: [
          if (!b.isUnplanned && !closed)
            IconButton(
              tooltip: 'Put money in',
              onPressed: () => _openFundRelease(fund: true),
              icon: const Icon(Icons.north_east_rounded),
            ),
          if (!b.isUnplanned && left > 0)
            IconButton(
              tooltip: 'Give back',
              onPressed: () => _openFundRelease(fund: false),
              icon: const Icon(Icons.south_west_rounded),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            SoftCard(
              padding: const EdgeInsets.all(20),
              color: accent.withValues(alpha: 0.08),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.savings_rounded, color: accent, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    b.name,
                                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _HealthChip(health: b.health),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (b.kind == 'RECURRING') 'resets ${b.recurrenceLabel ?? 'periodically'}'
                                else if (b.isUnplanned) 'catch-all'
                                else 'one-time plan',
                                if (b.categoryName != null) b.categoryName!,
                                if (b.cycleLabel != null) b.cycleLabel!,
                              ].join(' · '),
                              style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                            ),
                            if (b.note?.isNotEmpty == true) ...[
                              const SizedBox(height: 6),
                              Text(b.note!, style: theme.textTheme.bodySmall?.copyWith(color: colors.muted)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (!b.isUnplanned) ...[
                    const SizedBox(height: 18),
                    Text(
                      'LEFT IN THIS PLAN',
                      style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: colors.muted),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Money.format(b.potBalance, currency: b.currency),
                      style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: SizedBox(
                        height: 10,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(color: colors.surfaceMuted),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: (spentPct / 100).clamp(0.0, 1.0),
                              child: ColoredBox(color: colors.muted.withValues(alpha: 0.35)),
                            ),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: ((spentPct + balancePct) / 100).clamp(0.0, 1.0),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: FractionallySizedBox(
                                  widthFactor: balancePct <= 0
                                      ? 0
                                      : (balancePct / (spentPct + balancePct)).clamp(0.0, 1.0),
                                  child: ColoredBox(color: accent),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Planned ${Money.format(b.plannedAmount, currency: b.currency)} · '
                      'filled ${Money.format(b.fundedAmount, currency: b.currency)} · '
                      'spent ${Money.format(b.spentAmount, currency: b.currency)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                    ),
                  ] else ...[
                    const SizedBox(height: 18),
                    Text('Spent so far', style: theme.textTheme.bodySmall?.copyWith(color: colors.muted)),
                    Text(
                      Money.format(b.spentAmount, currency: b.currency),
                      style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ],
              ),
            ),

            if (closed) ...[
              const SizedBox(height: 12),
              SoftCard(
                color: colors.surfaceMuted,
                child: Text(
                  'This plan is closed — it no longer appears when you add a transaction. Its history is kept below.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                ),
              ),
            ],

            if (!b.isUnplanned && !b.started && b.startsAt != null) ...[
              const SizedBox(height: 12),
              SoftCard(
                color: const Color(0xFF6366F1).withValues(alpha: 0.06),
                child: Row(
                  children: [
                    const Icon(Icons.event_outlined, color: Color(0xFF6366F1), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Starts on ${Dates.day(b.startsAt)}. You can fill it now, but nothing can be spent until then.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),
            if (!b.isUnplanned)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!closed)
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _openFundRelease(fund: true),
                      icon: const Icon(Icons.north_east_rounded, size: 16),
                      label: const Text('Put money in'),
                    ),
                  if (left > 0)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _openFundRelease(fund: false),
                      icon: const Icon(Icons.south_west_rounded, size: 16),
                      label: const Text('Give back'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => closed ? _actReopen() : _actClose(),
                    icon: Icon(closed ? Icons.unarchive_outlined : Icons.archive_outlined, size: 16),
                    label: Text(closed ? 'Reopen' : 'Close'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: colors.danger),
                    onPressed: _busy ? null : _actDelete,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Delete'),
                  ),
                ],
              ),

            const SizedBox(height: 16),
            // Stat strip
            if (b.isUnplanned)
              Row(
                children: [
                  _stat(context, 'Spent', Money.format(b.spentAmount, currency: b.currency)),
                  _stat(
                    context,
                    'All time',
                    Money.format(_detail?.lifetimeSpent ?? b.spentAmount, currency: b.currency),
                    sub: '${_detail?.lifetimeTxCount ?? _txs.length} tx',
                  ),
                ],
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: (MediaQuery.sizeOf(context).width - 40) / 2,
                    child: _statTile(context, 'Planned', Money.format(b.plannedAmount, currency: b.currency)),
                  ),
                  SizedBox(
                    width: (MediaQuery.sizeOf(context).width - 40) / 2,
                    child: _statTile(
                      context,
                      'Filled this cycle',
                      Money.format(b.fundedAmount, currency: b.currency),
                      sub: Money.parse(b.carriedIn) > 0
                          ? 'incl. ${Money.format(b.carriedIn, currency: b.currency)} carried'
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: (MediaQuery.sizeOf(context).width - 40) / 2,
                    child: _statTile(
                      context,
                      'Spent this cycle',
                      Money.format(b.spentAmount, currency: b.currency),
                      sub: '${b.pctSpentOfFunded}% of what’s in',
                    ),
                  ),
                  SizedBox(
                    width: (MediaQuery.sizeOf(context).width - 40) / 2,
                    child: _statTile(
                      context,
                      'Lifetime',
                      Money.format(_detail?.lifetimeSpent ?? '0', currency: b.currency),
                      sub: 'across ${_detail?.lifetimeCycleCount ?? 0} cycles',
                    ),
                  ),
                ],
              ),

            if ((_detail?.sources.isNotEmpty ?? false) && !b.isUnplanned) ...[
              const SizedBox(height: 16),
              SoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Money held per account', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      'Still physically in these accounts — just not counted as available.',
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                    ),
                    const SizedBox(height: 12),
                    for (final s in _detail!.sources) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: colors.surfaceMuted.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.account_balance_wallet_outlined, size: 16, color: colors.muted),
                            const SizedBox(width: 8),
                            Expanded(child: Text(s.accountName, style: const TextStyle(fontWeight: FontWeight.w600))),
                            Text(
                              Money.format(s.available, currency: b.currency),
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 18),
            Text('Transactions', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            Text(
              _loading ? 'Loading…' : '${_txs.length} shown',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
            ),
            const SizedBox(height: 10),
            ScopedTransactionList(
              items: _txs,
              loading: _loading && _txs.isEmpty,
              emptyMessage: 'No spending filed under this plan yet.',
            ),

            if (!b.isUnplanned) ...[
              const SizedBox(height: 18),
              Text('Recent movements', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              if ((_detail?.timeline ?? const []).isEmpty)
                SoftCard(
                  child: Text(
                    'Put money in from an account to get this plan going.',
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                  ),
                )
              else
                SoftCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < _detail!.timeline.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: colors.border),
                        _TimelineRow(entry: _detail!.timeline[i], currency: b.currency),
                      ],
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value, {String? sub}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: _statTile(context, label, value, sub: sub),
      ),
    );
  }

  Widget _statTile(BuildContext context, String label, String value, {String? sub}) {
    final colors = Theme.of(context).extension<SantimColors>()!;
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: colors.muted)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(fontSize: 11, color: colors.muted)),
          ],
        ],
      ),
    );
  }

  Future<void> _openFundRelease({required bool fund}) async {
    final updated = await showSantimSheet<BudgetDetail>(
      context: context,
      title: fund ? 'Put money in "${plan.name}"' : 'Give back from "${plan.name}"',
      builder: (ctx) => _FundReleaseBody(
        detail: _detail ?? BudgetDetail(plan: plan),
        fund: fund,
      ),
    );
    if (updated != null && mounted) {
      setState(() => _detail = updated);
      await _reload();
      if (mounted) await context.read<DataStore>().refreshAll();
    }
  }

  Future<void> _actClose() async {
    setState(() => _busy = true);
    try {
      await context.read<DataStore>().closeBudget(widget.budgetId);
      if (mounted) {
        showOk(context, 'Plan closed');
        await _reload();
      }
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _actReopen() async {
    setState(() => _busy = true);
    try {
      await context.read<DataStore>().reopenBudget(widget.budgetId);
      if (mounted) {
        showOk(context, 'Plan reopened');
        await _reload();
      }
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _actDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this plan?'),
        content: const Text(
          'Expenses already recorded against it stay in your transactions as ordinary expenses.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 40)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<DataStore>().deleteBudget(widget.budgetId);
      if (!mounted) return;
      showOk(context, 'Plan deleted');
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _HealthChip extends StatelessWidget {
  const _HealthChip({required this.health});
  final String health;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (health) {
      'empty' || 'drained' => ('Empty', SantimTheme.expense),
      'low' || 'warning' => ('Running low', SantimTheme.warning),
      'over' => ('Over', SantimTheme.expense),
      'closed' => ('Closed', const Color(0xFF64748B)),
      _ => ('Healthy', SantimTheme.income),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.4),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.entry, required this.currency});
  final BudgetTimelineEntry entry;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SantimColors>()!;
    final isIn = entry.kind.toUpperCase().contains('FUND') ||
        entry.kind.toUpperCase().contains('ALLOC') ||
        entry.kind.toUpperCase() == 'IN';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Icon(
        isIn ? Icons.north_east_rounded : Icons.south_west_rounded,
        color: isIn ? colors.success : colors.danger,
        size: 18,
      ),
      title: Text(
        entry.note?.isNotEmpty == true
            ? entry.note!
            : (isIn ? 'Filled' : entry.kind.replaceAll('_', ' ').toLowerCase()),
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        [
          if (entry.accountName != null) entry.accountName!,
          Dates.day(entry.date),
        ].join(' · '),
        style: TextStyle(fontSize: 12, color: colors.muted),
      ),
      trailing: Text(
        '${isIn ? '+' : '−'}${Money.format(entry.amount, currency: currency)}',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: isIn ? colors.success : colors.danger,
        ),
      ),
    );
  }
}

class _FundReleaseBody extends StatefulWidget {
  const _FundReleaseBody({required this.detail, required this.fund});
  final BudgetDetail detail;
  final bool fund;

  @override
  State<_FundReleaseBody> createState() => _FundReleaseBodyState();
}

class _FundReleaseBodyState extends State<_FundReleaseBody> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late DateTime _date;
  String? _accountId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    final data = context.read<DataStore>();
    if (widget.fund) {
      _accountId = data.activeAccounts
              .where((a) => a.currency == widget.detail.plan.currency)
              .firstOrNull
              ?.id ??
          data.activeAccounts.firstOrNull?.id;
    } else {
      _accountId = widget.detail.sources.where((s) => Money.parse(s.available) > 0).firstOrNull?.accountId;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final plan = widget.detail.plan;
    final accounts = widget.fund
        ? data.activeAccounts.where((a) => a.currency == plan.currency).toList()
        : <Account>[];

    final releaseOptions = widget.detail.sources.where((s) => Money.parse(s.available) > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.fund
              ? 'The cash stays in your account but stops counting as available until you spend it here.'
              : 'Returns money to the account it came from and frees it to spend elsewhere.',
          style: TextStyle(fontSize: 13, color: Theme.of(context).extension<SantimColors>()!.muted),
        ),
        const SizedBox(height: 14),
        if (widget.fund)
          SantimSelect<String>(
            label: 'From account',
            value: _accountId,
            items: [
              for (final a in accounts)
                MapEntry(a.id, '${a.name} — ${Money.format(a.available, currency: a.currency)}'),
            ],
            onChanged: (v) => setState(() => _accountId = v),
          )
        else
          SantimSelect<String>(
            label: 'Back to account',
            value: _accountId,
            items: [
              for (final s in releaseOptions)
                MapEntry(s.accountId, '${s.accountName} — ${Money.format(s.available, currency: plan.currency)} held'),
            ],
            onChanged: (v) => setState(() => _accountId = v),
          ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
          decoration: const InputDecoration(labelText: 'Amount', hintText: '0.00'),
          validator: (v) {
            final n = double.tryParse((v ?? '').replaceAll(',', ''));
            if (n == null || n <= 0) return 'Enter an amount';
            return null;
          },
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2015),
              lastDate: DateTime.now(),
            );
            if (picked != null) setState(() => _date = picked);
          },
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Date'),
            child: Text(DateFormat('yyyy-MM-dd').format(_date)),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _note,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(widget.fund ? 'Set aside' : 'Give back'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      showError(context, 'Enter an amount');
      return;
    }
    if (_accountId == null) {
      showError(context, 'Pick an account');
      return;
    }
    setState(() => _busy = true);
    try {
      final data = context.read<DataStore>();
      final date = DateFormat('yyyy-MM-dd').format(_date);
      final updated = widget.fund
          ? await data.fundBudget(
              budgetId: planId,
              accountId: _accountId!,
              amount: amount,
              date: date,
              note: _note.text.trim(),
            )
          : await data.releaseBudget(
              budgetId: planId,
              accountId: _accountId!,
              amount: amount,
              date: date,
              note: _note.text.trim(),
            );
      if (!mounted) return;
      Navigator.pop(context, updated);
      showOk(context, widget.fund ? 'Money set aside in the plan' : 'Money returned to the account');
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get planId => widget.detail.plan.id;
}
