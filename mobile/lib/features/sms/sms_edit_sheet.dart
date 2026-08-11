import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme.dart';

import '../../core/theme/tokens.dart';
import '../../models/ingest.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';
import 'sms_review_deck.dart';

Future<Map<String, dynamic>?> showSmsEditSheet(
  BuildContext context, {
  required InboxMessage message,
}) {
  return showAppSheet<Map<String, dynamic>>(
    context,
    title: 'Edit before recording',
    subtitle: message.bankLabel ?? message.sender,
    builder: (ctx) => _SmsEditSheet(message: message),
  );
}

class _SmsEditSheet extends StatefulWidget {
  const _SmsEditSheet({required this.message});
  final InboxMessage message;

  @override
  State<_SmsEditSheet> createState() => _SmsEditSheetState();
}

class _SmsEditSheetState extends State<_SmsEditSheet> {
  late DraftConfirm _draft;
  late final TextEditingController _amount;
  late final TextEditingController _payee;
  late final TextEditingController _note;
  bool _showBody = false;

  @override
  void initState() {
    super.initState();
    _draft = DraftConfirm.fromMessage(widget.message);
    _amount = TextEditingController(text: widget.message.parsedAmount ?? '');
    _payee = TextEditingController(text: _draft.payee ?? '');
    _note = TextEditingController(text: _draft.note ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _payee.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final data = context.watch<DataState>();
    final accounts = data.scopedAccounts;
    final categories = data.categories.data ?? const <TxCategory>[];
    final kind = _draft.kind ?? TxKind.expense;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedTabs<TxKind>(
            value: kind,
            options: const [TxKind.expense, TxKind.income, TxKind.transfer],
            labelOf: (k) => k.label,
            onChanged: (k) => setState(() => _draft.kind = k),
          ),
          const Gap(S.md),
          AmountField(
            controller: _amount,
            currency: _draft.currency ?? data.activeCurrency,
            label: 'Amount',
            tint: kind == TxKind.income ? t.success : t.primary,
          ),
          const Gap(S.md),
          PickerField<Account>(
            label: 'Wallet',
            value: accounts.where((a) => a.id == _draft.accountId).firstOrNull,
            options: accounts,
            labelOf: (a) => a.name,
            onChanged: (a) => setState(() => _draft.accountId = a?.id),
          ),
          if (kind == TxKind.transfer) ...[
            const Gap(S.md),
            PickerField<Account>(
              label: 'To wallet',
              value: accounts.where((a) => a.id == _draft.transferAccountId).firstOrNull,
              options: accounts.where((a) => a.id != _draft.accountId).toList(),
              labelOf: (a) => a.name,
              onChanged: (a) => setState(() => _draft.transferAccountId = a?.id),
            ),
          ],
          if (kind != TxKind.transfer) ...[
            const Gap(S.md),
            PickerField<TxCategory>(
              label: 'Category',
              value: categories.where((c) => c.id == _draft.categoryId).firstOrNull,
              options: categories
                  .where(
                    (c) => !c.archived && c.kind == (kind == TxKind.income ? 'INCOME' : 'EXPENSE'),
                  )
                  .toList(),
              labelOf: (c) => c.name,
              onChanged: (c) => setState(() => _draft.categoryId = c?.id),
            ),
          ],
          const Gap(S.md),
          AppTextField(controller: _payee, label: 'Payee', prefixIcon: Icons.storefront_outlined),
          const Gap(S.md),
          AppTextField(controller: _note, label: 'Note', prefixIcon: Icons.notes_rounded),
          const Gap(S.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Always use these', style: TextStyle(fontSize: AppType.body)),
            subtitle: const Text(
              'Remember wallet and category for this sender',
              style: TextStyle(fontSize: AppType.label),
            ),
            value: _draft.rememberMapping,
            onChanged: (v) => setState(() => _draft.rememberMapping = v),
          ),
          TextButton(
            onPressed: () => setState(() => _showBody = !_showBody),
            child: Text(_showBody ? 'Hide SMS' : 'Show original SMS'),
          ),
          if (_showBody)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(S.md),
              decoration: BoxDecoration(
                color: t.surfaceMuted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.message.body,
                style: const TextStyle(fontSize: AppType.label, height: 1.4),
              ),
            ),
          const Gap(S.lg),
          AppButton(
            label: 'Save & record',
            expand: true,
            onPressed: () {
              _draft.amount = double.tryParse(_amount.text.trim());
              _draft.payee = _payee.text.trim().isEmpty ? null : _payee.text.trim();
              _draft.note = _note.text.trim().isEmpty ? null : _note.text.trim();
              if (_draft.accountId == null) {
                toast(context, 'Pick a wallet', error: true);
                return;
              }
              if (_draft.amount == null || _draft.amount! <= 0) {
                toast(context, 'Enter an amount', error: true);
                return;
              }
              if (kind == TxKind.transfer && _draft.transferAccountId == null) {
                toast(context, 'Pick a destination wallet', error: true);
                return;
              }
              Navigator.pop(context, _draft.toBody());
            },
          ),
        ],
      ),
    );
  }
}
