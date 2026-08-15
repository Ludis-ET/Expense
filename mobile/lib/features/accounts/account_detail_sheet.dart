import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../state/sync_state.dart';
import '../../widgets/ui.dart';
import '../budgets/budget_detail_screen.dart';
import '../shell/app_shell.dart';
import '../transactions/transaction_detail.dart';
import '../transactions/transaction_list.dart';
import 'account_form.dart';
import 'transfer_sheet.dart';

/// `AccountDetailModal`   the wallet's figures plus its recent movements.
Future<void> showAccountDetail(BuildContext context, Account account) {
  return showAppSheet<void>(
    context,
    title: account.name,
    subtitle: '${account.type.label} · ${account.currency}',
    builder: (ctx) => _AccountDetail(account: account),
  );
}

class _AccountDetail extends StatefulWidget {
  const _AccountDetail({required this.account});
  final Account account;

  @override
  State<_AccountDetail> createState() => _AccountDetailState();
}

class _AccountDetailState extends State<_AccountDetail> {
  List<Transaction>? _recent;
  List<WalletReservation>? _held;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    // The two halves of "what is in this wallet" load together: the movements
    // that made the balance, and the plans that have claimed part of it.
    final results = await Future.wait([
      api
          .get<Map<String, dynamic>>(
            '/transactions',
            query: {
              'accountId': widget.account.id,
              'pageSize': 8,
              'sort': 'date_desc',
            },
          )
          .then<Object?>((v) => v)
          .catchError((Object _) => null),
      api
          .get<Map<String, dynamic>>(
            '/accounts/${widget.account.id}/reservations',
          )
          .then<Object?>((v) => v)
          .catchError((Object _) => null),
    ]);
    if (!mounted) return;

    final txJson = results[0] as Map<String, dynamic>?;
    final heldJson = results[1] as Map<String, dynamic>?;

    setState(() {
      if (txJson != null) _recent = TransactionPage.fromJson(txJson).items;
      if (heldJson != null) {
        _held = (heldJson['items'] as List? ?? const [])
            .map(WalletReservation.maybe)
            .whereType<WalletReservation>()
            .toList();
      }
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final prefs = context.watch<PrefsState>();
    final a = widget.account;
    final tint = parseHexColor(a.color) ?? t.primary;

    String money(Object? v) =>
        prefs.money(v, currency: a.currency, decimals: true);
    String moneyIn(Object? v, String c) => prefs.money(v, currency: c);

    final locked = toNum(a.lockedAmount);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Column(
              children: [
                IconTile(
                  icon: a.icon != null
                      ? financeIcon(a.icon)
                      : accountTypeIcon(a.type.wire),
                  color: tint,
                  size: 56,
                  radius: R.lg,
                ),
                const Gap(S.md),
                Amount(money(a.balance), size: 30),
                const Gap(S.hair),
                Muted('available to spend', size: 12),
                // "Shared" is gone with the rest of the sharing UI - the flag
                // was written but never read, so it promised visibility that
                // did not exist.
                if (a.isDefault || a.archived) ...[
                  const Gap(S.sm),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (a.isDefault)
                        AppBadge('Default', tone: BadgeTone.primary),
                      if (a.archived)
                        AppBadge('Archived', tone: BadgeTone.neutral),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Gap(S.xl),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Real balance',
                  value: money(a.realBalance),
                ),
              ),
              const GapX(S.sm),
              Expanded(
                child: _Figure(
                  label: 'Set aside in plans',
                  value: money(a.lockedAmount),
                  color: locked > 0 ? t.primary : null,
                ),
              ),
            ],
          ),
          const Gap(S.sm),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Opening balance',
                  value: money(a.openingBalance),
                ),
              ),
              const GapX(S.sm),
              Expanded(
                child: _Figure(label: 'Currency', value: a.currency),
              ),
            ],
          ),

          // Who has claimed this wallet's money. The figure above says how
          // much; this says by whom, which is the half that can be acted on.
          if (locked > 0) ...[
            const Gap(S.xl),
            SectionLabel('SET ASIDE BY'),
            _HeldByPlans(
              account: a,
              held: _held,
              loading: _loading,
              money: money,
            ),
          ],

          const Gap(S.xl),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Transfer',
                  icon: Icons.swap_horiz_rounded,
                  variant: BtnVariant.outline,
                  expand: true,
                  onPressed: () async {
                    final done = await showTransferSheet(context, from: a);
                    if (done == true && context.mounted) {
                      await context.read<DataState>().refreshAfterWrite();
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                ),
              ),
              const GapX(S.sm),
              Expanded(
                child: AppButton(
                  label: 'Edit',
                  icon: Icons.edit_outlined,
                  variant: BtnVariant.outline,
                  expand: true,
                  onPressed: () async {
                    final saved = await showAccountForm(context, existing: a);
                    if (saved == true && context.mounted) {
                      await context.read<DataState>().refreshAfterWrite();
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                ),
              ),
            ],
          ),
          const Gap(S.xl),
          SectionLabel('RECENT MOVEMENTS'),
          if (_loading)
            const Column(
              children: [
                Skeleton(height: 54, radius: R.md),
                Gap(S.sm),
                Skeleton(height: 54, radius: R.md),
              ],
            )
          else if (_recent == null || _recent!.isEmpty)
            const EmptyState(title: 'Nothing yet in this wallet', compact: true)
          else
            AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: S.sm,
                vertical: S.xxs,
              ),
              child: TransactionList(
                items: _recent!,
                money: moneyIn,
                compact: true,
                onTap: (tx) async {
                  final changed = await showTransactionDetail(context, tx);
                  if (changed == true) _load();
                },
              ),
            ),
          const Gap(S.lg),
          AppButton(
            label: a.archived ? 'Delete wallet' : 'Archive wallet',
            icon: a.archived
                ? Icons.delete_outline
                : Icons.inventory_2_outlined,
            variant: BtnVariant.ghost,
            expand: true,
            onPressed: () => _archiveOrDelete(context),
          ),
        ],
      ),
    );
  }

  Future<void> _archiveOrDelete(BuildContext context) async {
    final a = widget.account;
    final sync = context.read<SyncState>();
    final data = context.read<DataState>();

    if (a.archived) {
      final ok = await confirm(
        context,
        title: 'Delete ${a.name}?',
        message:
            'This is permanent. Wallets with transactions cannot be deleted   '
            'archive them instead.',
      );
      if (!ok || !context.mounted) return;
      try {
        final result = await sync.deleteAccount(a.id, name: a.name);
        await data.refreshAfterWrite();
        if (context.mounted) {
          Navigator.pop(context);
          toast(
            context,
            result.queued
                ? 'Delete queued   will sync when you are back online'
                : 'Wallet deleted',
          );
        }
      } on ApiError catch (e) {
        if (context.mounted) toast(context, e.message, error: true);
      }
      return;
    }

    final ok = await confirm(
      context,
      title: 'Archive ${a.name}?',
      message:
          'It disappears from pickers and totals. Its history stays intact '
          'and you can bring it back any time.',
      confirmLabel: 'Archive',
      danger: false,
    );
    if (!ok || !context.mounted) return;
    try {
      final result = await sync.saveAccount(
        id: a.id,
        name: a.name,
        body: {'archived': true},
      );
      await data.refreshAfterWrite();
      if (context.mounted) {
        Navigator.pop(context);
        toast(
          context,
          result.queued
              ? 'Archive queued   will sync when you are back online'
              : 'Wallet archived',
        );
      }
    } on ApiError catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }
}

/// Which plans have claimed this wallet's money, and what is left over.
///
/// The stacked bar carries the proportions and the rows carry the figures, so
/// the section needs no sentence to explain itself. Tapping a plan opens it   a
/// wallet holding money you did not expect is normally something you want to
/// give back, and that button lives on the plan.
class _HeldByPlans extends StatelessWidget {
  const _HeldByPlans({
    required this.account,
    required this.held,
    required this.loading,
    required this.money,
  });

  final Account account;
  final List<WalletReservation>? held;
  final bool loading;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    if (loading && held == null) {
      return const Skeleton(height: 128, radius: R.card);
    }
    final rows = held ?? const <WalletReservation>[];
    if (rows.isEmpty) {
      // The wallet reports a hold but no plan claims it. That is a books
      // problem, not an empty state, and the Money Doctor is where it is fixed.
      return AppCard(
        prominence: Prominence.quiet,
        child: Row(
          children: [
            Icon(Icons.help_outline_rounded, size: 16, color: t.warning),
            const GapX(S.sm),
            Expanded(
              child: Muted(
                'No plan claims this. Run the Money Doctor in Settings.',
                size: AppType.caption,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    final free = toNum(account.balance);
    final real = toNum(account.realBalance);
    // Guard the divisor: an overdrawn wallet must still draw a sane bar.
    final total = real > 0 ? real : rows.fold<double>(0, (s, r) => s + toNum(r.amount));

    Color tintFor(int i) =>
        parseHexColor(rows[i].plan.color) ??
        [t.primary, t.accent, t.warning, t.danger][i % 4];

    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(R.pill),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  for (var i = 0; i < rows.length; i++)
                    Expanded(
                      flex: _flex(toNum(rows[i].amount), total),
                      child: Container(
                        color: tintFor(i),
                        margin: const EdgeInsets.only(right: 1.5),
                      ),
                    ),
                  if (free > 0)
                    Expanded(
                      flex: _flex(free, total),
                      child: Container(
                        color: t.surfaceMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const Gap(S.md),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Gap(S.xs),
            _HeldRow(
              tint: tintFor(i),
              icon: financeIcon(rows[i].plan.icon),
              label: rows[i].plan.name,
              badge: rows[i].closed ? 'closed' : null,
              amount: money(rows[i].amount),
              // Grab the shell before closing: once the sheet pops, this
              // context is on its way out and cannot route anything.
              onTap: () {
                final shell = AppShell.of(context);
                final planId = rows[i].plan.id;
                Navigator.pop(context);
                shell.push(BudgetDetailScreen(budgetId: planId));
              },
            ),
          ],
          if (free > 0) ...[
            const Gap(S.xs),
            _HeldRow(
              tint: t.surfaceMuted,
              icon: Icons.lock_open_rounded,
              label: 'Free to spend',
              amount: money(account.balance),
              hollow: true,
            ),
          ],
        ],
      ),
    );
  }

  /// Flex weights are integers, so tiny slices are floored to 1 rather than
  /// vanishing   a 20-birr hold should still be visible next to a 20,000 one.
  static int _flex(double value, double total) {
    if (total <= 0) return 1;
    return (value / total * 1000).round().clamp(1, 1000);
  }
}

class _HeldRow extends StatelessWidget {
  const _HeldRow({
    required this.tint,
    required this.icon,
    required this.label,
    required this.amount,
    this.badge,
    this.onTap,
    this.hollow = false,
  });

  final Color tint;
  final IconData icon;
  final String label;
  final String amount;
  final String? badge;
  final VoidCallback? onTap;
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: hollow ? null : tint,
                  border: hollow ? Border.all(color: t.border, width: 2) : null,
                  shape: BoxShape.circle,
                ),
              ),
              const GapX(S.sm),
              Icon(
                icon,
                size: 15,
                color: hollow ? t.mutedForeground : tint,
              ),
              const GapX(S.sm),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.bodySm,
                    fontWeight: hollow ? W.medium : W.semibold,
                    color: hollow ? t.mutedForeground : t.foreground,
                  ),
                ),
              ),
              if (badge != null) ...[
                const GapX(S.xs),
                AppBadge(badge!, tone: BadgeTone.neutral, dense: true),
              ],
              const GapX(S.sm),
              const Spacer(),
              Amount(
                amount,
                size: AppType.bodySm,
                color: hollow ? t.mutedForeground : null,
              ),
              if (onTap != null) ...[
                const GapX(S.xxs),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: t.mutedForeground,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.md),
      decoration: BoxDecoration(
        color: t.surfaceMuted.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Muted(label, size: 10.5, maxLines: 1),
          const Gap(S.xxs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Amount(value, size: 14.5, color: color),
          ),
        ],
      ),
    );
  }
}
