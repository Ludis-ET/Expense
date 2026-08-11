import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../state/auth_state.dart';
import '../../state/data_state.dart';
import '../../state/sms_state.dart';
import '../../widgets/ui.dart';
import 'messaging_points_screen.dart';

/// First-run / re-entry wizard: permission → pair → cash wallet → battery → banks.
Future<bool?> showSmsSetupWizard(BuildContext context) {
  return Navigator.of(
    context,
  ).push<bool>(MaterialPageRoute(builder: (_) => const SmsSetupWizard()));
}

class SmsSetupWizard extends StatefulWidget {
  const SmsSetupWizard({super.key});

  @override
  State<SmsSetupWizard> createState() => _SmsSetupWizardState();
}

class _SmsSetupWizardState extends State<SmsSetupWizard> {
  int _step = 0;
  bool _busy = false;
  String? _error;
  bool _permOk = false;
  bool _paired = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _probe());
  }

  Future<void> _probe() async {
    final sms = context.read<SmsState>();
    final perm = await sms.hasSmsPermission();
    setState(() {
      _permOk = perm;
      _paired = sms.isPaired;
      if (_paired && _permOk) _step = 2;
    });
  }

  Future<void> _requestPerm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await context.read<SmsState>().requestSmsPermission();
    setState(() {
      _busy = false;
      _permOk = ok;
      if (!ok) {
        _error = 'SMS permission is required to capture bank messages.';
      } else {
        _step = 1;
      }
    });
  }

  Future<void> _pair() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final name = Platform.isAndroid ? 'Android phone' : 'This device';
      await context.read<SmsState>().pairDevice(name: name);
      setState(() {
        _paired = true;
        _step = 2;
      });
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickCash() async {
    final data = context.read<DataState>();
    await data.loadAccounts();
    if (!mounted) return;
    final accounts = data.scopedAccounts;
    if (accounts.isEmpty) {
      setState(() => _error = 'Create a wallet first, then come back.');
      return;
    }
    final picked = await showAppSheet<String>(
      context,
      title: 'Cash wallet',
      subtitle: 'ATM withdrawals move here as transfers — not spending.',
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final a in accounts)
            ListTile(
              title: Text(a.name),
              subtitle: Text(a.type.label),
              onTap: () => Navigator.pop(ctx, a.id),
            ),
          SizedBox(height: 12 + MediaQuery.of(ctx).padding.bottom),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await context.read<AuthState>().updateProfile({'cashAccountId': picked});
      setState(() => _step = 3);
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _battery() async {
    await context.read<SmsState>().requestBatteryExemption();
    if (mounted) setState(() => _step = 4);
  }

  Future<void> _finish() async {
    final sms = context.read<SmsState>();
    await sms.loadBanks();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MessagingPointsScreen(fromSetup: true)));
    await sms.completeSetup();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    if (kIsWeb || !Platform.isAndroid) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bank SMS')),
        body: MeshBackground(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(S.xxl),
              child: EmptyState(
                icon: Icons.phone_android_rounded,
                title: 'Android only',
                description:
                    'Bank SMS capture needs the Android APK. Install Santim on your phone to read messages and fill transactions automatically.',
              ),
            ),
          ),
        ),
      );
    }

    final steps = [
      _Step(
        title: 'Allow SMS',
        body:
            'Santim only reads messages from the banks you approve. '
            'Nothing else leaves your phone.',
        action: 'Allow SMS access',
        onAction: _busy ? null : _requestPerm,
        done: _permOk,
      ),
      _Step(
        title: 'Pair this phone',
        body:
            'A private device token lets the phone upload drafts without '
            'keeping you signed in for every message.',
        action: 'Pair phone',
        onAction: _busy || !_permOk ? null : _pair,
        done: _paired,
      ),
      _Step(
        title: 'Cash wallet',
        body:
            'ATM cash-outs become transfers into this wallet so spending '
            'is not double-counted.',
        action: 'Choose cash wallet',
        onAction: _busy || !_paired ? null : _pickCash,
      ),
      _Step(
        title: 'Stay awake',
        body:
            'Android may pause background work. Exempt Santim so bank SMS '
            'still land while the screen is off.',
        action: 'Battery settings',
        onAction: _busy ? null : _battery,
      ),
      _Step(
        title: 'Pick your banks',
        body:
            'Choose which senders count as messaging points, and which '
            'wallet each one fills.',
        action: 'Choose banks',
        onAction: _busy ? null : _finish,
      ),
    ];

    final current = steps[_step.clamp(0, steps.length - 1)];

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Text(
          'Bank SMS setup',
          style: TextStyle(
            fontSize: AppType.lead,
            fontWeight: FontWeight.w700,
            color: t.foreground,
          ),
        ),
      ),
      body: MeshBackground(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.xl, S.md, S.xl, S.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Progress(step: _step, total: steps.length),
              const Gap(S.xl),
              Expanded(
                child: FadeInUp(
                  child: GlassCard(
                    padding: const EdgeInsets.all(S.xxl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(colors: [t.primary, t.accent]),
                            boxShadow: [
                              BoxShadow(color: t.primary.withValues(alpha: 0.35), blurRadius: 18),
                            ],
                          ),
                          child: const Icon(Icons.sms_rounded, color: Colors.white),
                        ),
                        const Gap(S.lg),
                        Text(
                          current.title,
                          style: TextStyle(
                            fontSize: AppType.figure,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: t.foreground,
                          ),
                        ),
                        const Gap(S.sm),
                        Muted(current.body, size: 14, height: 1.45, maxLines: 6),
                        const Spacer(),
                        if (_error != null) ...[
                          Text(
                            _error!,
                            style: TextStyle(color: t.danger, fontSize: AppType.bodySm),
                          ),
                          const Gap(S.md),
                        ],
                        AppButton(
                          label: _busy ? 'Working…' : current.action,
                          expand: true,
                          onPressed: current.onAction == null
                              ? null
                              : () {
                                  Haptics.select();
                                  current.onAction!();
                                },
                        ),
                        if (_step > 0) ...[
                          const Gap(S.sm),
                          AppButton(
                            label: 'Back',
                            variant: BtnVariant.ghost,
                            expand: true,
                            onPressed: _busy
                                ? null
                                : () => setState(() => _step = (_step - 1).clamp(0, 4)),
                          ),
                        ],
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
}

class _Step {
  const _Step({
    required this.title,
    required this.body,
    required this.action,
    required this.onAction,
    this.done = false,
  });
  final String title;
  final String body;
  final String action;
  final VoidCallback? onAction;
  final bool done;
}

class _Progress extends StatelessWidget {
  const _Progress({required this.step, required this.total});
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: Motion.fast,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: i <= step ? t.primary : t.border,
                boxShadow: i <= step
                    ? [BoxShadow(color: t.primary.withValues(alpha: 0.45), blurRadius: 8)]
                    : null,
              ),
            ),
          ),
          if (i < total - 1) const GapX(S.xs),
        ],
      ],
    );
  }
}
