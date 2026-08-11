import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../widgets/sync_ui.dart';
import '../../widgets/ui.dart';
import 'account_detail_sheet.dart';
import 'account_form.dart';
import 'transfer_sheet.dart';

/// Wallets. Each card shows both figures the app cares about: the real balance
/// and what is left after budget plans have reserved their share.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DataState>().loadAccounts(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final data = context.watch<DataState>();
    final prefs = context.watch<PrefsState>();
    final currency = data.activeCurrency;

    final all = data.accounts.data ?? const <Account>[];
    final active = all.where((a) => !a.archived && a.currency == currency).toList();
    final archived = all.where((a) => a.archived && a.currency == currency).toList();
    final otherCurrencyCount =
        all.where((a) => !a.archived && a.currency != currency).length;

    final real = active.fold<double>(0, (s, a) => s + toNum(a.realBalance));
    final locked = active.fold<double>(0, (s, a) => s + toNum(a.lockedAmount));
    final available = active.fold<double>(0, (s, a) => s + toNum(a.balance));

    String money(Object? v) => prefs.money(v, currency: currency);

    return RefreshIndicator(
      onRefresh: () => data.loadAccounts(force: true),
      color: t.primary,
      backgroundColor: t.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 130),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          PageHeader(
            title: 'Wallets',
            description: 'Available is what is left after budget plans have '
                'reserved their share. Real is the money physically in the account.',
            action: IconPill(
              icon: Icons.add,
              tooltip: 'New wallet',
              onTap: () => _create(context),
            ),
          ),
          const OfflineBanner(),

          if (!data.accounts.hasData) ...[
            if (data.accounts.hasError)
              ErrorState(
                message: data.accounts.errorMessage,
                onRetry: () => data.loadAccounts(force: true),
              )
            else
              const PageLoader(rows: 4),
          ] else ...[
            FadeInUp(
              child: GradientHero(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.account_balance_wallet_rounded,
                            size: 16, color: Colors.white.withValues(alpha: 0.75)),
                        const SizedBox(width: 6),
                        Text(
                          'AVAILABLE  ·  $currency',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AnimatedNumber(
                      value: available,
                      builder: (context, v) => FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          money(v),
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.4,
                            height: 1.1,
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _HeroFigure(
                            label: 'Real balance',
                            value: money(real),
                            icon: Icons.account_balance_rounded,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _HeroFigure(
                            label: 'In plans',
                            value: money(locked),
                            icon: Icons.savings_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _HeroAction(
                            label: 'Transfer',
                            icon: Icons.swap_horiz_rounded,
                            onTap: () => _transfer(context),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _HeroAction(
                            label: 'Add wallet',
                            icon: Icons.add_rounded,
                            onTap: () => _create(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            if (active.isEmpty && otherCurrencyCount > 0)
              AppCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.currency_exchange_rounded, size: 18, color: t.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You have $otherCurrencyCount wallet${otherCurrencyCount == 1 ? '' : 's'} '
                        'in another currency. Switch the currency badge in the top bar.',
                        style: TextStyle(fontSize: 12.5, height: 1.4, color: t.foreground),
                      ),
                    ),
                  ],
                ),
              ),

            if (active.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 2),
                child: Row(
                  children: [
                    Text(
                      'Your wallets',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.foreground,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: t.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(R.pill),
                      ),
                      child: Text(
                        '${active.length}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: t.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              for (var i = 0; i < active.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FadeInUp.staggered(
                    index: i,
                    child: AccountCard(
                      account: active[i],
                      money: money,
                      onTap: () => showAccountDetail(context, active[i]),
                    ),
                  ),
                ),
            ] else if (otherCurrencyCount == 0)
              EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: 'No $currency wallets yet',
                description: 'Add the accounts you actually keep money in — '
                    'cash, a bank account, mobile money.',
                action: AppButton(
                  label: 'Add a wallet',
                  icon: Icons.add,
                  size: BtnSize.sm,
                  onPressed: () => _create(context),
                ),
              ),

            if (archived.isNotEmpty) ...[
              const SizedBox(height: 8),
              SectionLabel('ARCHIVED'),
              for (final a in archived)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Opacity(
                    opacity: 0.55,
                    child: AccountCard(
                      account: a,
                      money: money,
                      onTap: () => showAccountDetail(context, a),
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  static Future<void> _create(BuildContext context) async {
    final created = await showAccountForm(context);
    if (created == true && context.mounted) {
      await context.read<DataState>().refreshAfterWrite();
    }
  }

  static Future<void> _transfer(BuildContext context) async {
    final done = await showTransferSheet(context);
    if (done == true && context.mounted) {
      await context.read<DataState>().refreshAfterWrite();
    }
  }
}

class _HeroFigure extends StatelessWidget {
  const _HeroFigure({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return GlassChip(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: Colors.white.withValues(alpha: 0.6)),
              const SizedBox(width: 5),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: Colors.white.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      scale: 0.96,
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.9)),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.95),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One wallet: type icon in the account's colour, both balances, and a bar
/// showing how much of it is locked away in plans.
class AccountCard extends StatelessWidget {
  const AccountCard({
    super.key,
    required this.account,
    required this.money,
    this.onTap,
  });

  final Account account;
  final String Function(Object?) money;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final tint = parseHexColor(account.color) ?? t.primary;
    final real = toNum(account.realBalance);
    final locked = toNum(account.lockedAmount);
    final lockedPct = real <= 0 ? 0.0 : (locked / real * 100).clamp(0.0, 100.0);

    final icon = financeIcon(account.icon) == Icons.circle_outlined
        ? accountTypeIcon(account.type.wire)
        : financeIcon(account.icon);

    return AppCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 15, 16, 15),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(R.md),
                    border: Border.all(color: tint.withValues(alpha: 0.2)),
                  ),
                  child: Icon(icon, size: 22, color: tint),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              account.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: t.foreground,
                              ),
                            ),
                          ),
                          if (account.isDefault) ...[
                            const SizedBox(width: 6),
                            AppBadge('Default', tone: BadgeTone.primary, dense: true),
                          ],
                          if (account.isShared) ...[
                            const SizedBox(width: 6),
                            AppBadge('Shared', tone: BadgeTone.info, dense: true),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: tint.withValues(alpha: 0.7),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Muted('${account.type.label} · ${account.currency}', size: 11.5),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Amount(money(account.balance), size: 17),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline_rounded,
                            size: 10, color: t.mutedForeground),
                        const SizedBox(width: 3),
                        Muted('available', size: 10),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, size: 18, color: t.mutedForeground.withValues(alpha: 0.5)),
              ],
            ),
          ),
          if (locked > 0) ...[
            Divider(height: 1, color: t.border.withValues(alpha: 0.5), indent: 14, endIndent: 14),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 13),
              child: Column(
                children: [
                  ProgressBar(value: lockedPct, height: 4, tone: BadgeTone.info),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.account_balance_rounded, size: 10, color: t.mutedForeground),
                          const SizedBox(width: 4),
                          Muted(money(real), size: 11),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline_rounded, size: 10, color: t.mutedForeground),
                          const SizedBox(width: 4),
                          Muted('${money(locked)} in plans', size: 11),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
