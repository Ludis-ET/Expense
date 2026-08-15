import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/layout.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';

/// `HouseholdPanel`   share chosen wallets with a partner. Nothing is shared
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
        _household = json == null || json.isEmpty
            ? null
            : HouseholdOverview.fromJson(json);
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
          style: TextStyle(
            fontSize: AppType.lead,
            fontWeight: FontWeight.w700,
            color: t.foreground,
          ),
        ),
      ),
      body: MeshBackground(
        showGrid: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: t.primary,
          backgroundColor: t.surface,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              14,
              4,
              14,
              ShellLayout.bottomClearance(context),
            ),
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
                  description:
                      'Create one to share chosen wallets with a partner. '
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
                  padding: const EdgeInsets.all(S.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconTile(
                            icon: Icons.home_outlined,
                            color: t.primary,
                            size: 44,
                          ),
                          const GapX(S.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  h.name,
                                  style: TextStyle(
                                    fontSize: AppType.lead,
                                    fontWeight: FontWeight.w700,
                                    color: t.foreground,
                                  ),
                                ),
                                const Gap(S.hair),
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
                      const Gap(S.lg),
                      Row(
                        children: [
                          Muted('Shared balance', size: 11.5),
                          const Spacer(),
                          Amount(
                            prefs.money(
                              h.sharedBalance,
                              currency: data.activeCurrency,
                            ),
                            size: 16,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Gap(S.lg),

                SectionLabel('MEMBERS'),
                for (final m in h.members)
                  Padding(
                    padding: const EdgeInsets.only(bottom: S.md),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: S.md,
                        vertical: S.md,
                      ),
                      child: Row(
                        children: [
                          Avatar(name: m.name, avatarId: m.avatarId, size: 38),
                          const GapX(S.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.isYou ? '${m.name} (you)' : m.name,
                                  style: TextStyle(
                                    fontSize: AppType.body,
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
                            tone: m.role == 'OWNER'
                                ? BadgeTone.primary
                                : BadgeTone.neutral,
                            dense: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (h.pendingInvites > 0) ...[
                  const Gap(S.xxs),
                  Muted('${h.pendingInvites} invite pending', size: 11.5),
                ],
                const Gap(S.md),
                AppButton(
                  label: 'Invite someone',
                  icon: Icons.person_add_alt,
                  variant: BtnVariant.outline,
                  expand: true,
                  onPressed: () => _invite(context),
                ),
                const Gap(S.xl),

                // The per-wallet share switches lived here. They wrote a
                // householdId that no read path in the app has ever consulted,
                // so a wallet marked shared was visible to precisely nobody
                // while the UI insisted otherwise. Saying so is better than a
                // control that does nothing.
                SectionLabel('SHARED WALLETS'),
                const Gap(S.sm),
                AppCard(
                  prominence: Prominence.quiet,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.construction_rounded,
                        size: 16,
                        color: context.t.warning,
                      ),
                      const GapX(S.sm),
                      Expanded(
                        child: Muted(
                          'Not built yet. Members can see each other here, but '
                          'balances stay private to whoever owns them.',
                          size: AppType.caption,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(S.xl),
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
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          24 + MediaQuery.of(ctx).padding.bottom,
        ),
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
            const Gap(S.xl),
            AppButton(
              label: 'Create',
              expand: true,
              onPressed: () async {
                try {
                  await ctx.read<ApiClient>().post(
                    '/household',
                    body: {
                      if (name.text.trim().isNotEmpty) 'name': name.text.trim(),
                    },
                  );
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
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          24 + MediaQuery.of(ctx).padding.bottom,
        ),
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
            const Gap(S.xl),
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

  Future<void> _leave(BuildContext context) async {
    final ok = await confirm(
      context,
      title: 'Leave this household?',
      message: 'You will no longer see the other members, or they you.',
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
