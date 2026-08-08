import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/formatting.dart';
import '../core/theme.dart';
import '../state/auth_store.dart';
import '../widgets/common.dart';
import '../widgets/web_chrome.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late String _month;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _month = MonthNavigator.currentMonth();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final currency = context.read<AuthStore>().user?.currency ?? 'ETB';
      final api = context.read<ApiClient>();
      final data = await api.get('/analytics/page', query: {
        'month': _month,
        'currency': currency,
      }) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Could not load analytics';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;
    final monthSummary = _data?['month'] as Map<String, dynamic>?;
    final plans = ((_data?['plans'] as List?) ?? const []).whereType<Map<String, dynamic>>().toList();
    final categories = ((_data?['categories'] as List?) ?? (_data?['byCategory'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: const [WebTopActions()],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            MonthNavigator(
              month: _month,
              onChanged: (m) {
                setState(() => _month = m);
                _load();
              },
            ),
            const SizedBox(height: 12),
            if (_loading)
              const ShimmerBlock(height: 160)
            else if (_error != null)
              EmptyState(icon: Icons.bar_chart_rounded, title: 'Analytics unavailable', message: _error)
            else ...[
              SoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Month snapshot', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _kpi(context, 'Income', monthSummary?['income'] ?? monthSummary?['totalIncome'], colors.success),
                        _kpi(context, 'Expense', monthSummary?['expense'] ?? monthSummary?['totalExpense'], colors.danger),
                        _kpi(context, 'Net', monthSummary?['net'] ?? monthSummary?['netIncome'], colors.primary),
                      ],
                    ),
                  ],
                ),
              ),
              if (categories.isNotEmpty) ...[
                const SizedBox(height: 14),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('By category', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      for (final c in categories.take(12))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${c['name'] ?? c['categoryName'] ?? 'Category'}',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              Text(
                                Money.format(c['amount'] ?? c['spent'] ?? c['total']),
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (plans.isNotEmpty) ...[
                const SizedBox(height: 14),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Plans', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      for (final p in plans.take(12))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                              Text(
                                Money.format(p['spent'] ?? p['spentAmount']),
                                style: TextStyle(fontWeight: FontWeight.w800, color: colors.danger),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _kpi(BuildContext context, String label, Object? value, Color color) {
    return Expanded(
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
