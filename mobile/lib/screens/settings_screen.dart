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
import '../state/theme_controller.dart';
import '../widgets/common.dart';
import '../widgets/sync_status.dart';
import '../widgets/web_chrome.dart';
import 'capture/capture_setup_screen.dart';
import 'capture/cash_account_sheet.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _sections = [
    (id: 'profile', label: 'Profile', short: 'Profile', icon: Icons.person_outline_rounded),
    (id: 'appearance', label: 'Appearance', short: 'Look', icon: Icons.palette_outlined),
    (id: 'capture', label: 'Capture', short: 'SMS', icon: Icons.sms_outlined),
    (id: 'devices', label: 'Devices', short: 'Phone', icon: Icons.smartphone_outlined),
    (id: 'sync', label: 'Sync', short: 'Sync', icon: Icons.cloud_sync_outlined),
  ];

  final _keys = {
    for (final s in _sections) s.id: GlobalKey(),
  };

  String _active = 'profile';
  late final TextEditingController _name;
  String _currency = 'ETB';
  String _locale = 'en';
  String _calendar = 'gregorian';
  String _firstDay = '1';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthStore>().user;
    _name = TextEditingController(text: user?.name ?? '');
    _currency = user?.currency ?? 'ETB';
    _locale = user?.locale ?? 'en';
    _calendar = user?.calendar ?? 'gregorian';
    _firstDay = '${user?.firstDayOfWeek ?? 1}';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _scrollTo(String id) {
    setState(() => _active = id);
    final ctx = _keys[id]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      await context.read<AuthStore>().updateProfile({
        'name': _name.text.trim(),
        'currency': _currency,
        'locale': _locale,
        'calendar': _calendar,
        'firstDayOfWeek': int.tryParse(_firstDay) ?? 1,
      });
      if (mounted) showOk(context, 'Profile updated');
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();
    final capture = context.watch<CaptureStore>();
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          SoftCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colors.primary.withValues(alpha: 0.85),
                        colors.accent.withValues(alpha: 0.75),
                        const Color(0xFF115E59),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Transform.translate(
                        offset: const Offset(0, -28),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: UserAvatar(
                            name: user?.name ?? user?.email,
                            size: 64,
                            radius: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.name ?? 'Signed in',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                user?.email ?? '',
                                style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.border),
                          color: theme.colorScheme.surface.withValues(alpha: 0.7),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.payments_outlined, size: 14, color: colors.muted),
                            const SizedBox(width: 6),
                            Text('Default ', style: TextStyle(fontSize: 11, color: colors.muted)),
                            Text(_currency, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SoftCard(
            padding: const EdgeInsets.all(6),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final s in _sections)
                  InkWell(
                    onTap: () => _scrollTo(s.id),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 78,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _active == s.id ? colors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            s.icon,
                            size: 16,
                            color: _active == s.id ? theme.colorScheme.onPrimary : colors.muted,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s.short,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _active == s.id ? theme.colorScheme.onPrimary : colors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          _sectionHeader(context, key: _keys['profile']!, icon: Icons.person_outline_rounded, title: 'Profile'),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Full name'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _currency,
                        decoration: const InputDecoration(labelText: 'Default currency'),
                        items: [
                          for (final c in ['ETB', 'USD', 'EUR', 'GBP', 'KES', 'AED'])
                            DropdownMenuItem(value: c, child: Text(c)),
                        ],
                        onChanged: (v) => setState(() => _currency = v ?? _currency),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _locale,
                        decoration: const InputDecoration(labelText: 'Language'),
                        items: const [
                          DropdownMenuItem(value: 'en', child: Text('English')),
                          DropdownMenuItem(value: 'am', child: Text('አማርኛ')),
                          DropdownMenuItem(value: 'om', child: Text('Afaan Oromoo')),
                          DropdownMenuItem(value: 'ti', child: Text('ትግርኛ')),
                        ],
                        onChanged: (v) => setState(() => _locale = v ?? _locale),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _firstDay,
                        decoration: const InputDecoration(labelText: 'First day of week'),
                        items: const [
                          DropdownMenuItem(value: '1', child: Text('Monday')),
                          DropdownMenuItem(value: '0', child: Text('Sunday')),
                        ],
                        onChanged: (v) => setState(() => _firstDay = v ?? _firstDay),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _calendar,
                        decoration: const InputDecoration(labelText: 'Calendar'),
                        items: const [
                          DropdownMenuItem(value: 'gregorian', child: Text('Gregorian')),
                          DropdownMenuItem(value: 'ethiopian', child: Text('Ethiopian')),
                        ],
                        onChanged: (v) => setState(() => _calendar = v ?? _calendar),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _saveProfile,
                  child: Text(_saving ? 'Saving…' : 'Save changes'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          _sectionHeader(context, key: _keys['appearance']!, icon: Icons.palette_outlined, title: 'Appearance'),
          SoftCard(
            child: Builder(
              builder: (context) {
                final themeMode = context.watch<ThemeController>().mode;
                return Row(
                  children: [
                    for (final opt in [
                      (ThemeMode.light, 'Light', Icons.light_mode_outlined),
                      (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
                      (ThemeMode.system, 'System', Icons.computer_outlined),
                    ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: InkWell(
                            onTap: () => context.read<ThemeController>().setMode(opt.$1),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: themeMode == opt.$1 ? colors.primary : colors.border,
                                ),
                                color: themeMode == opt.$1 ? colors.primary.withValues(alpha: 0.05) : null,
                              ),
                              child: Column(
                                children: [
                                  Icon(opt.$3, color: themeMode == opt.$1 ? colors.primary : colors.muted),
                                  const SizedBox(height: 6),
                                  Text(
                                    opt.$2,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: themeMode == opt.$1 ? colors.primary : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 18),

          _sectionHeader(context, key: _keys['capture']!, icon: Icons.sms_outlined, title: 'Bank message capture'),
          SoftCard(
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
                const _CashAccountLine(),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(santimRoute(const CaptureSetupScreen())),
                  child: const Text('Manage capture'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          _sectionHeader(context, key: _keys['devices']!, icon: Icons.smartphone_outlined, title: 'Paired phones'),
          SoftCard(
            child: capture.devices.isEmpty
                ? Text('No phones paired yet.', style: TextStyle(color: colors.muted))
                : Column(children: [for (final d in capture.devices) _DeviceRow(device: d)]),
          ),
          const SizedBox(height: 18),

          _sectionHeader(context, key: _keys['sync']!, icon: Icons.cloud_sync_outlined, title: 'Offline & sync'),
          const SoftCard(child: PendingChangesPanel()),
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

  Widget _sectionHeader(
    BuildContext context, {
    required GlobalKey key,
    required IconData icon,
    required String title,
  }) {
    final colors = Theme.of(context).extension<SantimColors>()!;
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 16, color: colors.primary),
          ),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, AuthStore auth) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
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
}

class _CashAccountLine extends StatelessWidget {
  const _CashAccountLine();

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
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
