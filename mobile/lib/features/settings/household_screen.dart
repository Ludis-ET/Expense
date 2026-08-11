import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/layout.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';

/// `HouseholdPanel` — share chosen wallets with a partner. Nothing is shared
/// until a wallet is explicitly marked as such.
class HouseholdScreen extends StatefulWidget {
  const HouseholdScreen({super.key});

  @override
  State<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends State<HouseholdScreen> {
  HouseholdOverview? _household;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = context.read<ApiClient>();
      final json = await api.get<Map<String, dynamic>?>('/household');
      if (!mounted) return;
      setState(() {
        _household = json == null || json.isEmpty ? null : HouseholdOverview.fromJson(json);
        _loading = false;
        _error = null;
      });
      await context.read<DataState>().loadAccounts(force: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final prefs = context.watch<PrefsState>();
    final data = context.watch<DataState>();
    final h = _household;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Household',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.foreground),
        ),
      ),
      body: MeshBackground(
        showGrid: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: t.primary,
          backgroundColor: t.surface,
          child: ListView(
            padding: EdgeInsets.fromLTRB(14, 4, 14, ShellLayout.bottomClearance(context)),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (_loading && h == null)
                const PageLoader(rows: 3)
              else if (_error != null && h == null)
                ErrorState(
                  message: _error is ApiError
                      ? (_error as ApiError).message
                      : 'Could not load your household.',
                  onRetry: _load,
                )
              else if (h == null)
                EmptyState(
                  icon: Icons.group_outlined,
                  title: 'No household yet',
                  description: 'Create one to share chosen wallets with a partner. '
                      'Nothing is shared until you mark a wallet as shared.',
                  action: AppButton(
                    label: 'Create a household',
                    icon: Icons.add,
                    size: BtnSize.sm,
                    onPressed: () => _create(context),
                  ),
                )
              else ...[
                AppCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconTile(icon: Icons.home_outlined, color: t.primary, size: 44),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  h.name,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: t.foreground,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Muted(
                                  '${h.members.length} member'
                                  '${h.members.length == 1 ? '' : 's'} · you are '
                                  '${h.role == 'OWNER' ? 'the owner' : 'a partner'}',
                                  size: 11.5,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Muted('Shared balance', size: 11.5),
                          const Spacer(),
                          Amount(
                            prefs.money(h.sharedBalance, currency: data.activeCurrency),
                            size: 16,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                SectionLabel('MEMBERS'),
                for (final m in h.members)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                      child: Row(
                        children: [
                          Avatar(name: m.name, avatarId: m.avatarId, size: 38),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.isYou ? '${m.name} (you)' : m.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: t.foreground,
                                  ),
                                ),
                                Muted(m.email, size: 11.5, maxLines: 1),
                              ],
                            ),
                          ),
                          AppBadge(
                            m.role == 'OWNER' ? 'Owner' : 'Partner',
                            tone: m.role == 'OWNER' ? BadgeTone.primary : BadgeTone.neutral,
                            dense: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (h.pendingInvites > 0) ...[
                  const SizedBox(height: 4),
                  Muted('${h.pendingInvites} invite pending', size: 11.5),
                ],
                const SizedBox(height: 12),
                AppButton(
                  label: 'Invite someone',
                  icon: Icons.person_add_alt,
                  variant: BtnVariant.outline,
                  expand: true,
                  onPressed: () => _invite(context),
                ),
                const SizedBox(height: 20),

                SectionLabel('SHARED WALLETS'),
                Muted(
                  'Only the wallets you switch on here are visible to the rest '
                  'of the household.',
                  size: 11.5,
                  height: 1.4,
                ),
                const SizedBox(height: 10),
                AppCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      for (final a in data.scopedAccounts)
                        SwitchRow(
                          title: a.name,
                          subtitle: a.type.label,
                          icon: accountTypeIcon(a.type.wire),
                          value: a.isShared,
                          onChanged: (v) => _toggleShare(context, a, v),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                AppButton(
                  label: 'Leave household',
                  icon: Icons.logout_rounded,
                  variant: BtnVariant.ghost,
                  expand: true,
                  onPressed: () => _leave(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final name = TextEditingController();
    final saved = await showAppSheet<bool>(
      context,
      title: 'Create a household',
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.of(ctx).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: name,
              label: 'Name',
              placeholder: 'Our home',
              prefixIcon: Icons.home_outlined,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 20),
            AppButton(
              label: 'Create',
              expand: true,
              onPressed: () async {
                try {
                  await ctx.read<ApiClient>().post('/household', body: {
                    if (name.text.trim().isNotEmpty) 'name': name.text.trim(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on ApiError catch (e) {
                  if (ctx.mounted) toast(ctx, e.message, error: true);
                }
              },
            ),
          ],
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _invite(BuildContext context) async {
    final email = TextEditingController();
    await showAppSheet<void>(
      context,
      title: 'Invite someone',
      subtitle: 'They get an email with a link to join.',
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.of(ctx).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: email,
              label: 'Email',
              placeholder: 'partner@example.com',
              prefixIcon: Icons.alternate_email,
              keyboardType: TextInputType.emailAddress,
              textCapitalization: TextCapitalization.none,
              autofocus: true,
            ),
            const SizedBox(height: 20),
            AppButton(
              label: 'Send invite',
              icon: Icons.send_outlined,
              expand: true,
              onPressed: () async {
                try {
                  await ctx.read<ApiClient>().post(
                    '/household/invite',
                    body: {'email': email.text.trim()},
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) toast(context, 'Invite sent');
                  _load();
                } on ApiError catch (e) {
                  if (ctx.mounted) toast(ctx, e.message, error: true);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleShare(BuildContext context, Account account, bool shared) async {
    try {
      await context
          .read<ApiClient>()
          .put('/household/accounts/${account.id}/share', body: {'shared': shared});
      await _load();
      if (context.mounted) await context.read<DataState>().refreshAfterWrite();
    } on ApiError catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _leave(BuildContext context) async {
    final ok = await confirm(
      context,
      title: 'Leave this household?',
      message: 'Your wallets stop being visible to the others, and theirs to you.',
      confirmLabel: 'Leave',
    );
    if (!ok || !context.mounted) return;
    try {
      await context.read<ApiClient>().post('/household/leave');
      await _load();
      if (context.mounted) await context.read<DataState>().refreshAfterWrite();
    } on ApiError catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }
}
