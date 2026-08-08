import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../models/extra.dart';
import '../state/data_store.dart';
import '../widgets/common.dart';
import '../widgets/web_chrome.dart';

class MoneyTabScreen extends StatefulWidget {
  const MoneyTabScreen({super.key});

  @override
  State<MoneyTabScreen> createState() => _MoneyTabScreenState();
}

class _MoneyTabScreenState extends State<MoneyTabScreen> {
  String _filter = 'all';
  LedgerSummary _summary = const LedgerSummary();
  List<LedgerEntry> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = context.read<DataStore>();
      final results = await Future.wait([
        data.fetchLedgerSummary(),
        data.fetchLedger(kind: _filter == 'all' ? null : _filter),
      ]);
      final summary = LedgerSummary.fromJson(results[0]);
      final items = (((results[1]['items'] as List?) ?? const []))
          .whereType<Map<String, dynamic>>()
          .map(LedgerEntry.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;
    final filters = const [
      ('all', 'All open'),
      ('LENT', 'They owe me'),
      ('BORROWED', 'I owe'),
      ('EXPECTED_IN', 'Incoming'),
      ('EXPECTED_OUT', 'Outgoing'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Money Tab'),
        actions: const [WebTopActions()],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            if (_summary.forecastNet != null)
              SoftCard(
                color: colors.primary.withValues(alpha: 0.05),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CASH-FLOW FORECAST · ${_summary.forecastMonth ?? ''}',
                            style: TextStyle(fontSize: 10, letterSpacing: 0.6, fontWeight: FontWeight.w600, color: colors.muted),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'If everything due this month settles on time',
                            style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      Money.format(_summary.forecastNet),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Money.parse(_summary.forecastNet) >= 0 ? colors.success : colors.warning,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SoftCard(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _mini(context, 'They owe', _summary.receivable, colors.success),
                  _mini(context, 'I owe', _summary.payable, colors.danger),
                  _mini(context, 'Incoming', _summary.expectedIn, colors.primary),
                  _mini(context, 'Outgoing', _summary.expectedOut, colors.warning),
                  _mini(context, 'Net', _summary.netPosition, colors.accent),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(f.$2),
                        selected: _filter == f.$1,
                        onSelected: (_) {
                          setState(() => _filter = f.$1);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const ShimmerBlock(height: 140)
            else if (_items.isEmpty)
              const EmptyState(
                icon: Icons.handshake_outlined,
                title: "You're all square",
                message: 'Nothing open on your money tab.',
              )
            else
              for (final e in _items) ...[
                SoftCard(
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          switch (e.kind) {
                            'LENT' => Icons.south_west_rounded,
                            'BORROWED' => Icons.north_east_rounded,
                            'EXPECTED_IN' => Icons.auto_awesome,
                            _ => Icons.event_outlined,
                          },
                          color: colors.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.counterparty, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                              [
                                e.title ?? e.kind.replaceAll('_', ' ').toLowerCase(),
                                if (e.dueDate != null) 'due ${Dates.day(e.dueDate)}',
                                if (e.isOverdue) 'overdue',
                              ].join(' · '),
                              style: TextStyle(fontSize: 12, color: e.isOverdue ? colors.danger : colors.muted),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        Money.format(e.remaining, currency: e.currency),
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }

  Widget _mini(BuildContext context, String label, String value, Color color) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).extension<SantimColors>()!.muted)),
          Text(Money.format(value), style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}
