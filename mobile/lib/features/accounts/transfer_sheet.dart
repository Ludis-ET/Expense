import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../data/outbox_store.dart';
import '../../state/data_state.dart';
import '../../state/sync_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/money_delta.dart';
import '../../widgets/ui.dart';

/// `TransferModal`   money between two of your own wallets. Nothing is earned
/// or spent, so this never touches income or expense totals.
Future<bool?> showTransferSheet(BuildContext context, {Account? from}) {
  return showAppSheet<bool>(
    context,
    title: 'Transfer',
    subtitle: 'Between your own wallets. Not income, not spending.',
    builder: (ctx) => _TransferSheet(from: from),
  );
}

class _TransferSheet extends StatefulWidget {
  const _TransferSheet({this.from});
  final Account? from;

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  final _amount = TextEditingController();

  /// What landed on the far side, when the two wallets hold different money.
  /// Crediting the destination the sent figure is how 100 USD silently becomes
  /// 100 birr, so the server refuses to guess and neither does this sheet.
  final _received = TextEditingController();
  final _note = TextEditingController();

  String? _fromId;
  String? _toId;
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fromId = widget.from?.id;
    // The preview redraws on every keystroke, so both fields drive setState.
    _amount.addListener(_onTyped);
    _received.addListener(_onTyped);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<DataState>().loadAccounts();
      if (!mounted || _fromId != null) return;
      final accounts = context.read<DataState>().scopedAccounts;
      final fallback =
          accounts.where((a) => a.isDefault).firstOrNull ??
          accounts.firstOrNull;
      if (fallback != null) setState(() => _fromId = fallback.id);
    });
  }

  void _onTyped() {
    if (mounted) setState(() {});
  }

  /// Why this transfer cannot go through, said before it is attempted.
  ///
  /// The interesting case is the middle one. A wallet can hold plenty of cash
  /// and still not be able to send it, because plans have already reserved
  /// part of it   and until now the only way to discover that was to tap
  /// Transfer and read a server refusal.
  String? _impactWarning(Account? from, double sent) {
    if (from == null || sent <= 0) return null;
    final free = toNum(from.balance);
    if (sent <= free) return null;

    final held = toNum(from.lockedAmount);
    if (held > 0 && sent <= toNum(from.realBalance)) {
      return '${formatMoney(held, currency: from.currency)} here is set aside '
          'in plans. Give some back first, or send less.';
    }
    return 'Only ${formatMoney(free, currency: from.currency)} is free here.';
  }

  @override
  void dispose() {
    _amount.removeListener(_onTyped);
    _received.removeListener(_onTyped);
    _amount.dispose();
    _received.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final data = context.read<DataState>();
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    if (_fromId == null || _toId == null) {
      setState(() => _error = 'Pick both wallets.');
      return;
    }
    if (_fromId == _toId) {
      setState(
        () => _error = 'Transfer destination must be a different account.',
      );
      return;
    }
    final source = data.transferableAccounts
        .where((a) => a.id == _fromId)
        .firstOrNull;
    final target = data.transferableAccounts
        .where((a) => a.id == _toId)
        .firstOrNull;
    if (source != null && amount > toNum(source.balance)) {
      setState(
        () => _error =
            '${source.name} only has ${formatMoney(source.balance, currency: source.currency)} available.',
      );
      return;
    }

    final crossing =
        source != null && target != null && source.currency != target.currency;
    final received = double.tryParse(_received.text.trim());
    if (crossing && (received == null || received <= 0)) {
      setState(
        () => _error = 'Say how much ${target.currency} actually arrived.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final from = source;
    final to = target;
    Ref? asRef(Account? a) => a == null
        ? null
        : Ref(
            id: a.id,
            name: a.name,
            icon: a.icon,
            color: a.color,
            currency: a.currency,
            type: a.type.wire,
          );
    // The wallet the money leaves decides the denomination   not whichever
    // currency the app happens to be scoped to.
    final currency = from?.currency ?? data.activeCurrency;
    final body = {
      'kind': 'TRANSFER',
      'amount': amount,
      'currency': currency,
      'date': wireDate(_date),
      'accountId': _fromId,
      'transferAccountId': _toId,
      'tags': <String>[],
      if (crossing) 'transferAmount': received,
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
    };
    try {
      final localId = newLocalId();
      final optimistic = Transaction(
        id: localId,
        kind: TxKind.transfer,
        amount: amount.toString(),
        currency: currency,
        date: _date,
        accountId: _fromId!,
        tags: const [],
        account: asRef(from),
        transferAccountId: _toId,
        transferAccount: asRef(to),
        transferAmount: (crossing ? received! : amount).toString(),
        transferRate: crossing ? (received! / amount).toString() : null,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        pending: PendingState.pending,
      );
      final result = await context.read<SyncState>().saveTransaction(
        body,
        optimistic,
      );
      if (!mounted) return;
      if (result.queued) {
        toast(context, 'Saved offline   will sync when you are back online');
      }
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
    final accounts = data.transferableAccounts;

    Account? byId(String? id) =>
        id == null ? null : accounts.where((a) => a.id == id).firstOrNull;

    final from = byId(_fromId);
    final to = byId(_toId);
    final crossing = from != null && to != null && from.currency != to.currency;

    final sent = double.tryParse(_amount.text.trim()) ?? 0;
    final received = double.tryParse(_received.text.trim()) ?? 0;
    final landing = crossing ? received : sent;

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
          AmountField(
            controller: _amount,
            currency: from?.currency ?? data.activeCurrency,
            tint: t.accent,
            autofocus: true,
          ),
          const Gap(S.lg),
          PickerField<Account>(
            label: 'From',
            value: byId(_fromId),
            options: accounts,
            labelOf: (a) => a.name,
            subtitleOf: (a) =>
                '${formatMoney(a.balance, currency: a.currency)} available',
            iconOf: (a) => accountTypeIcon(a.type.wire),
            colorOf: (a) => parseHexColor(a.color) ?? t.mutedForeground,
            onChanged: (a) => setState(() {
              _fromId = a?.id;
              if (_toId == _fromId) _toId = null;
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
            label: 'To',
            value: byId(_toId),
            options: accounts.where((a) => a.id != _fromId).toList(),
            labelOf: (a) => a.name,
            subtitleOf: (a) =>
                '${formatMoney(a.balance, currency: a.currency)} available',
            iconOf: (a) => accountTypeIcon(a.type.wire),
            colorOf: (a) => parseHexColor(a.color) ?? t.mutedForeground,
            onChanged: (a) => setState(() => _toId = a?.id),
          ),

          // Crossing a currency needs the far-side figure. Santim will not
          // invent a rate, so this is a field rather than a conversion.
          if (crossing) ...[
            const Gap(S.lg),
            AppTextField(
              controller: _received,
              label: 'Arrived in ${to.name}',
              placeholder: '0.00',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              prefixIcon: Icons.south_east_rounded,
              suffix: Text(
                to.currency,
                style: TextStyle(
                  fontSize: AppType.bodySm,
                  fontWeight: W.semibold,
                  color: t.mutedForeground,
                ),
              ),
            ),
            if (sent > 0 && received > 0) ...[
              const Gap(S.xs),
              Muted(
                '1 ${from.currency} = '
                '${(received / sent).toStringAsFixed(4)} ${to.currency}',
                size: AppType.caption,
              ),
            ],
          ],

          // What this does to both wallets, live. Replaces finding out from a
          // refusal after tapping Transfer.
          const Gap(S.lg),
          MoneyImpact(
            warning: _impactWarning(from, sent),
            rows: [
              if (from != null)
                MoneyDelta(
                  label: from.name,
                  caption: 'available',
                  currency: from.currency,
                  before: toNum(from.balance),
                  after: toNum(from.balance) - sent,
                  icon: accountTypeIcon(from.type.wire),
                  color: parseHexColor(from.color) ?? t.mutedForeground,
                ),
              if (to != null)
                MoneyDelta(
                  label: to.name,
                  caption: 'available',
                  currency: to.currency,
                  before: toNum(to.balance),
                  after: toNum(to.balance) + landing,
                  icon: accountTypeIcon(to.type.wire),
                  color: parseHexColor(to.color) ?? t.accent,
                ),
            ],
          ),

          const Gap(S.lg),
          DateField(
            label: 'Date',
            value: _date,
            onChanged: (d) => setState(() => _date = d ?? _date),
          ),
          const Gap(S.lg),
          AppTextField(
            controller: _note,
            label: 'Note',
            placeholder: 'ATM withdrawal, moving savings…',
            prefixIcon: Icons.notes_outlined,
          ),
          if (_error != null) ...[
            const Gap(S.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: S.md,
                vertical: S.md,
              ),
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
                      _error!,
                      style: TextStyle(
                        fontSize: AppType.bodySm,
                        height: 1.4,
                        color: t.foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Gap(S.xl),
          AppButton(
            label: 'Transfer',
            icon: Icons.swap_horiz_rounded,
            size: BtnSize.lg,
            expand: true,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
