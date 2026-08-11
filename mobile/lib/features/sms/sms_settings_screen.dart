import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../state/sms_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';
import 'messaging_points_screen.dart';
import 'sms_balance_screen.dart';
import 'sms_import_sheet.dart';
import 'sms_sender_health_screen.dart';
import 'sms_setup_wizard.dart';

class SmsSettingsScreen extends StatefulWidget {
  const SmsSettingsScreen({super.key});

  @override
  State<SmsSettingsScreen> createState() => _SmsSettingsScreenState();
}

class _SmsSettingsScreenState extends State<SmsSettingsScreen> {
  final _previewSender = TextEditingController(text: 'CBE');
  final _previewBody = TextEditingController();
  String? _previewResult;
  bool _previewBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SmsState>().loadSenderRules();
    });
  }

  @override
  void dispose() {
    _previewSender.dispose();
    _previewBody.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final sms = context.watch<SmsState>();

    if (kIsWeb || !Platform.isAndroid) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bank SMS')),
        body: MeshBackground(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: EmptyState(
              icon: Icons.phone_android_rounded,
              title: 'Android only',
              description:
                  'Install the Santim APK on your phone to capture bank SMS. '
                  'This is not available on web or iOS.',
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Bank SMS',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.foreground),
        ),
      ),
      body: MeshBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 40),
          children: [
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Capture bank SMS', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  sms.isPaired
                      ? 'Live messages from approved senders upload as drafts'
                      : 'Pair this phone to start capturing',
                  style: TextStyle(fontSize: 12, color: t.mutedForeground),
                ),
                value: sms.captureEnabled && sms.isPaired,
                onChanged: sms.isPaired
                    ? (v) => sms.setCaptureEnabled(v)
                    : null,
              ),
            ),
            const SizedBox(height: 14),
            SectionLabel('DEVICE'),
            _Tile(
              icon: Icons.phonelink_setup_rounded,
              title: sms.isPaired ? (sms.devices.deviceName ?? 'Paired phone') : 'Not paired',
              subtitle: sms.isPaired
                  ? 'Token stored securely · ${sms.localPendingUploads} queued'
                  : 'Run setup to pair and grant SMS access',
              onTap: () => showSmsSetupWizard(context),
            ),
            if (sms.isPaired)
              _Tile(
                icon: Icons.link_off_rounded,
                title: 'Revoke this phone',
                subtitle: 'Stops uploads until you pair again',
                onTap: () async {
                  final ok = await confirm(
                    context,
                    title: 'Revoke device?',
                    message: 'The phone will stop uploading SMS until paired again.',
                    confirmLabel: 'Revoke',
                  );
                  if (!ok || !context.mounted) return;
                  await sms.revokeAndClear();
                  if (context.mounted) toast(context, 'Device revoked');
                },
              ),
            const SizedBox(height: 14),
            SectionLabel('MESSAGING'),
            _Tile(
              icon: Icons.cell_tower_rounded,
              title: 'Bank message sources',
              subtitle: sms.senderRules.isEmpty
                  ? 'Pick which SMS senders are banks and which wallet they fill'
                  : '${sms.senderRules.length} mapped · tap to edit wallet & digits',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MessagingPointsScreen()),
              ),
            ),
            if (sms.senderRules.isNotEmpty) ...[
              for (final r in sms.senderRules.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MessagingPointsScreen()),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          r.enabled ? Icons.sms_rounded : Icons.sms_failed_outlined,
                          size: 18,
                          color: r.enabled ? t.primary : t.mutedForeground,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.sender, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                              Muted(
                                [
                                  r.bankLabel ?? r.bankKey,
                                  if (r.account != null) '→ ${r.account!.name}',
                                  if (r.account == null) 'No wallet mapped',
                                ].join(' · '),
                                size: 11.5,
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: t.mutedForeground, size: 18),
                      ],
                    ),
                  ),
                ),
            ],
            _Tile(
              icon: Icons.balance_rounded,
              title: 'Balance SMS reconciliation',
              subtitle: 'Alert when bank-reported balance drifts from a wallet',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SmsBalanceScreen()),
              ),
            ),
            _Tile(
              icon: Icons.monitor_heart_outlined,
              title: 'Sender health',
              subtitle: 'Watch parser confidence and reparse after template changes',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SmsSenderHealthScreen()),
              ),
            ),
            _Tile(
              icon: Icons.history_rounded,
              title: 'Import history',
              subtitle: 'Backfill older bank messages',
              onTap: () => showSmsImportSheet(context),
            ),
            _Tile(
              icon: Icons.battery_saver_outlined,
              title: 'Battery exemption',
              subtitle: 'Keep capture alive in the background',
              onTap: () => sms.requestBatteryExemption(),
            ),
            const SizedBox(height: 14),
            SectionLabel('PRIVACY'),
            _Tile(
              icon: Icons.delete_sweep_outlined,
              title: 'Clear local SMS queue',
              subtitle: 'Removes unsent captures on this phone only',
              onTap: () async {
                await sms.clearLocalSmsOutbox();
                if (context.mounted) toast(context, 'Local queue cleared');
              },
            ),
            const SizedBox(height: 14),
            SectionLabel('PASTE PREVIEW'),
            AppTextField(
              controller: _previewSender,
              label: 'Sender',
            ),
            const SizedBox(height: 10),
            AppTextField(
              controller: _previewBody,
              label: 'Message body',
              maxLines: 4,
            ),
            const SizedBox(height: 10),
            AppButton(
              label: _previewBusy ? 'Parsing…' : 'Preview parse',
              expand: true,
              variant: BtnVariant.outline,
              onPressed: _previewBusy
                  ? null
                  : () async {
                      setState(() {
                        _previewBusy = true;
                        _previewResult = null;
                      });
                      try {
                        final json = await sms.preview(
                          sender: _previewSender.text.trim(),
                          body: _previewBody.text.trim(),
                        );
                        setState(() => _previewResult = json.toString());
                      } on ApiError catch (e) {
                        setState(() => _previewResult = e.message);
                      } finally {
                        if (mounted) setState(() => _previewBusy = false);
                      }
                    },
            ),
            if (_previewResult != null) ...[
              const SizedBox(height: 10),
              Text(_previewResult!, style: TextStyle(fontSize: 12, color: t.mutedForeground)),
            ],
            const SizedBox(height: 18),
            Muted(
              'Santim is distributed by direct APK install. Google Play does not '
              'allow expense apps to request SMS permission.',
              size: 11.5,
              height: 1.4,
              maxLines: 4,
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 19, color: t.mutedForeground),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  Muted(subtitle, size: 12, maxLines: 2),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: t.mutedForeground),
          ],
        ),
      ),
    );
  }
}
