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
import '../../widgets/ui.dart';

/// Create or edit a wallet. Returns true when something was written.
Future<bool?> showAccountForm(BuildContext context, {Account? existing}) {
  return showAppSheet<bool>(
    context,
    title: existing == null ? 'New wallet' : 'Edit wallet',
    builder: (ctx) => _AccountForm(existing: existing),
  );
}

class _AccountForm extends StatefulWidget {
  const _AccountForm({this.existing});
  final Account? existing;

  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _opening = TextEditingController(
    text: widget.existing == null ? '' : toNum(widget.existing!.openingBalance).toString(),
  );

  late AccountType _type = widget.existing?.type ?? AccountType.cash;
  late String _currency = widget.existing?.currency ?? 'ETB';
  late String? _icon = widget.existing?.icon;
  late String? _color = widget.existing?.color;
  late bool _isDefault = widget.existing?.isDefault ?? false;
  late bool _archived = widget.existing?.archived ?? false;

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  static const _currencies = ['ETB', 'USD', 'EUR', 'GBP', 'KES', 'AED'];

  @override
  void initState() {
    super.initState();
    final data = context.read<DataState>();
    if (!_isEdit) _currency = data.activeCurrency;
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the wallet a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'type': _type.wire,
      'currency': _currency,
      if (_icon != null) 'icon': _icon,
      if (_color != null) 'color': _color,
      'isDefault': _isDefault,
      if (!_isEdit) 'openingBalance': double.tryParse(_opening.text.trim()) ?? 0,
      if (_isEdit) 'archived': _archived,
    };

    try {
      final sync = context.read<SyncState>();
      final result = await sync.saveAccount(
        body: body,
        id: _isEdit ? widget.existing!.id : null,
        name: _name.text.trim(),
      );
      if (!mounted) return;
      if (result.queued) {
        toast(context, 'Saved offline — will sync when you are back online');
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
    final tint = parseHexColor(_color) ?? t.primary;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: IconTile(
              icon: _icon != null ? financeIcon(_icon) : accountTypeIcon(_type.wire),
              color: tint,
              size: 58,
              radius: R.lg,
            ),
          ),
          const Gap(S.xl),
          AppTextField(
            controller: _name,
            label: 'Name',
            placeholder: 'CBE Savings',
            prefixIcon: Icons.badge_outlined,
            autofocus: !_isEdit,
            textCapitalization: TextCapitalization.words,
          ),
          const Gap(S.lg),
          PickerField<AccountType>(
            label: 'Type',
            value: _type,
            options: AccountType.values,
            labelOf: (a) => a.label,
            iconOf: (a) => accountTypeIcon(a.wire),
            onChanged: (a) => setState(() => _type = a ?? _type),
          ),
          const Gap(S.lg),
          PickerField<String>(
            label: 'Currency',
            hint:
                'A wallet holds one currency. Totals are never mixed across '
                'currencies — switch the scope from the topbar instead.',
            value: _currency,
            options: _currencies,
            labelOf: (c) => '$c · ${currencySymbol(c)}',
            onChanged: (c) => setState(() => _currency = c ?? _currency),
            enabled: !_isEdit,
          ),
          if (!_isEdit) ...[
            const Gap(S.lg),
            AppTextField(
              controller: _opening,
              label: 'Opening balance',
              hint:
                  'What is in the wallet right now. Every later figure is '
                  'measured from here.',
              placeholder: '0',
              prefixIcon: Icons.savings_outlined,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
          const Gap(S.lg),
          ColorPickerRow(
            value: _color,
            colors: financeColors,
            onChanged: (c) => setState(() => _color = c),
          ),
          const Gap(S.lg),
          IconPickerGrid(
            value: _icon,
            names: iconNames,
            iconOf: financeIcon,
            tint: tint,
            onChanged: (i) => setState(() => _icon = i),
          ),
          const Gap(S.sm),
          SwitchRow(
            title: 'Default wallet',
            subtitle: 'Preselected on the transaction form.',
            icon: Icons.star_outline,
            value: _isDefault,
            onChanged: (v) => setState(() => _isDefault = v),
          ),
          if (_isEdit)
            SwitchRow(
              title: 'Archived',
              subtitle: 'Hidden from pickers, history is kept.',
              icon: Icons.inventory_2_outlined,
              value: _archived,
              onChanged: (v) => setState(() => _archived = v),
            ),
          if (_error != null) ...[
            const Gap(S.md),
            Container(
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
                      _error!,
                      style: TextStyle(fontSize: AppType.bodySm, color: t.foreground),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Gap(S.xl),
          AppButton(
            label: _isEdit ? 'Save changes' : 'Create wallet',
            icon: Icons.check,
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
