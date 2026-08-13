import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../state/sms_state.dart';
import '../../widgets/ui.dart';
import 'messaging_points_screen.dart';

/// Flags bank senders whose parse confidence is slipping or failing.
class SmsSenderHealthScreen extends StatefulWidget {
  const SmsSenderHealthScreen({super.key});

  @override
  State<SmsSenderHealthScreen> createState() => _SmsSenderHealthScreenState();
}

class _SmsSenderHealthScreenState extends State<SmsSenderHealthScreen> {
  bool _loading = true;
  bool _reparsing = false;
  String? _error;
  List<SenderHealth> _rows = const [];

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
      final rows = await context.read<SmsState>().loadSenderHealth();
      setState(() => _rows = rows);
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reparse() async {
    setState(() => _reparsing = true);
    try {
      final json = await context.read<SmsState>().reparse();
      if (!mounted) return;
      final updated = json['updated'];
      toast(context, updated == null ? 'Reparse finished' : 'Updated $updated messages');
      await _load();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _reparsing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final unhealthy = _rows.where((r) => r.unhealthy).length;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Text(
          'Sender health',
          style: TextStyle(
            fontSize: AppType.lead,
            fontWeight: FontWeight.w700,
            color: t.foreground,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _reparsing ? null : _reparse,
            child: Text(_reparsing ? 'Reparsing…' : 'Reparse all'),
          ),
        ],
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
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(colors: [t.primary, t.accent]),
                          ),
                          child: const Icon(
                            Icons.monitor_heart_outlined,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const GapX(S.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      unhealthy == 0
                                          ? 'Parsers look healthy'
                                          : '$unhealthy need attention',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: AppType.lead,
                                        color: t.foreground,
                                      ),
                                    ),
                                  ),
                                  const InfoHint(
                                    label: 'Sender health',
                                    body:
                                        'When a bank changes its SMS template, confidence drops. '
                                        'Reparse stored messages after a fix.',
                                    size: 16,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Gap(S.lg),
              if (_loading)
                const PageLoader(rows: 3)
              else if (_error != null)
                ErrorState(message: _error!, onRetry: _load)
              else if (_rows.isEmpty)
                const EmptyState(
                  icon: Icons.cell_tower_rounded,
                  title: 'No sender history yet',
                  description: 'Confirm a few bank messages first, then health trends appear here.',
                )
              else ...[
                SectionLabel('SENDERS'),
                for (final row in _rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: S.sm),
                    child: AppCard(
                      padding: const EdgeInsets.all(S.lg),
                      onTap: () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute(builder: (_) => const MessagingPointsScreen())),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          IconTile(
                            icon: row.unhealthy
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline,
                            color: row.unhealthy ? t.warning : t.success,
                            size: 40,
                          ),
                          const GapX(S.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row.sender,
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                Muted(
                                  [
                                    if (row.bankLabel != null) row.bankLabel!,
                                    '${row.sampleCount} msgs',
                                    if (row.rule?.account != null) '→ ${row.rule!.account!.name}',
                                  ].join(' · '),
                                  size: 12,
                                ),
                                const Gap(S.sm),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    _StatChip(
                                      label: 'Recent ${row.recentAvgConfidence.round()}%',
                                      color: row.recentAvgConfidence >= 70 ? t.success : t.warning,
                                    ),
                                    _StatChip(
                                      label: 'Before ${row.olderAvgConfidence.round()}%',
                                      color: t.mutedForeground,
                                    ),
                                    if (row.confidenceDrop >= 10)
                                      _StatChip(
                                        label: '↓ ${row.confidenceDrop.round()} pts',
                                        color: t.danger,
                                      ),
                                    if (row.unparsedCount > 0)
                                      _StatChip(
                                        label: '${row.unparsedCount} unparsed',
                                        color: t.danger,
                                      ),
                                  ],
                                ),
                              ],
                            ),
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

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.sm, vertical: S.xxs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: AppType.caption, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
