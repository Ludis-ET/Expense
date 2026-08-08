import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/native_ingest.dart';
import '../../core/theme.dart';
import '../../models/finance.dart';
import '../../state/capture_store.dart';
import '../../state/data_store.dart';
import '../../widgets/common.dart';
import 'cash_account_sheet.dart';
import 'import_range_sheet.dart';
import 'sender_picker_screen.dart';

/// Turns bank-SMS capture on, in the order the pieces actually depend on
/// each other: permission, then pairing, then which senders count, then
/// history, then the battery exemption that keeps it all alive.
class CaptureSetupScreen extends StatefulWidget {
  const CaptureSetupScreen({super.key});

  @override
  State<CaptureSetupScreen> createState() => _CaptureSetupScreenState();
}

class _CaptureSetupScreenState extends State<CaptureSetupScreen> {
  bool _smsGranted = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CaptureStore>().refreshNativeStatus();
    });
  }

  Future<void> _checkPermission() async {
    if (!Platform.isAndroid) return;
    final granted = await Permission.sms.isGranted;
    if (mounted) setState(() => _smsGranted = granted);
  }

  Future<void> _requestPermission() async {
    final status = await Permission.sms.request();
    if (!mounted) return;

    setState(() => _smsGranted = status.isGranted);
    if (status.isPermanentlyDenied) {
      showError(context, 'Enable SMS permission in Android settings to continue');
      await openAppSettings();
    }
  }

  Future<void> _pair() async {
    setState(() => _busy = true);
    try {
      await context.read<CaptureStore>().pairThisDevice(name: await _deviceLabel());
      if (mounted) showOk(context, 'This phone is paired');
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (_) {
      if (mounted) showError(context, 'Could not reach the server');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A human label for the devices list. Kept simple on purpose - the exact
  /// model name is not worth another dependency.
  Future<String> _deviceLabel() async => 'Android phone';

  Future<void> _openImport() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => const ImportRangeSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final capture = context.watch<CaptureStore>();
    final native = capture.native;
    final activeSenders = capture.senderRules.where((r) => r.enabled).length;
    final cashAccount = context.select<DataStore, Account?>((d) => d.cashAccount);

    return Scaffold(
      appBar: AppBar(title: const Text('Bank message capture')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          const _Explainer(),
          const SizedBox(height: 16),

          _Step(
            index: 1,
            title: 'Allow Santim to read SMS',
            body: 'Only messages from the banks you pick below are ever read. '
                'Everything else is discarded on the phone.',
            done: _smsGranted,
            action: _smsGranted
                ? null
                : FilledButton(onPressed: _requestPermission, child: const Text('Allow')),
          ),

          _Step(
            index: 2,
            title: 'Pair this phone',
            body: 'Gives this phone its own key so it can send transactions to your '
                'account. You can revoke it any time from Settings.',
            done: native.configured,
            action: native.configured
                ? null
                : FilledButton(
                    onPressed: _busy || !_smsGranted ? null : _pair,
                    child: const Text('Pair'),
                  ),
          ),

          _Step(
            index: 3,
            title: 'Choose your banks',
            body: activeSenders == 0
                ? 'Pick which senders on this phone are your banks.'
                : '$activeSenders sender(s) approved.',
            done: activeSenders > 0,
            action: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(120, 44)),
              onPressed: !_smsGranted || !native.configured
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SenderPickerScreen()),
                      ),
              child: Text(activeSenders == 0 ? 'Pick banks' : 'Edit'),
            ),
          ),

          _Step(
            index: 4,
            title: 'Say which wallet is cash',
            body: cashAccount == null
                ? 'Money out of an ATM has moved to your pocket, not been spent. Santim '
                    'needs to know where "your pocket" is.'
                : 'ATM withdrawals move into ${cashAccount.name}.',
            done: cashAccount != null,
            action: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(120, 44)),
              onPressed: () => CashAccountSheet.show(context),
              child: Text(cashAccount == null ? 'Choose' : 'Change'),
            ),
          ),

          _Step(
            index: 5,
            title: 'Import past messages',
            body: 'Optional. Everything from now on is captured automatically — this '
                'pulls in whatever came before. Pick any range you like.',
            done: native.lastImportedAt != null,
            action: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(120, 44)),
              onPressed: _busy || activeSenders == 0 ? null : _openImport,
              child: const Text('Choose range'),
            ),
          ),

          _Step(
            index: 6,
            title: 'Keep it running',
            body: 'Android battery saving can silently stop the uploader. This exempts '
                'Santim so queued transactions still get through.',
            done: native.batteryUnrestricted,
            action: native.batteryUnrestricted
                ? null
                : OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(120, 44)),
                    onPressed: () async {
                      await NativeIngest.requestBatteryExemption();
                      if (context.mounted) {
                        await context.read<CaptureStore>().refreshNativeStatus();
                      }
                    },
                    child: const Text('Allow'),
                  ),
          ),

          const SizedBox(height: 20),
          if (native.configured) _StatusPanel(status: native),
        ],
      ),
    );
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'How this works',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'When your bank texts you, Santim reads the amount out of it and puts a '
            'draft transaction in your inbox. You glance at it and tap once. Nothing '
            'is added to your ledger without you seeing it first.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.index,
    required this.title,
    required this.body,
    required this.done,
    this.action,
  });

  final int index;
  final String title;
  final String body;
  final bool done;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 30,
              width: 30,
              decoration: BoxDecoration(
                color: done
                    ? SantimTheme.income.withValues(alpha: 0.15)
                    : theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: done
                  ? const Icon(Icons.check, size: 17, color: SantimTheme.income)
                  : Center(
                      child: Text(
                        '$index',
                        style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (action != null) ...[const SizedBox(height: 12), action!],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live view of the native layer, so "is it actually working?" is answerable.
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.status});

  final IngestStatus status;

  @override
  Widget build(BuildContext context) {
    final capture = context.read<CaptureStore>();

    return SectionCard(
      title: 'Capture status',
      trailing: Switch(
        value: status.captureEnabled,
        onChanged: (v) => capture.setCaptureEnabled(v),
      ),
      child: Column(
        children: [
          _StatusRow(
            label: 'Listening for messages',
            ok: status.captureEnabled && status.senderCount > 0,
          ),
          _StatusRow(label: 'Battery restrictions lifted', ok: status.batteryUnrestricted),
          _StatusRow(
            label: status.queued == 0
                ? 'Nothing waiting to upload'
                : '${status.queued} message(s) waiting to upload',
            ok: status.queued == 0,
          ),
          if (status.queued > 0) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: capture.syncNow,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Send now'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error_outline,
            size: 17,
            color: ok ? SantimTheme.income : SantimTheme.warning,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
