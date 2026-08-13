import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme.dart';

import '../../core/api/api_client.dart';
import '../../core/layout.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../models/ingest.dart';
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
      final sms = context.read<SmsState>();
      sms.loadSenderRules();
      sms.loadDevices();
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
            padding: const EdgeInsets.all(S.xl),
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
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        foregroundColor: t.foreground,
        title: Text(
          'Bank SMS',
          style: TextStyle(
            fontSize: AppType.lead,
            fontWeight: FontWeight.w700,
            color: t.foreground,
          ),
        ),
      ),
      body: MeshBackground(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            14,
            8,
            14,
            ShellLayout.pageClearance(context),
          ),
          children: [
            GlassCard(
              padding: const EdgeInsets.all(S.lg),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Capture bank SMS',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: t.foreground,
                  ),
                ),
                subtitle: Text(
                  sms.isPaired
                      ? 'Live messages from approved senders upload as drafts'
                      : 'Pair this phone to start capturing',
                  style: TextStyle(
                    fontSize: AppType.label,
                    color: t.mutedForeground,
                  ),
                ),
                value: sms.captureEnabled && sms.isPaired,
                onChanged: sms.isPaired
                    ? (v) => sms.setCaptureEnabled(v)
                    : null,
              ),
            ),
            const Gap(S.md),
            SectionLabel('THIS PHONE'),
            _Tile(
              icon: Icons.phonelink_setup_rounded,
              title: sms.isPaired
                  ? (sms.devices.deviceName ?? 'This phone')
                  : 'Not paired',
              subtitle: sms.isPaired
                  ? 'Capturing here · ${sms.localPendingUploads} queued'
                  : 'Run setup to pair and grant SMS access',
              onTap: () => showSmsSetupWizard(context),
            ),
            if (sms.isPaired)
              _Tile(
                icon: Icons.link_off_rounded,
                title: 'Unlink this phone',
                subtitle:
                    'Stops uploads from this handset until you pair again',
                onTap: () async {
                  final ok = await confirm(
                    context,
                    title: 'Unlink this phone?',
                    message:
                        'This phone will stop uploading SMS until paired again.',
                    confirmLabel: 'Unlink',
                  );
                  if (!ok || !context.mounted) return;
                  await sms.revokeAndClear();
                  if (context.mounted) toast(context, 'Phone unlinked');
                },
              ),
            const Gap(S.md),
            SectionLabel('LINKED PHONES'),
            if (sms.loadingDevices && sms.pairedDevices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: S.md),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (sms.pairedDevices.where((d) => !d.revoked).isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: S.sm),
                child: AppCard(
                  padding: const EdgeInsets.all(S.lg),
                  child: Muted(
                    'No active phones yet. Pair this device, or set up another phone with the same Santim account.',
                    size: 12.5,
                    maxLines: 4,
                  ),
                ),
              )
            else
              for (final d in sms.pairedDevices.where((d) => !d.revoked))
                _DeviceCard(
                  device: d,
                  isThisPhone: d.id == sms.devices.deviceId,
                  onRevoke: () async {
                    final ok = await confirm(
                      context,
                      title: d.id == sms.devices.deviceId
                          ? 'Unlink this phone?'
                          : 'Revoke ${d.name}?',
                      message: d.id == sms.devices.deviceId
                          ? 'This phone will stop uploading until paired again.'
                          : 'That phone will stop uploading bank SMS.',
                      confirmLabel: 'Revoke',
                    );
                    if (!ok || !context.mounted) return;
                    try {
                      await sms.revokeDevice(d.id);
                      if (context.mounted) toast(context, 'Device revoked');
                    } on ApiError catch (e) {
                      if (context.mounted)
                        toast(context, e.message, error: true);
                    }
                  },
                ),
            _Tile(
              icon: Icons.add_to_home_screen_rounded,
              title: sms.isPaired ? 'Re-pair this phone' : 'Pair another phone',
              subtitle: sms.isPaired
                  ? 'Creates a fresh token for this handset'
                  : 'Each phone needs its own setup on that device',
              onTap: () => showSmsSetupWizard(context),
            ),
            const Gap(S.md),
            SectionLabel('MESSAGING'),
            _Tile(
              icon: Icons.cell_tower_rounded,
              title: 'Bank message sources',
              subtitle: sms.senderRules.isEmpty
                  ? 'Link SMS senders to wallets (accounts) and categories'
                  : '${sms.senderRules.length} mapped · tap to edit wallet & digits',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MessagingPointsScreen(),
                ),
              ),
            ),
            if (sms.senderRules.isNotEmpty) ...[
              for (final r in sms.senderRules.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: S.sm),
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: S.lg,
                      vertical: S.md,
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MessagingPointsScreen(),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          r.enabled
                              ? Icons.sms_rounded
                              : Icons.sms_failed_outlined,
                          size: 18,
                          color: r.enabled ? t.primary : t.mutedForeground,
                        ),
                        const GapX(S.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.sender,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppType.bodySm,
                                  color: t.foreground,
                                ),
                              ),
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
                        Icon(
                          Icons.chevron_right_rounded,
                          color: t.mutedForeground,
                          size: 18,
                        ),
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
              subtitle:
                  'Watch parser confidence and reparse after template changes',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SmsSenderHealthScreen(),
                ),
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
            const Gap(S.md),
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
            const Gap(S.md),
            SectionLabel('PASTE PREVIEW'),
            AppTextField(controller: _previewSender, label: 'Sender'),
            const Gap(S.sm),
            AppTextField(
              controller: _previewBody,
              label: 'Message body',
              maxLines: 4,
            ),
            const Gap(S.sm),
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
              const Gap(S.sm),
              Text(
                _previewResult!,
                style: TextStyle(
                  fontSize: AppType.label,
                  color: t.mutedForeground,
                ),
              ),
            ],
            const Gap(S.lg),
            const InfoHint(
              label: 'Why pair phones',
              body:
                  'Santim is distributed by direct APK install. Google Play does not '
                  'allow expense apps to request SMS permission. Pair each phone you '
                  'want to capture from — they all share the same inbox and wallet mappings.',
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.isThisPhone,
    required this.onRevoke,
  });

  final PairedDevice device;
  final bool isThisPhone;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.sm),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.md),
        child: Row(
          children: [
            Icon(
              isThisPhone
                  ? Icons.smartphone_rounded
                  : Icons.phone_android_rounded,
              size: 20,
              color: isThisPhone ? t.primary : t.mutedForeground,
            ),
            const GapX(S.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: AppType.body,
                      color: t.foreground,
                    ),
                  ),
                  Muted(
                    [
                      if (isThisPhone) 'This phone',
                      device.platform,
                      if (device.lastSeenAt != null)
                        'Seen ${formatDate(device.lastSeenAt)}',
                      '${device.messageCount} msgs',
                    ].join(' · '),
                    size: 11.5,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onRevoke,
              style: TextButton.styleFrom(foregroundColor: t.danger),
              child: Text(
                isThisPhone ? 'Unlink' : 'Revoke',
                style: const TextStyle(fontSize: AppType.label),
              ),
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
      padding: const EdgeInsets.only(bottom: S.sm),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.md),
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 19, color: t.mutedForeground),
            const GapX(S.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: AppType.body,
                      color: t.foreground,
                    ),
                  ),
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
