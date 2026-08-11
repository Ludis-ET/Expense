import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/tokens.dart';
import '../../core/layout.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/auth_state.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../state/app_lock_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';
import 'ai_providers_screen.dart';
import 'categories_screen.dart';
import 'exchange_rates_screen.dart';
import 'household_screen.dart';
import '../lock/app_lock_settings_screen.dart';
import '../sms/sms_settings_screen.dart';
import '../update/app_update_sheet.dart';

/// Settings. Everything that shapes how the app behaves, grouped by what it
/// affects rather than by which endpoint owns it.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final auth = context.watch<AuthState>();
    final prefs = context.watch<PrefsState>();
    final data = context.watch<DataState>();
    final lock = context.watch<AppLockState>();
    final user = auth.user;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: TextStyle(
            fontSize: AppType.lead,
            fontWeight: FontWeight.w700,
            color: t.foreground,
          ),
        ),
      ),
      body: MeshBackground(
        showGrid: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            14,
            4,
            14,
            ShellLayout.bottomClearance(context),
          ),
          children: [
            FadeInUp(
              child: AppCard(
                padding: const EdgeInsets.all(S.lg),
                onTap: () => _editProfile(context),
                child: Row(
                  children: [
                    Avatar(
                      name: user?.name ?? '?',
                      avatarId: user?.avatarId,
                      size: 52,
                    ),
                    const GapX(S.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.name ?? '',
                            style: TextStyle(
                              fontSize: AppType.lead,
                              fontWeight: FontWeight.w700,
                              color: t.foreground,
                            ),
                          ),
                          const Gap(S.hair),
                          Muted(user?.email ?? '', size: 12.5, maxLines: 1),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: t.mutedForeground,
                    ),
                  ],
                ),
              ),
            ),
            const Gap(S.lg),

            SectionLabel('APPEARANCE'),
            AppCard(
              padding: const EdgeInsets.all(S.lg),
              child: Column(
                children: [
                  FieldShell(
                    label: 'Theme',
                    child: SegmentedTabs<ThemeMode>(
                      value: prefs.themeMode,
                      options: const [
                        ThemeMode.system,
                        ThemeMode.light,
                        ThemeMode.dark,
                      ],
                      labelOf: (m) => switch (m) {
                        ThemeMode.system => 'System',
                        ThemeMode.light => 'Light',
                        ThemeMode.dark => 'Dark',
                      },
                      iconOf: (m) => switch (m) {
                        ThemeMode.system => Icons.brightness_auto_outlined,
                        ThemeMode.light => Icons.light_mode_outlined,
                        ThemeMode.dark => Icons.dark_mode_outlined,
                      },
                      onChanged: prefs.setThemeMode,
                    ),
                  ),
                  const Gap(S.xs),
                  SwitchRow(
                    title: 'Hide amounts',
                    subtitle: 'Masks every figure until you tap the eye.',
                    icon: Icons.visibility_off_outlined,
                    value: prefs.amountsHidden,
                    onChanged: (_) => prefs.toggleAmounts(),
                  ),
                  SwitchRow(
                    title: 'Reduce motion',
                    subtitle:
                        'Turns off the drifting background and entrance animations.',
                    icon: Icons.motion_photos_off_outlined,
                    value: prefs.reduceMotion,
                    onChanged: prefs.setReduceMotion,
                  ),
                ],
              ),
            ),
            const Gap(S.lg),

            SectionLabel('MONEY'),
            _Tile(
              icon: Icons.sell_outlined,
              title: 'Categories',
              subtitle:
                  '${(data.categories.data ?? const <TxCategory>[]).length} in use',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CategoriesScreen()),
              ),
            ),
            _Tile(
              icon: Icons.currency_exchange,
              title: 'Exchange rates',
              subtitle: 'Needed to combine currencies into one total',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExchangeRatesScreen()),
              ),
            ),
            _Tile(
              icon: Icons.payments_outlined,
              title: 'Default currency',
              subtitle: user?.currency ?? 'ETB',
              onTap: () => _pickCurrency(context),
            ),
            _Tile(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Cash wallet',
              subtitle: _cashWalletName(data, user) ?? 'Not set',
              onTap: () => _pickCashWallet(context),
            ),
            const Gap(S.lg),

            SectionLabel('PEOPLE & AI'),
            _Tile(
              icon: Icons.group_outlined,
              title: 'Household',
              subtitle: 'Share wallets with a partner',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HouseholdScreen()),
              ),
            ),
            _Tile(
              icon: Icons.auto_awesome,
              title: 'AI providers',
              subtitle: 'Bring your own key for Ask Santim',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiProvidersScreen()),
              ),
            ),
            const Gap(S.lg),

            SectionLabel('APP'),
            _Tile(
              icon: Icons.lock_outline_rounded,
              title: 'App lock',
              subtitle: lock.enabled
                  ? (lock.biometricEnabled ? 'PIN + biometrics on' : 'PIN on')
                  : 'Off   protect your money privately',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AppLockSettingsScreen(),
                ),
              ),
            ),
            _Tile(
              icon: Icons.sms_rounded,
              title: 'Bank SMS',
              subtitle: 'Capture & review messaging points',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SmsSettingsScreen()),
              ),
            ),
            _Tile(
              icon: Icons.system_update_alt_rounded,
              title: 'Check for updates',
              subtitle: 'Download the latest Santim APK in-app',
              onTap: () => maybePromptAppUpdate(context, manual: true),
            ),
            _Tile(
              icon: Icons.calendar_today_outlined,
              title: 'Calendar',
              subtitle: 'Gregorian with Ethiopian alongside',
              onTap: null,
            ),
            const Gap(S.lg),

            AppButton(
              label: 'Sign out',
              icon: Icons.logout_rounded,
              variant: BtnVariant.outline,
              expand: true,
              onPressed: () async {
                final ok = await confirm(
                  context,
                  title: 'Sign out?',
                  message:
                      'You will need your email and password to get back in.',
                  confirmLabel: 'Sign out',
                );
                if (ok && context.mounted)
                  await context.read<AuthState>().logout();
              },
            ),
            const Gap(S.xl),
            Center(
              child: Column(
                children: [
                  const BrandMark(size: 34),
                  const Gap(S.sm),
                  Muted('Santim · version 1.0.0', size: 11),
                  const Gap(S.xxs),
                  Muted('Know where every birr goes', size: 11),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String? _cashWalletName(DataState data, User? user) {
    if (user?.cashAccountId == null) return null;
    return (data.accounts.data ?? const <Account>[])
        .where((a) => a.id == user!.cashAccountId)
        .firstOrNull
        ?.name;
  }

  static Future<void> _editProfile(BuildContext context) async {
    final auth = context.read<AuthState>();
    final name = TextEditingController(text: auth.user?.name ?? '');
    await showAppSheet<void>(
      context,
      title: 'Your profile',
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
              prefixIcon: Icons.person_outline,
              textCapitalization: TextCapitalization.words,
            ),
            const Gap(S.md),
            AppTextField(
              label: 'Email',
              placeholder: auth.user?.email ?? '',
              prefixIcon: Icons.alternate_email,
              enabled: false,
            ),
            const Gap(S.xl),
            AppButton(
              label: 'Save',
              expand: true,
              onPressed: () async {
                try {
                  await auth.updateProfile({'name': name.text.trim()});
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) toast(context, 'Profile updated');
                } on ApiError catch (e) {
                  if (context.mounted) toast(context, e.message, error: true);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _pickCurrency(BuildContext context) async {
    const currencies = ['ETB', 'USD', 'EUR', 'GBP', 'KES', 'AED'];
    final auth = context.read<AuthState>();
    final picked = await showAppSheet<String>(
      context,
      title: 'Default currency',
      subtitle: 'Used for new wallets and as the base for conversions.',
      scrollable: false,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: 16 + MediaQuery.of(ctx).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in currencies)
              ListTile(
                onTap: () => Navigator.pop(ctx, c),
                selected: c == auth.user?.currency,
                selectedTileColor: ctx.t.primary.withValues(alpha: 0.08),
                title: Text(
                  '$c · ${currencySymbol(c)}',
                  style: const TextStyle(fontSize: AppType.body),
                ),
                trailing: c == auth.user?.currency
                    ? Icon(Icons.check_circle, size: 20, color: ctx.t.primary)
                    : null,
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    try {
      await auth.updateProfile({'currency': picked});
      if (context.mounted) await context.read<DataState>().refreshAfterWrite();
    } on ApiError catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }

  static Future<void> _pickCashWallet(BuildContext context) async {
    final auth = context.read<AuthState>();
    final data = context.read<DataState>();
    await data.loadAccounts();
    if (!context.mounted) return;

    final picked = await showAppSheet<String>(
      context,
      title: 'Cash wallet',
      subtitle:
          'The wallet that holds physical cash. ATM withdrawals transfer into it.',
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: 16 + MediaQuery.of(ctx).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in data.scopedAccounts)
              ListTile(
                onTap: () => Navigator.pop(ctx, a.id),
                selected: a.id == auth.user?.cashAccountId,
                selectedTileColor: ctx.t.primary.withValues(alpha: 0.08),
                leading: IconTile(
                  icon: accountTypeIcon(a.type.wire),
                  color: parseHexColor(a.color),
                  size: 34,
                ),
                title: Text(
                  a.name,
                  style: const TextStyle(fontSize: AppType.body),
                ),
                trailing: a.id == auth.user?.cashAccountId
                    ? Icon(Icons.check_circle, size: 20, color: ctx.t.primary)
                    : null,
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    try {
      await auth.updateProfile({'cashAccountId': picked});
      if (context.mounted) toast(context, 'Cash wallet updated');
    } on ApiError catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
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
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.md),
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
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w600,
                      color: t.foreground,
                    ),
                  ),
                  const Gap(S.hair),
                  Muted(subtitle, size: 11.5, maxLines: 1),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, size: 19, color: t.mutedForeground),
          ],
        ),
      ),
    );
  }
}
