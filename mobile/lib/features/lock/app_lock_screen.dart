import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../state/app_lock_state.dart';
import '../../widgets/ui.dart';

/// Full-screen PIN / biometric unlock gate.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  String _pin = '';
  String? _error;
  int _shake = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  Future<void> _tryBiometric() async {
    final lock = context.read<AppLockState>();
    if (!lock.biometricEnabled || !lock.biometricAvailable || _busy) return;
    setState(() => _busy = true);
    final ok = await lock.unlockWithBiometric();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      // Stay on PIN   user cancelled or failed biometrics.
    }
  }

  Future<void> _submit(String pin) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await context.read<AppLockState>().unlockWithPin(pin);
    if (!mounted) return;
    if (ok) {
      Haptics.toggle();
      setState(() {
        _pin = '';
        _busy = false;
      });
      return;
    }
    Haptics.reject();
    setState(() {
      _pin = '';
      _busy = false;
      _error = 'Wrong PIN';
      _shake++;
    });
  }

  void _tap(String digit) {
    if (_busy || _pin.length >= AppLockState.pinMax) return;
    Haptics.select();
    final lock = context.read<AppLockState>();
    final next = '$_pin$digit';
    setState(() {
      _pin = next;
      _error = null;
    });
    if (next.length == lock.pinLength) {
      _submit(next);
    }
  }

  void _backspace() {
    if (_pin.isEmpty || _busy) return;
    Haptics.select();
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final lock = context.watch<AppLockState>();

    return Scaffold(
      backgroundColor: t.background,
      body: MeshBackground(
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              const BrandMark(size: 64),
              const Gap(S.lg),
              const BrandWord(fontSize: AppType.figure),
              const Gap(S.sm),
              Muted('Enter your PIN to unlock', size: 14),
              const Gap(S.xxl),
              ShakeX(
                trigger: _shake,
                child: _PinDots(
                  length: lock.pinLength,
                  filled: _pin.length,
                  error: _error != null,
                ),
              ),
              if (_error != null) ...[
                const Gap(S.md),
                Text(
                  _error!,
                  style: TextStyle(
                    fontSize: AppType.bodySm,
                    fontWeight: FontWeight.w600,
                    color: t.danger,
                  ),
                ),
              ],
              const Spacer(flex: 2),
              _Keypad(
                onDigit: _tap,
                onBackspace: _backspace,
                biometric: lock.biometricEnabled && lock.biometricAvailable,
                onBiometric: _busy ? null : _tryBiometric,
              ),
              const Gap(S.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({
    required this.length,
    required this.filled,
    required this.error,
  });

  final int length;
  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final color = error ? t.danger : t.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final on = i < filled;
        return Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: S.sm),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? color : Colors.transparent,
            border: Border.all(color: on ? color : t.border, width: 2),
          ),
        );
      }),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onBackspace,
    required this.biometric,
    required this.onBiometric,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool biometric;
  final VoidCallback? onBiometric;

  @override
  Widget build(BuildContext context) {
    Widget key(
      String label, {
      VoidCallback? onTap,
      IconData? icon,
      Color? color,
    }) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(S.xs),
          child: Material(
            color: context.t.surface,
            borderRadius: BorderRadius.circular(R.lg),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(R.lg),
              child: SizedBox(
                height: 58,
                child: Center(
                  child: icon != null
                      ? Icon(
                          icon,
                          color: color ?? context.t.foreground,
                          size: 26,
                        )
                      : Text(
                          label,
                          style: TextStyle(
                            fontSize: AppType.figure,
                            fontWeight: FontWeight.w600,
                            color: context.t.foreground,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.huge),
      child: Column(
        children: [
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(
              children: [for (final d in row) key(d, onTap: () => onDigit(d))],
            ),
          Row(
            children: [
              biometric
                  ? key(
                      '',
                      icon: Icons.fingerprint_rounded,
                      color: context.t.primary,
                      onTap: onBiometric,
                    )
                  : const Expanded(child: SizedBox()),
              key('0', onTap: () => onDigit('0')),
              key('', icon: Icons.backspace_outlined, onTap: onBackspace),
            ],
          ),
        ],
      ),
    );
  }
}
