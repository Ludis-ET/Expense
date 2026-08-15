import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../state/sync_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/money_delta.dart';
import '../../widgets/ui.dart';

/// Moving reserved money without unreserving it first.
///
/// Both halves of this existed on the server and neither had a way in, so the
/// only route between two plans was give-back-then-refill   two movements in
/// the history for one intention, and a window in between where the money
/// looked spendable.
///
/// The two directions are genuinely different and the segmented control says
/// which is which:
///
/// * **To a plan**   the money changes owner. This pot down, that pot up.
/// * **To a wallet**   the same plan keeps the money, but a different wallet
///   backs it. Used when the cash itself has moved and the envelope has to
///   follow it.
enum MoveKind { toPlan, toWallet }

Future<bool?> showMoveSheet(
  BuildContext context, {
  required BudgetDetail detail,
}) {
  return showAppSheet<bool>(
    context,
    title: 'Move money',
    subtitle: 'Out of "${detail.row.name}", without freeing it first.',
    builder: (ctx) => _MoveSheet(detail: detail),
  );
}

class _MoveSheet extends StatefulWidget {
  const _MoveSheet({required this.detail});
  final BudgetDetail detail;

  @override
  State<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<_MoveSheet> {
  final _amount = TextEditingController();

  MoveKind _kind = MoveKind.toPlan;
  String? _toBudgetId;
  String? _fromAccountId;
  String? _toAccountId;
  bool _raiseTarget = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount.addListener(_onTyped);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final data = context.read<DataState>();
      await Future.wait([data.loadAccounts(), data.loadBudgets()]);
      if (!mounted) return;
      // Default to the wallet holding the largest share   the one a move is
      // most likely to be about.
      final sources = [...widget.detail.sources]
        ..sort((a, b) => toNum(b.available).compareTo(toNum(a.available)));
      setState(() => _fromAccountId = sources.firstOrNull?.account?.id);
    });
  }

  void _onTyped() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _amount.removeListener(_onTyped);
    _amount.dispose();
    super.dispose();
  }

  /// Plans that can actually receive this money: same currency, open, not this
  /// one, and not the catch-all   Unplanned has no pot to move into.
  List<BudgetRow> _targets(DataState data) {
    final b = widget.detail.row;
    return (data.budgets.data?.items ?? const <BudgetRow>[])
        .where(
          (p) =>
              p.id != b.id &&
              !p.isUnplanned &&
              !p.isClosed &&
              p.currency == b.currency,
        )
        .toList();
  }

  Future<void> _submit() async {
    final b = widget.detail.row;
    final data = context.read<DataState>();
    final sync = context.read<SyncState>();
    final amount = double.tryParse(_amount.text.trim());

    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (_kind == MoveKind.toPlan) {
        final target = _targets(data).where((p) => p.id == _toBudgetId).firstOrNull;
        if (target == null) {
          setState(() {
            _saving = false;
            _error = 'Pick the plan the money is going to.';
          });
          return;
        }
        await sync.movePlanMoney(
          fromBudgetId: b.id,
          toBudgetId: target.id,
          amount: amount,
          label: '${b.name} → ${target.name}',
          raiseTarget: _raiseTarget,
        );
      } else {
        if (_fromAccountId == null || _toAccountId == null) {
          setState(() {
            _saving = false;
            _error = 'Pick both wallets.';
          });
          return;
        }
        await sync.movePlanHolding(
          budgetId: b.id,
          fromAccountId: _fromAccountId!,
          toAccountId: _toAccountId!,
          amount: amount,
          planName: b.name,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final data = context.watch<DataState>();
    final b = widget.detail.row;
    final typed = double.tryParse(_amount.text.trim()) ?? 0;

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
          SegmentedTabs<MoveKind>(
            value: _kind,
            options: MoveKind.values,
            labelOf: (k) =>
                k == MoveKind.toPlan ? 'To a plan' : 'To a wallet',
            iconOf: (k) => k == MoveKind.toPlan
                ? Icons.savings_outlined
                : Icons.account_balance_wallet_outlined,
            onChanged: (k) => setState(() {
              _kind = k;
              _error = null;
            }),
          ),
          const Gap(S.lg),
          AmountField(
            controller: _amount,
            currency: b.currency,
            tint: t.accent,
            autofocus: true,
          ),
          const Gap(S.lg),
          if (_kind == MoveKind.toPlan)
            ..._toPlanFields(data, typed)
          else
            ..._toWalletFields(data, typed),
          if (_error != null) ...[
            const Gap(S.md),
            _ErrorNote(message: _error!),
          ],
          const Gap(S.xl),
          AppButton(
            label: 'Move money',
            icon: Icons.swap_horiz_rounded,
            size: BtnSize.lg,
            expand: true,
            loading: _saving,
            onPressed: _saving ? null : _submit,
          ),
        ],
      ),
    );
  }

  // ─── Plan → plan ───────────────────────────────────────────────────────────

  List<Widget> _toPlanFields(DataState data, double typed) {
    final t = context.t;
    final b = widget.detail.row;
    final targets = _targets(data);
    final target = targets.where((p) => p.id == _toBudgetId).firstOrNull;

    if (targets.isEmpty) {
      return [
        EmptyState(
          art: EmptyArt.plan,
          title: 'Nowhere to move it',
          description:
              'You have no other open ${b.currency} plan. Give the money back '
              'to a wallet instead.',
          compact: true,
        ),
      ];
    }

    // The receiving plan has a ceiling of its own. Overshooting it is allowed,
    // but only as a deliberate raise the user opts into.
    final room = target == null ? 0.0 : toNum(target.fillable);
    final overshoot = target != null && typed > room;

    return [
      PickerField<BudgetRow>(
        label: 'Move into',
        value: target,
        options: targets,
        labelOf: (p) => p.name,
        subtitleOf: (p) =>
            '${formatMoney(p.fillable, currency: p.currency)} of room',
        iconOf: (p) => financeIcon(p.icon),
        colorOf: (p) => parseHexColor(p.color) ?? t.primary,
        onChanged: (p) => setState(() {
          _toBudgetId = p?.id;
          _raiseTarget = false;
        }),
      ),
      const Gap(S.lg),
      MoneyImpact(
        warning: typed > toNum(b.balance)
            ? '"${b.name}" only holds '
                  '${formatMoney(b.balance, currency: b.currency)}.'
            : (overshoot && !_raiseTarget
                  ? 'That is more than "${target.name}" can hold. Raise it, or '
                        'move less.'
                  : null),
        rows: [
          MoneyDelta(
            label: b.name,
            caption: 'in the pot',
            currency: b.currency,
            before: toNum(b.balance),
            after: toNum(b.balance) - typed,
            icon: financeIcon(b.icon),
            color: parseHexColor(b.color) ?? t.mutedForeground,
          ),
          if (target != null)
            MoneyDelta(
              label: target.name,
              caption: 'in the pot',
              currency: target.currency,
              before: toNum(target.balance),
              after: toNum(target.balance) + typed,
              icon: financeIcon(target.icon),
              color: parseHexColor(target.color) ?? t.primary,
            ),
        ],
      ),
      if (overshoot) ...[
        const Gap(S.md),
        SwitchRow(
          value: _raiseTarget,
          onChanged: (v) => setState(() => _raiseTarget = v),
          icon: Icons.trending_up_rounded,
          title: 'Raise "${target.name}" to fit',
          subtitle:
              'Adds ${formatMoney(typed - room, currency: target.currency)} to '
              'its plan amount, as a raise you can undo.',
        ),
      ],
    ];
  }

  // ─── Wallet → wallet, same plan ────────────────────────────────────────────

  List<Widget> _toWalletFields(DataState data, double typed) {
    final t = context.t;
    final b = widget.detail.row;

    final holders = widget.detail.sources
        .where((s) => s.account != null && toNum(s.available) > 0)
        .toList();
    if (holders.isEmpty) {
      return [
        EmptyState(
          art: EmptyArt.wallet,
          title: 'Nothing held yet',
          description: 'Put money in this plan first.',
          compact: true,
        ),
      ];
    }

    final wallets = data.scopedAccounts
        .where((a) => a.currency == b.currency)
        .toList();
    final held = holders.where((s) => s.account!.id == _fromAccountId).firstOrNull;
    final from = wallets.where((a) => a.id == _fromAccountId).firstOrNull;
    final to = wallets.where((a) => a.id == _toAccountId).firstOrNull;

    return [
      PickerField<BudgetSource>(
        label: 'Held in',
        value: held,
        options: holders,
        labelOf: (s) => s.account!.name,
        subtitleOf: (s) =>
            '${formatMoney(s.available, currency: b.currency)} held here',
        iconOf: (s) => accountTypeIcon(s.account!.type ?? 'OTHER'),
        colorOf: (s) => parseHexColor(s.account!.color) ?? t.mutedForeground,
        onChanged: (s) => setState(() {
          _fromAccountId = s?.account?.id;
          if (_toAccountId == _fromAccountId) _toAccountId = null;
        }),
      ),
      const Gap(S.sm),
      Center(
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: t.accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.arrow_downward_rounded,
            size: 17,
            color: t.accent,
          ),
        ),
      ),
      const Gap(S.sm),
      PickerField<Account>(
        label: 'Hold it in',
        value: to,
        options: wallets.where((a) => a.id != _fromAccountId).toList(),
        labelOf: (a) => a.name,
        subtitleOf: (a) =>
            '${formatMoney(a.balance, currency: a.currency)} free',
        iconOf: (a) => accountTypeIcon(a.type.wire),
        colorOf: (a) => parseHexColor(a.color) ?? t.mutedForeground,
        onChanged: (a) => setState(() => _toAccountId = a?.id),
      ),

      // The pot is unchanged here   only which wallet is backing it. Showing
      // both wallets' available side by side is the whole point: one gains
      // spending power, the other loses exactly as much.
      const Gap(S.lg),
      MoneyImpact(
        warning: _walletWarning(held, to, typed),
        rows: [
          if (from != null)
            MoneyDelta(
              label: from.name,
              caption: 'available',
              currency: from.currency,
              before: toNum(from.balance),
              after: toNum(from.balance) + typed,
              icon: accountTypeIcon(from.type.wire),
              color: parseHexColor(from.color) ?? t.mutedForeground,
            ),
          if (to != null)
            MoneyDelta(
              label: to.name,
              caption: 'available',
              currency: to.currency,
              before: toNum(to.balance),
              after: toNum(to.balance) - typed,
              icon: accountTypeIcon(to.type.wire),
              color: parseHexColor(to.color) ?? t.mutedForeground,
            ),
        ],
      ),
    ];
  }

  /// A reservation can only move to a wallet with the free cash to back it.
  String? _walletWarning(BudgetSource? held, Account? to, double typed) {
    if (typed <= 0) return null;
    final b = widget.detail.row;
    if (held != null && typed > toNum(held.available)) {
      return 'Only ${formatMoney(held.available, currency: b.currency)} of this '
          'plan is held in "${held.account!.name}".';
    }
    if (to != null && typed > toNum(to.balance)) {
      return '"${to.name}" has only '
          '${formatMoney(to.balance, currency: to.currency)} free to back it. '
          'Transfer the cash across first.';
    }
    return null;
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.md),
      decoration: BoxDecoration(
        color: t.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: t.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: t.danger),
          const GapX(S.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: AppType.bodySm,
                height: 1.4,
                color: t.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
