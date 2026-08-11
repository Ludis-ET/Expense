import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
import '../../widgets/fields.dart';
import '../../widgets/sync_ui.dart';
import '../../widgets/ui.dart';

/// Money Tab — who owes you, who you owe, and what is expected either way.
/// Grouped by person, because that is how the debt is actually remembered.
class TabScreen extends StatefulWidget {
  const TabScreen({super.key});

  @override
  State<TabScreen> createState() => _TabScreenState();
}

class _TabScreenState extends State<TabScreen> {
  LedgerSummary? _summary;
  List<LedgerPersonGroup> _people = const [];
  bool _loading = true;
  Object? _error;
  bool _showSettled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = context.read<ApiClient>();
      final currency = context.read<DataState>().activeCurrency;

      if (_showSettled) {
        final results = await Future.wait([
          api.get<Map<String, dynamic>>('/ledger/summary', query: {'currency': currency}),
          api.get<Map<String, dynamic>>('/ledger', query: {'status': 'all', 'currency': currency}),
        ]);
        if (!mounted) return;
        setState(() {
          _summary = LedgerSummary.fromJson(results[0]);
          _people = _groupEntries(mapItemsList(results[1], LedgerEntry.fromJson));
          _loading = false;
          _error = null;
        });
      } else {
        final results = await Future.wait([
          api.get<Map<String, dynamic>>('/ledger/summary', query: {'currency': currency}),
          api.get<Map<String, dynamic>>('/ledger/people', query: {'currency': currency}),
        ]);
        if (!mounted) return;
        setState(() {
          _summary = LedgerSummary.fromJson(results[0]);
          _people = mapItemsList(results[1], LedgerPersonGroup.fromJson);
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Fallback when showing settled/all entries — groups the flat ledger list.
  List<LedgerPersonGroup> _groupEntries(List<LedgerEntry> entries) {
    final groups = <String, List<LedgerEntry>>{};
    for (final e in entries) {
      final key = e.counterparty.trim().toLowerCase();
      groups.putIfAbsent(key, () => []).add(e);
    }

    final out = <LedgerPersonGroup>[];
    for (final list in groups.values) {
      var receivable = 0.0;
      var expectedIn = 0.0;
      var payable = 0.0;
      var expectedOut = 0.0;
      var openCount = 0;
      for (final e in list) {
        if (e.status != 'OPEN') continue;
        openCount++;
        final rem = toNum(e.remaining);
        switch (e.kind) {
          case LedgerKind.lent:
            receivable += rem;
          case LedgerKind.expectedIn:
            expectedIn += rem;
          case LedgerKind.borrowed:
            payable += rem;
          case LedgerKind.expectedOut:
            expectedOut += rem;
        }
      }
      final inflow = receivable + expectedIn;
      final outflow = payable + expectedOut;
      out.add(
        LedgerPersonGroup(
          counterparty: list.first.counterparty,
          openCount: openCount,
          receivable: receivable.toStringAsFixed(2),
          expectedIn: expectedIn.toStringAsFixed(2),
          payable: payable.toStringAsFixed(2),
          expectedOut: expectedOut.toStringAsFixed(2),
          netRemaining: (inflow - outflow).toStringAsFixed(2),
          netDirection: inflow >= outflow ? 'in' : 'out',
          entries: list,
        ),
      );
    }
    out.sort((a, b) => toNum(b.netRemaining).abs().compareTo(toNum(a.netRemaining).abs()));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final prefs = context.watch<PrefsState>();
    final data = context.watch<DataState>();
    final s = _summary;
    final currency = s?.currency ?? data.activeCurrency;

    String money(Object? v) => prefs.money(v, currency: currency);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Money Tab',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.foreground),
        ),
        actions: [
          IconPill(
            icon: Icons.add,
            tooltip: 'New entry',
            onTap: () async {
              final saved = await showLedgerForm(context);
              if (saved == true) {
                _load();
                if (context.mounted) await context.read<DataState>().refreshAfterWrite();
              }
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: MeshBackground(
        showGrid: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: t.primary,
          backgroundColor: t.surface,
          child: ListView(
            padding: EdgeInsets.fromLTRB(14, 4, 14, ShellLayout.bottomClearance(context)),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const OfflineBanner(),
              if (_loading && s == null)
                const PageLoader(rows: 4)
              else if (_error != null && s == null)
                ErrorState(
                  message: _error is ApiError
                      ? (_error as ApiError).message
                      : 'Could not load your tab.',
                  onRetry: _load,
                )
              else if (s != null) ...[
                FadeInUp(child: _SummaryHero(summary: s, money: money)),
                const SizedBox(height: 14),

                if (s.overdue.isNotEmpty) ...[
                  FadeInUp(
                    delay: const Duration(milliseconds: 60),
                    child: AppCard(
                      padding: const EdgeInsets.all(14),
                      color: t.danger.withValues(alpha: 0.06),
                      borderColor: t.danger.withValues(alpha: 0.25),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, size: 17, color: t.danger),
                              const SizedBox(width: 8),
                              Text(
                                '${s.overdueCount} overdue',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: t.danger,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          for (final e in s.overdue.take(4))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${e.counterparty}${e.title != null ? ' · ${e.title}' : ''}',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12.5, color: t.foreground),
                                    ),
                                  ),
                                  Muted(formatDayMonth(e.dueDate), size: 11),
                                  const SizedBox(width: 10),
                                  Amount(money(e.remaining), size: 12.5, color: t.danger),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                Row(
                  children: [
                    SectionLabel(_showSettled ? 'EVERYONE' : 'OPEN WITH'),
                    const Spacer(),
                    AppButton(
                      label: _showSettled ? 'Open only' : 'Show settled',
                      variant: BtnVariant.ghost,
                      size: BtnSize.sm,
                      onPressed: () {
                        setState(() => _showSettled = !_showSettled);
                        _load();
                      },
                    ),
                  ],
                ),

                if (_people.isEmpty)
                  EmptyState(
                    icon: Icons.volunteer_activism_outlined,
                    title: 'Nothing on the tab',
                    description: 'Track money you lent, borrowed, or are still '
                        'expecting — so nobody has to remember it.',
                    action: AppButton(
                      label: 'Add an entry',
                      icon: Icons.add,
                      size: BtnSize.sm,
                      onPressed: () async {
                        final saved = await showLedgerForm(context);
                        if (saved == true) _load();
                      },
                    ),
                  )
                else
                  for (var i = 0; i < _people.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: FadeInUp.staggered(
                        index: i,
                        child: _PersonCard(
                          group: _people[i],
                          money: money,
                          onChanged: () async {
                            _load();
                            if (context.mounted) {
                              await context.read<DataState>().refreshAfterWrite();
                            }
                          },
                        ),
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryHero extends StatelessWidget {
  const _SummaryHero({required this.summary, required this.money});

  final LedgerSummary summary;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    final net = toNum(summary.netPosition);
    return GradientHero(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            net >= 0 ? 'Net owed to you' : 'Net you owe',
            style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.72)),
          ),
          const SizedBox(height: 6),
          AnimatedNumber(
            value: net.abs(),
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
          Row(
            children: [
              Expanded(child: _Fig(label: 'Owed to you', value: money(summary.receivable))),
              const SizedBox(width: 10),
              Expanded(child: _Fig(label: 'You owe', value: money(summary.payable))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _Fig(label: 'Expected in', value: money(summary.expectedIn))),
              const SizedBox(width: 10),
              Expanded(child: _Fig(label: 'Expected out', value: money(summary.expectedOut))),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${summary.openCount} open · forecast ${money(summary.netIfOnTime)} '
            'if everything due settles this month',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.8),
            ),
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
                fontSize: 14.5,
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

class _PersonCard extends StatefulWidget {
  const _PersonCard({
    required this.group,
    required this.money,
    required this.onChanged,
  });

  final LedgerPersonGroup group;
  final String Function(Object?) money;
  final VoidCallback onChanged;

  @override
  State<_PersonCard> createState() => _PersonCardState();
}

class _PersonCardState extends State<_PersonCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final g = widget.group;
    final inbound = g.netDirection == 'in';

    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Avatar(name: g.counterparty, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.counterparty,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Muted('${g.openCount} open item${g.openCount == 1 ? '' : 's'}', size: 11.5),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Amount(
                    widget.money(toNum(g.netRemaining).abs()),
                    size: 15.5,
                    color: inbound ? t.success : t.danger,
                  ),
                  const SizedBox(height: 2),
                  Muted(inbound ? 'owes you' : 'you owe', size: 10.5),
                ],
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: Motion.fast,
                child: Icon(Icons.expand_more, size: 19, color: t.mutedForeground),
              ),
            ],
          ),
          AnimatedSize(
            duration: Motion.fast,
            curve: Motion.easeOut,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 14),
                      for (final e in g.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: _EntryRow(
                            entry: e,
                            money: widget.money,
                            onChanged: widget.onChanged,
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

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.money,
    required this.onChanged,
  });

  final LedgerEntry entry;
  final String Function(Object?) money;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final e = entry;
    final tone = e.isOverdue ? t.danger : (e.kind.inbound ? t.success : t.warning);

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: t.surfaceMuted.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(R.md),
        border: e.isOverdue
            ? Border.all(color: t.danger.withValues(alpha: 0.3))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                e.kind.inbound ? Icons.south_west_rounded : Icons.north_east_rounded,
                size: 15,
                color: tone,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.title ?? e.kind.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.foreground,
                  ),
                ),
              ),
              if (!e.isOpen)
                AppBadge(e.status == 'SETTLED' ? 'Settled' : 'Cancelled', dense: true)
              else
                Amount(money(e.remaining), size: 13, color: tone),
            ],
          ),
          if (e.isOpen) ...[
            const SizedBox(height: 8),
            ProgressBar(
              value: e.pct,
              height: 5,
              tone: e.isOverdue ? BadgeTone.danger : BadgeTone.primary,
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Muted('${money(e.paid)} of ${money(e.totalAmount)} paid', size: 11),
                const Spacer(),
                if (e.dueDate != null)
                  Muted(
                    e.isOverdue
                        ? 'Overdue ${relativeTime(e.dueDate!)}'
                        : 'Due ${formatDayMonth(e.dueDate)}',
                    size: 11,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Record payment',
                    icon: Icons.payments_outlined,
                    size: BtnSize.sm,
                    variant: BtnVariant.outline,
                    expand: true,
                    onPressed: () async {
                      final done = await showPaymentSheet(context, entry: e);
                      if (done == true) onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconPill(
                  icon: Icons.more_horiz,
                  size: 34,
                  onTap: () => _menu(context),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _menu(BuildContext context) async {
    final action = await showAppSheet<String>(
      context,
      title: entry.counterparty,
      subtitle: entry.title ?? entry.kind.label,
      scrollable: false,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: 16 + MediaQuery.of(ctx).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              onTap: () => Navigator.pop(ctx, 'edit'),
              leading: const Icon(Icons.edit_outlined, size: 20),
              title: const Text('Edit', style: TextStyle(fontSize: 14.5)),
            ),
            ListTile(
              onTap: () => Navigator.pop(ctx, 'cancel'),
              leading: const Icon(Icons.block, size: 20),
              title: const Text('Cancel this entry', style: TextStyle(fontSize: 14.5)),
            ),
            ListTile(
              onTap: () => Navigator.pop(ctx, 'delete'),
              leading: Icon(Icons.delete_outline, size: 20, color: ctx.t.danger),
              title: Text(
                'Delete',
                style: TextStyle(fontSize: 14.5, color: ctx.t.danger),
              ),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case 'edit':
        final saved = await showLedgerForm(context, existing: entry);
        if (saved == true) onChanged();
      case 'cancel':
        try {
          final result = await context.read<SyncState>().ledgerCancel(
                entry.id,
                label: entry.counterparty,
              );
          if (result.queued && context.mounted) {
            toast(context, 'Queued offline — will sync when you are back online');
          }
          onChanged();
        } on ApiError catch (e) {
          if (context.mounted) toast(context, e.message, error: true);
        }
      case 'delete':
        final ok = await confirm(
          context,
          title: 'Delete this entry?',
          message: 'Payments already recorded against it stay in your transactions.',
        );
        if (!ok || !context.mounted) return;
        try {
          final result = await context.read<SyncState>().deleteLedger(
                entry.id,
                label: entry.counterparty,
              );
          if (result.queued && context.mounted) {
            toast(context, 'Delete queued — will sync when you are back online');
          }
          onChanged();
        } on ApiError catch (e) {
          if (context.mounted) toast(context, e.message, error: true);
        }
    }
  }
}

/// Add or edit a tab entry.
Future<bool?> showLedgerForm(BuildContext context, {LedgerEntry? existing}) {
  return showAppSheet<bool>(
    context,
    title: existing == null ? 'New tab entry' : 'Edit entry',
    builder: (ctx) => _LedgerForm(existing: existing),
  );
}

class _LedgerForm extends StatefulWidget {
  const _LedgerForm({this.existing});
  final LedgerEntry? existing;

  @override
  State<_LedgerForm> createState() => _LedgerFormState();
}

class _LedgerFormState extends State<_LedgerForm> {
  late final _amount = TextEditingController(
    text: widget.existing == null ? '' : toNum(widget.existing!.totalAmount).toString(),
  );
  late final _counterparty =
      TextEditingController(text: widget.existing?.counterparty ?? '');
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');

  late LedgerKind _kind = widget.existing?.kind ?? LedgerKind.lent;
  late DateTime? _dueDate = widget.existing?.dueDate;
  bool _recordMovement = false;
  String? _sourceAccountId;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<DataState>().loadAccounts();
      if (!mounted) return;
      final accounts = context.read<DataState>().scopedAccounts;
      final fallback = accounts.where((a) => a.isDefault).firstOrNull ?? accounts.firstOrNull;
      setState(() => _sourceAccountId = fallback?.id);
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _counterparty.dispose();
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (_counterparty.text.trim().isEmpty) {
      setState(() => _error = 'Who is this with?');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final data = context.read<DataState>();
    // Only LENT and BORROWED move cash right now; the expected kinds do not.
    final canMove = _kind == LedgerKind.lent || _kind == LedgerKind.borrowed;

    try {
      final sync = context.read<SyncState>();
      final QueueResult result;
      if (_isEdit) {
        result = await sync.saveLedger(
          id: widget.existing!.id,
          label: _counterparty.text.trim(),
          body: {
            'counterparty': _counterparty.text.trim(),
            'title': _title.text.trim().isEmpty ? null : _title.text.trim(),
            'totalAmount': amount,
            'dueDate': _dueDate?.toUtc().toIso8601String(),
            'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
          },
        );
      } else {
        result = await sync.saveLedger(
          label: _counterparty.text.trim(),
          body: {
            'kind': _kind.wire,
            'counterparty': _counterparty.text.trim(),
            if (_title.text.trim().isNotEmpty) 'title': _title.text.trim(),
            'totalAmount': amount,
            'currency': data.activeCurrency,
            if (_dueDate != null) 'dueDate': _dueDate!.toUtc().toIso8601String(),
            if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
            if (canMove && _recordMovement) ...{
              'recordMovement': true,
              if (_sourceAccountId != null) 'sourceAccountId': _sourceAccountId,
            },
          },
        );
      }
      if (!mounted) return;
      if (result.queued) {
        toast(context, 'Saved offline — will sync when you are back online');
      }
      Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final data = context.watch<DataState>();
    final accounts = data.scopedAccounts;
    final canMove = _kind == LedgerKind.lent || _kind == LedgerKind.borrowed;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_isEdit) ...[
            PickerField<LedgerKind>(
              label: 'What is this?',
              value: _kind,
              options: LedgerKind.values,
              labelOf: (k) => k.label,
              iconOf: (k) => k.inbound
                  ? Icons.south_west_rounded
                  : Icons.north_east_rounded,
              colorOf: (k) => k.inbound ? t.success : t.warning,
              onChanged: (k) => setState(() => _kind = k ?? _kind),
            ),
            const SizedBox(height: 16),
          ],
          AmountField(
            controller: _amount,
            currency: widget.existing?.currency ?? data.activeCurrency,
            tint: _kind.inbound ? t.success : t.warning,
            autofocus: !_isEdit,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _counterparty,
            label: 'With who?',
            placeholder: 'Abebe',
            prefixIcon: Icons.person_outline,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _title,
            label: 'What for?',
            placeholder: 'Rent share, taxi money…',
            prefixIcon: Icons.label_outline,
          ),
          const SizedBox(height: 16),
          DateField(
            label: 'Due',
            placeholder: 'No due date',
            value: _dueDate,
            allowClear: true,
            onChanged: (d) => setState(() => _dueDate = d),
          ),
          if (!_isEdit && canMove) ...[
            const SizedBox(height: 8),
            SwitchRow(
              title: _kind == LedgerKind.lent
                  ? 'Money left my wallet now'
                  : 'Money arrived in my wallet now',
              subtitle: 'Records the matching transaction so balances stay true.',
              icon: Icons.account_balance_wallet_outlined,
              value: _recordMovement,
              onChanged: (v) => setState(() => _recordMovement = v),
            ),
            if (_recordMovement) ...[
              const SizedBox(height: 10),
              PickerField<Account>(
                label: _kind == LedgerKind.lent ? 'From wallet' : 'Into wallet',
                value: accounts.where((a) => a.id == _sourceAccountId).firstOrNull,
                options: accounts,
                labelOf: (a) => a.name,
                subtitleOf: (a) => '${formatMoney(a.balance, currency: a.currency)} available',
                iconOf: (a) => accountTypeIcon(a.type.wire),
                onChanged: (a) => setState(() => _sourceAccountId = a?.id),
              ),
            ],
          ],
          const SizedBox(height: 16),
          AppTextField(
            controller: _note,
            label: 'Note',
            placeholder: 'Anything worth remembering',
            maxLines: 2,
            prefixIcon: Icons.notes_outlined,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: TextStyle(fontSize: 13, color: t.danger)),
          ],
          const SizedBox(height: 20),
          AppButton(
            label: _isEdit ? 'Save changes' : 'Add to the tab',
            icon: Icons.check,
            size: BtnSize.lg,
            expand: true,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}

/// Record a payment against an entry, optionally posting the matching
/// transaction so balances stay true.
Future<bool?> showPaymentSheet(BuildContext context, {required LedgerEntry entry}) {
  return showAppSheet<bool>(
    context,
    title: 'Record payment',
    subtitle: '${entry.counterparty} · ${formatMoney(entry.remaining, currency: entry.currency)} left',
    builder: (ctx) => _PaymentSheet(entry: entry),
  );
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.entry});
  final LedgerEntry entry;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  bool _recordTransaction = true;
  String? _accountId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount.text = toNum(widget.entry.remaining).toString();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<DataState>().loadAccounts();
      if (!mounted) return;
      final accounts = context.read<DataState>().scopedAccounts;
      final fallback = accounts.where((a) => a.isDefault).firstOrNull ?? accounts.firstOrNull;
      setState(() => _accountId = fallback?.id);
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    if (amount > toNum(widget.entry.remaining)) {
      setState(() => _error =
          'Only ${formatMoney(widget.entry.remaining, currency: widget.entry.currency)} is outstanding.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await context.read<SyncState>().ledgerPayment(
            entryId: widget.entry.id,
            label: widget.entry.counterparty,
            body: {
              'amount': amount,
              'date': _date.toUtc().toIso8601String(),
              if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
              'recordTransaction': _recordTransaction,
              if (_recordTransaction && _accountId != null) 'accountId': _accountId,
            },
          );
      if (!mounted) return;
      if (result.queued) {
        toast(context, 'Saved offline — will sync when you are back online');
      }
      Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final accounts = context.watch<DataState>().scopedAccounts;
    final inbound = widget.entry.kind.inbound;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AmountField(
            controller: _amount,
            currency: widget.entry.currency,
            tint: inbound ? t.success : t.warning,
            autofocus: true,
          ),
          const SizedBox(height: 16),
          DateField(
            label: 'Date',
            value: _date,
            onChanged: (d) => setState(() => _date = d ?? _date),
          ),
          const SizedBox(height: 8),
          SwitchRow(
            title: 'Also record the transaction',
            subtitle: inbound
                ? 'Adds the money as income in the wallet you pick.'
                : 'Takes the money out of the wallet you pick.',
            icon: Icons.receipt_long_outlined,
            value: _recordTransaction,
            onChanged: (v) => setState(() => _recordTransaction = v),
          ),
          if (_recordTransaction) ...[
            const SizedBox(height: 10),
            PickerField<Account>(
              label: inbound ? 'Into wallet' : 'From wallet',
              value: accounts.where((a) => a.id == _accountId).firstOrNull,
              options: accounts,
              labelOf: (a) => a.name,
              subtitleOf: (a) => '${formatMoney(a.balance, currency: a.currency)} available',
              iconOf: (a) => accountTypeIcon(a.type.wire),
              onChanged: (a) => setState(() => _accountId = a?.id),
            ),
          ],
          const SizedBox(height: 16),
          AppTextField(
            controller: _note,
            label: 'Note',
            placeholder: 'Optional',
            prefixIcon: Icons.notes_outlined,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: TextStyle(fontSize: 13, color: t.danger)),
          ],
          const SizedBox(height: 20),
          AppButton(
            label: 'Record payment',
            icon: Icons.check,
            size: BtnSize.lg,
            expand: true,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
