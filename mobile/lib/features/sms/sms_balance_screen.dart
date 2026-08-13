import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../state/prefs_state.dart';
import '../../state/sms_state.dart';
import '../../widgets/ui.dart';
import 'messaging_points_screen.dart';

/// Compares the latest SMS-reported bank balance to Santim wallet balances.
class SmsBalanceScreen extends StatefulWidget {
  const SmsBalanceScreen({super.key});

  @override
  State<SmsBalanceScreen> createState() => _SmsBalanceScreenState();
}

class _SmsBalanceScreenState extends State<SmsBalanceScreen> {
  bool _loading = true;
  String? _error;
  List<BalanceDrift> _drifts = const [];
  double _threshold = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final drifts = await context.read<SmsState>().loadBalanceReconciliation(
        threshold: _threshold,
      );
      setState(() => _drifts = drifts);
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final prefs = context.watch<PrefsState>();

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Text(
          'Balance check',
          style: TextStyle(
            fontSize: AppType.lead,
            fontWeight: FontWeight.w700,
            color: t.foreground,
          ),
        ),
      ),
      body: MeshBackground(
        child: RefreshIndicator(
          onRefresh: _load,
          color: t.primary,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 40),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              GlassCard(
                padding: const EdgeInsets.all(S.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'SMS vs wallet',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: AppType.lead,
                            color: t.foreground,
                          ),
                        ),
                        const GapX(S.xs),
                        const InfoHint(
                          label: 'SMS vs wallet',
                          body:
                              'When a bank SMS includes a remaining balance, Santim '
                              'compares it to the mapped wallet. Soft alerts only — '
                              'nothing is changed automatically.',
                          size: 16,
                        ),
                      ],
                    ),
                    const Gap(S.md),
                    Text(
                      'Alert when drift ≥ ${_threshold.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: AppType.label,
                        color: t.mutedForeground,
                      ),
                    ),
                    Slider(
                      value: _threshold,
                      min: 1,
                      max: 500,
                      divisions: 20,
                      label: _threshold.toStringAsFixed(0),
                      onChanged: (v) => setState(() => _threshold = v),
                      onChangeEnd: (_) => _load(),
                    ),
                  ],
                ),
              ),
              const Gap(S.lg),
              if (_loading)
                const PageLoader(rows: 3)
              else if (_error != null)
                ErrorState(message: _error!, onRetry: _load)
              else if (_drifts.isEmpty)
                const EmptyState(
                  icon: Icons.verified_outlined,
                  title: 'Balances look aligned',
                  description:
                      'No SMS balance drifted past your threshold. Map senders '
                      'to wallets so Santim knows which account each message is about.',
                )
              else ...[
                SectionLabel('${_drifts.length} ALERTS'),
                for (final d in _drifts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: S.sm),
                    child: AppCard(
                      padding: const EdgeInsets.all(S.lg),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MessagingPointsScreen(),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              IconTile(
                                icon: Icons.balance_rounded,
                                color: t.warning,
                                size: 40,
                              ),
                              const GapX(S.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d.account.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Muted(
                                      d.message.bankLabel ?? d.message.sender,
                                      size: 12,
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                'Δ ${prefs.money(d.drift, currency: d.account.currency)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: t.warning,
                                ),
                              ),
                            ],
                          ),
                          const Gap(S.md),
                          Row(
                            children: [
                              Expanded(
                                child: _Fig(
                                  label: 'SMS says',
                                  value: prefs.money(
                                    d.smsBalance,
                                    currency: d.account.currency,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: _Fig(
                                  label: 'Santim wallet',
                                  value: prefs.money(
                                    d.walletBalance,
                                    currency: d.account.currency,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Gap(S.sm),
                          Muted(
                            'From SMS ${formatDate(d.message.receivedAt)}'
                            '${d.message.parsedRef != null ? ' · ref ${d.message.parsedRef}' : ''}',
                            size: 11.5,
                          ),
                        ],
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

class _Fig extends StatelessWidget {
  const _Fig({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: AppType.caption, color: t.mutedForeground),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: AppType.body,
          ),
        ),
      ],
    );
  }
}
