import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/formatting.dart';
import '../core/theme.dart';
import '../models/finance.dart';
import '../models/ingest.dart';
import '../state/auth_store.dart';
import '../state/capture_store.dart';
import '../state/data_store.dart';
import '../widgets/common.dart';
import '../widgets/sync_status.dart';
import 'capture/capture_setup_screen.dart';
import 'capture/cash_account_sheet.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();
    final capture = context.watch<CaptureStore>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          SectionCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    (auth.user?.name ?? auth.user?.email ?? '?')
                        .characters
                        .first
                        .toUpperCase(),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.user?.name ?? 'Signed in',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        auth.user?.email ?? '',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          SectionCard(
            title: 'Bank message capture',
            trailing: TextButton(
              onPressed: () => Navigator.of(context).push(
                santimRoute(const CaptureSetupScreen()),
              ),
              child: const Text('Manage'),
            ),
            child: Column(
              children: [
                _Line(
                  label: 'Status',
                  value: capture.native.healthy ? 'Running' : 'Not set up',
                  tone: capture.native.healthy ? PillTone.good : PillTone.warn,
                ),
                _Line(label: 'Approved senders', value: '${capture.native.senderCount}'),
                _Line(
                  label: 'Waiting to upload',
                  value: '${capture.native.queued}',
                  tone: capture.native.queued > 0 ? PillTone.warn : PillTone.neutral,
                ),
                _Line(label: 'Needs review', value: '${capture.needsReview}'),
                const Divider(height: 20),
                _CashAccountLine(),
              ],
            ),
          ),
          const SizedBox(height: 14),

          SectionCard(
            title: 'Paired phones',
            subtitle: 'Revoking a phone stops it forwarding messages immediately.',
            child: capture.devices.isEmpty
                ? Text(
                    'No phones paired yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Column(
                    children: [
                      for (final d in capture.devices) _DeviceRow(device: d),
                    ],
                  ),
          ),
          const SizedBox(height: 14),

          SectionCard(
            title: 'Offline & sync',
            subtitle: 'Edits made without signal wait here until the phone reconnects.',
            child: const PendingChangesPanel(),
          ),
          const SizedBox(height: 14),

          SectionCard(
            title: 'Server',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  auth.api.baseUrl,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => _editServer(context, auth),
                  child: const Text('Change server address'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          OutlinedButton.icon(
            onPressed: () => _confirmLogout(context, auth),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, AuthStore auth) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        // Worth stating plainly: signing out also unpairs, because leaving a
        // phone forwarding into an account nobody is watching would be worse.
        content: const Text(
          'This phone will stop capturing bank messages until you sign in and pair again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 40)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      context.read<DataStore>().reset();
      await auth.logout();
      if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  Future<void> _editServer(BuildContext context, AuthStore auth) async {
    final controller = TextEditingController(text: auth.api.baseUrl);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server address'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'http://192.168.1.10:4000/api/v1'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) await auth.setBaseUrl(result);
  }
}

/// Which wallet ATM withdrawals land in. Lives next to capture because that is
/// the only thing that uses it.
class _CashAccountLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cash = context.select<DataStore, Account?>((d) => d.cashAccount);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => CashAccountSheet.show(context),
      leading: Icon(
        Icons.local_atm,
        color: cash == null ? SantimTheme.warning : SantimTheme.income,
      ),
      title: const Text('Cash wallet', style: TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        cash == null
            ? 'Not set — ATM withdrawals cannot be recorded as transfers'
            : 'ATM withdrawals move into ${cash.name}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final PillTone? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (tone != null)
            StatusPill(label: value, tone: tone!)
          else
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device});

  final PairedDevice device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capture = context.read<CaptureStore>();

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.smartphone,
        color: device.revoked ? theme.disabledColor : SantimTheme.income,
      ),
      title: Text(
        device.name,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          decoration: device.revoked ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        device.revoked
            ? 'Revoked'
            : '${device.messageCount} forwarded · last seen ${Dates.relative(device.lastSeenAt)}',
      ),
      trailing: device.revoked
          ? null
          : TextButton(
              onPressed: () async {
                try {
                  await capture.revokeDevice(device.id);
                  if (context.mounted) showOk(context, 'Revoked');
                } on ApiException catch (e) {
                  if (context.mounted) showError(context, e.message);
                }
              },
              child: const Text('Revoke'),
            ),
    );
  }
}
