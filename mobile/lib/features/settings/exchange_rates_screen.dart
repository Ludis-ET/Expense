import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/layout.dart';
import '../../models/common.dart';
import '../../state/data_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';

/// `ExchangeRatesPanel` — rates are only needed to show one combined total
/// across currencies. Per-currency figures never use them.
class ExchangeRatesScreen extends StatefulWidget {
  const ExchangeRatesScreen({super.key});

  @override
  State<ExchangeRatesScreen> createState() => _ExchangeRatesScreenState();
}

class _Rate {
  const _Rate({required this.id, required this.from, required this.to, required this.rate});
  final String id;
  final String from;
  final String to;
  final double rate;

  factory _Rate.fromJson(Map<String, dynamic> j) => _Rate(
        id: asStr(j['id'], ''),
        from: asStr(j['fromCurrency'], ''),
        to: asStr(j['toCurrency'], ''),
        rate: asNum(j['rate']),
      );
}

class _ExchangeRatesScreenState extends State<ExchangeRatesScreen> {
  List<_Rate> _rates = const [];
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
      final json = await context.read<ApiClient>().get<List>('/exchange-rates');
      if (!mounted) return;
      setState(() {
        _rates = mapList(json, _Rate.fromJson);
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

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Exchange rates',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.foreground),
        ),
        actions: [
          IconPill(icon: Icons.add, tooltip: 'Add a rate', onTap: () => _edit(context)),
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
              AppCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: t.primary),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        'Rates are only used to show one combined total across '
                        'currencies. Every per-currency figure in the app is '
                        'untouched by them.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: t.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_loading && _rates.isEmpty)
                const PageLoader(rows: 3, hero: false)
              else if (_error != null && _rates.isEmpty)
                ErrorState(
                  message: _error is ApiError
                      ? (_error as ApiError).message
                      : 'Could not load your rates.',
                  onRetry: _load,
                )
              else if (_rates.isEmpty)
                EmptyState(
                  icon: Icons.currency_exchange,
                  title: 'No rates set',
                  description: 'Add one for each pair you hold, and the '
                      'dashboard can show a combined total.',
                  action: AppButton(
                    label: 'Add a rate',
                    icon: Icons.add,
                    size: BtnSize.sm,
                    onPressed: () => _edit(context),
                  ),
                )
              else
                for (var i = 0; i < _rates.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: FadeInUp.staggered(
                      index: i,
                      child: AppCard(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        onTap: () => _edit(context, existing: _rates[i]),
                        child: Row(
                          children: [
                            IconTile(
                              icon: Icons.currency_exchange,
                              color: t.accent,
                              size: 36,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '1 ${_rates[i].from} = ${_rates[i].rate} ${_rates[i].to}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: t.foreground,
                                ),
                              ),
                            ),
                            IconPill(
                              icon: Icons.delete_outline,
                              size: 32,
                              background: Colors.transparent,
                              color: t.danger,
                              onTap: () => _delete(context, _rates[i]),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, _Rate rate) async {
    final ok = await confirm(
      context,
      title: 'Delete this rate?',
      message: 'Combined totals will leave ${rate.from} out until you add it again.',
    );
    if (!ok || !context.mounted) return;
    try {
      await context.read<ApiClient>().delete('/exchange-rates/${rate.id}');
      await _load();
      if (context.mounted) await context.read<DataState>().loadDashboard(force: true);
    } on ApiError catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _edit(BuildContext context, {_Rate? existing}) async {
    const currencies = ['ETB', 'USD', 'EUR', 'GBP', 'KES', 'AED'];
    var from = existing?.from ?? 'USD';
    var to = existing?.to ?? 'ETB';
    final rate = TextEditingController(text: existing?.rate.toString() ?? '');

    final saved = await showAppSheet<bool>(
      context,
      title: existing == null ? 'Add a rate' : 'Edit rate',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.of(ctx).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: PickerField<String>(
                      label: 'From',
                      value: from,
                      options: currencies,
                      labelOf: (c) => c,
                      onChanged: (c) => setSheet(() => from = c ?? from),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(10, 22, 10, 0),
                    child: Icon(Icons.arrow_forward, size: 18),
                  ),
                  Expanded(
                    child: PickerField<String>(
                      label: 'To',
                      value: to,
                      options: currencies,
                      labelOf: (c) => c,
                      onChanged: (c) => setSheet(() => to = c ?? to),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: rate,
                label: 'Rate',
                hint: 'How many "to" units one "from" unit buys.',
                placeholder: '1 $from = ? $to',
                prefixIcon: Icons.calculate_outlined,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 20),
              AppButton(
                label: 'Save rate',
                icon: Icons.check,
                size: BtnSize.lg,
                expand: true,
                onPressed: () async {
                  final value = double.tryParse(rate.text.trim());
                  if (value == null || value <= 0) {
                    toast(ctx, 'Enter a rate greater than zero.', error: true);
                    return;
                  }
                  if (from == to) {
                    toast(ctx, 'Pick two different currencies.', error: true);
                    return;
                  }
                  try {
                    await ctx.read<ApiClient>().put('/exchange-rates', body: {
                      'rates': [
                        {'fromCurrency': from, 'toCurrency': to, 'rate': value},
                      ],
                    });
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } on ApiError catch (e) {
                    if (ctx.mounted) toast(ctx, e.message, error: true);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == true) {
      await _load();
      if (context.mounted) await context.read<DataState>().loadDashboard(force: true);
    }
  }
}
