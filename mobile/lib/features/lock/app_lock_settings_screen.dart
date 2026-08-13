import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/layout.dart';
import '../../state/app_lock_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';

/// Settings hub for enabling, changing, or disabling the app PIN / biometrics.
class AppLockSettingsScreen extends StatelessWidget {
  const AppLockSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final lock = context.watch<AppLockState>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'App lock',
          style: TextStyle(
            fontSize: AppType.lead,
            fontWeight: FontWeight.w700,
            color: t.foreground,
          ),
        ),
      ),
      body: MeshBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(14, 4, 14, ShellLayout.bottomClearance(context)),
          children: [
            AppCard(
              padding: const EdgeInsets.all(S.lg),
              child: Column(
                children: [
                  SwitchRow(
                    title: 'Require PIN',
                    subtitle: 'Lock Santim when you leave the app.',
                    icon: Icons.lock_outline_rounded,
                    value: lock.enabled,
                    onChanged: (v) async {
                      if (v) {
                        final pin = await _promptNewPin(context);
                        if (pin == null || !context.mounted) return;
                        try {
                          await context.read<AppLockState>().enableWithPin(pin);
                          if (context.mounted) toast(context, 'App lock enabled');
                        } catch (e) {
                          if (context.mounted) {
                            toast(context, e.toString(), error: true);
                          }
                        }
                      } else {
                        final pin = await _promptCurrentPin(
                          context,
                          title: 'Turn off app lock',
                          subtitle: 'Enter your PIN to disable.',
                        );
                        if (pin == null || !context.mounted) return;
                        try {
                          await context.read<AppLockState>().disable(pin: pin);
                          if (context.mounted) toast(context, 'App lock disabled');
                        } catch (_) {
                          if (context.mounted) {
                            toast(context, 'Wrong PIN', error: true);
                          }
                        }
                      }
                    },
                  ),
                  if (lock.enabled) ...[
                    const Gap(S.xxs),
                    SwitchRow(
                      title: 'Biometrics',
                      subtitle: lock.biometricAvailable
                          ? 'Unlock with fingerprint or face.'
                          : 'Not available on this device.',
                      icon: Icons.fingerprint_rounded,
                      value: lock.biometricEnabled,
                      onChanged: (v) async {
                        if (!lock.biometricAvailable) {
                          toast(context, 'Biometrics not available', error: true);
                          return;
                        }
                        await context.read<AppLockState>().setBiometric(v);
                        if (!context.mounted) return;
                        toast(context, v ? 'Biometrics enabled' : 'Biometrics disabled');
                      },
                    ),
                  ],
                ],
              ),
            ),
            if (lock.enabled) ...[
              const Gap(S.md),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: S.xxs, vertical: S.xxs),
                onTap: () async {
                  final current = await _promptCurrentPin(
                    context,
                    title: 'Change PIN',
                    subtitle: 'Enter your current PIN.',
                  );
                  if (current == null || !context.mounted) return;
                  final ok = await context.read<AppLockState>().verifyPin(current);
                  if (!context.mounted) return;
                  if (!ok) {
                    toast(context, 'Wrong PIN', error: true);
                    return;
                  }
                  final next = await _promptNewPin(context, title: 'Choose a new PIN');
                  if (next == null || !context.mounted) return;
                  try {
                    await context.read<AppLockState>().changePin(currentPin: current, newPin: next);
                    if (context.mounted) toast(context, 'PIN updated');
                  } catch (e) {
                    if (context.mounted) toast(context, e.toString(), error: true);
                  }
                },
                child: ListTile(
                  leading: Icon(Icons.pin_outlined, color: t.primary),
                  title: Text(
                    'Change PIN',
                    style: TextStyle(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w600,
                      color: t.foreground,
                    ),
                  ),
                  subtitle: Muted('${AppLockState.pinMin}–${AppLockState.pinMax} digits', size: 12),
                  trailing: Icon(Icons.chevron_right_rounded, color: t.mutedForeground),
                ),
              ),
              const Gap(S.md),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: S.xxs, vertical: S.xxs),
                onTap: () async {
                  await context.read<AppLockState>().lockNow();
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: ListTile(
                  leading: Icon(Icons.lock_rounded, color: t.primary),
                  title: Text(
                    'Lock now',
                    style: TextStyle(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w600,
                      color: t.foreground,
                    ),
                  ),
                  subtitle: const Muted('Immediately lock this session', size: 12),
                  trailing: Icon(Icons.chevron_right_rounded, color: t.mutedForeground),
                ),
              ),
            ],
            const Gap(S.lg),
            const InfoHint(
              label: 'Your PIN',
              body:
                  'Your PIN stays on this phone only. Santim never uploads it.',
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _promptNewPin(BuildContext context, {String title = 'Create a PIN'}) async {
  final first = await showPinSheet(
    context,
    title: title,
    subtitle: 'Choose ${AppLockState.pinMin}–${AppLockState.pinMax} digits.',
    confirmLabel: 'Continue',
  );
  if (first == null || !context.mounted) return null;
  final second = await showPinSheet(
    context,
    title: 'Confirm PIN',
    subtitle: 'Enter the same PIN again.',
    confirmLabel: 'Save',
  );
  if (second == null) return null;
  if (first != second) {
    if (context.mounted) toast(context, 'PINs do not match', error: true);
    return null;
  }
  return first;
}

Future<String?> _promptCurrentPin(
  BuildContext context, {
  required String title,
  required String subtitle,
}) {
  return showPinSheet(context, title: title, subtitle: subtitle, confirmLabel: 'Continue');
}

Future<String?> showPinSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String confirmLabel,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PinSheet(title: title, subtitle: subtitle, confirmLabel: confirmLabel),
  );
}

class _PinSheet extends StatefulWidget {
  const _PinSheet({required this.title, required this.subtitle, required this.confirmLabel});

  final String title;
  final String subtitle;
  final String confirmLabel;

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _controller.text.trim();
    final lock = context.read<AppLockState>();
    if (!lock.isValidPinFormat(pin)) {
      setState(() => _error = 'Use ${AppLockState.pinMin}–${AppLockState.pinMax} digits');
      return;
    }
    Navigator.pop(context, pin);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(S.xl, S.lg, S.xl, S.xl),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: t.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: TextStyle(
                fontSize: AppType.lead,
                fontWeight: FontWeight.w700,
                color: t.foreground,
              ),
            ),
            const Gap(S.xxs),
            Muted(widget.subtitle, size: 13),
            const Gap(S.lg),
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: AppLockState.pinMax,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                counterText: '',
                hintText: '••••',
                errorText: _error,
                filled: true,
                fillColor: t.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.md),
                  borderSide: BorderSide(color: t.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.md),
                  borderSide: BorderSide(color: t.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.md),
                  borderSide: BorderSide(color: t.primary, width: 1.4),
                ),
              ),
              onSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const Gap(S.md),
            AppButton(label: widget.confirmLabel, expand: true, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
