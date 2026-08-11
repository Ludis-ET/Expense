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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final json = await context.read<ApiClient>().get<Map<String, dynamic>>(
        '/transactions',
        query: {
          'accountId': widget.account.id,
          'pageSize': 8,
          'sort': 'date_desc',
        },
      );
      if (!mounted) return;
      setState(() {
        _recent = TransactionPage.fromJson(json).items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
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
                if (a.isDefault || a.isShared || a.archived) ...[
                  const Gap(S.sm),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (a.isDefault)
                        AppBadge('Default', tone: BadgeTone.primary),
                      if (a.isShared) AppBadge('Shared', tone: BadgeTone.info),
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
