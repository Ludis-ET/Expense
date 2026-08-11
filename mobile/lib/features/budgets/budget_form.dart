import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';

/// Create or edit a budget plan. Returns true when something was written.
Future<bool?> showBudgetForm(BuildContext context, {BudgetRow? existing}) {
  return showAppSheet<bool>(
    context,
    title: existing == null ? 'New plan' : 'Edit plan',
    builder: (ctx) => _BudgetForm(existing: existing),
  );
}

class _BudgetForm extends StatefulWidget {
  const _BudgetForm({this.existing});
  final BudgetRow? existing;

  @override
  State<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends State<_BudgetForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _amount = TextEditingController(
    text: widget.existing == null ? '' : toNum(widget.existing!.plannedAmount).toString(),
  );
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late final _interval = TextEditingController(
    text: '${widget.existing?.recurrenceInterval ?? 1}',
  );

  late BudgetKind _kind = widget.existing?.kind ?? BudgetKind.oneTime;
  late RecurrenceUnit? _unit = widget.existing?.recurrenceUnit ?? RecurrenceUnit.month;
  late String? _categoryId = widget.existing?.categoryId;
  late String? _icon = widget.existing?.icon;
  late String? _color = widget.existing?.color;
  late double _alertThreshold = (widget.existing?.alertThreshold ?? 80).toDouble();
  late DateTime _startsAt = widget.existing?.startsAt ?? DateTime.now();
  late DateTime? _endDate = widget.existing?.endDate;

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DataState>().loadCategories();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    _interval.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the plan a name.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Set how much you plan to spend per cycle.');
      return;
    }
    if (_kind == BudgetKind.recurring && _unit == null) {
      setState(() => _error = 'Pick how often this plan repeats.');
      return;
    }
    if (_endDate != null && _endDate!.isBefore(_startsAt)) {
      setState(() => _error = 'End date must be on or after the start date.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final api = context.read<ApiClient>();
    final data = context.read<DataState>();
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'kind': _kind.wire,
      'plannedAmount': amount,
      'alertThreshold': _alertThreshold.round(),
      'startsAt': _startsAt.toUtc().toIso8601String(),
      'categoryId': _categoryId,
      'icon': _icon,
      'color': _color,
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      'endDate': _endDate?.toUtc().toIso8601String(),
      if (_kind == BudgetKind.recurring) ...{
        'recurrenceUnit': _unit!.wire,
        'recurrenceInterval': int.tryParse(_interval.text.trim()) ?? 1,
      } else ...{
        'recurrenceUnit': null,
      },
      if (!_isEdit) 'currency': data.activeCurrency,
    };

    try {
      if (_isEdit) {
        await api.put('/budgets/${widget.existing!.id}', body: body);
      } else {
        await api.post('/budgets', body: body);
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
    final categories = data.categoriesOfKind(TxKind.expense);
    final tint = parseHexColor(_color) ?? t.primary;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: IconTile(
              icon: financeIcon(_icon),
              color: tint,
              size: 56,
              radius: R.lg,
            ),
          ),
          const SizedBox(height: 20),
          AppTextField(
            controller: _name,
            label: 'Name',
            placeholder: 'Groceries',
            prefixIcon: Icons.badge_outlined,
            autofocus: !_isEdit,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          AmountField(
            controller: _amount,
            currency: widget.existing?.currency ?? data.activeCurrency,
            label: 'Planned per cycle',
            tint: tint,
          ),
          const SizedBox(height: 6),
          Muted(
            'This is both what you intend to spend and the ceiling the pot can '
            'be filled to.',
            size: 11.5,
            height: 1.4,
          ),
          const SizedBox(height: 18),

          SegmentedTabs<BudgetKind>(
            value: _kind,
            options: const [BudgetKind.oneTime, BudgetKind.recurring],
            labelOf: (k) => k.label,
            iconOf: (k) => k == BudgetKind.oneTime ? Icons.flag_outlined : Icons.autorenew,
            onChanged: (k) => setState(() => _kind = k),
          ),
          const SizedBox(height: 16),

          if (_kind == BudgetKind.recurring) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 92,
                  child: AppTextField(
                    controller: _interval,
                    label: 'Every',
                    placeholder: '1',
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PickerField<RecurrenceUnit>(
                    label: 'Period',
                    value: _unit,
                    options: RecurrenceUnit.values,
                    labelOf: (u) => u.label,
                    onChanged: (u) => setState(() => _unit = u ?? _unit),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          PickerField<TxCategory>(
            label: 'Category',
            hint: 'Optional. It only pre-selects itself when you spend from '
                'this plan — it does not restrict what the pot can pay for.',
            value: categories.where((c) => c.id == _categoryId).firstOrNull,
            options: categories,
            labelOf: (c) => c.name,
            iconOf: (c) => financeIcon(c.icon),
            colorOf: (c) => parseHexColor(c.color) ?? t.mutedForeground,
            onChanged: (c) => setState(() => _categoryId = c?.id),
            allowClear: true,
            placeholder: 'No category',
          ),
          const SizedBox(height: 16),

          DateField(
            label: 'Starts',
            hint: 'Nothing can be spent from the plan before this date.',
            value: _startsAt,
            onChanged: (d) => setState(() => _startsAt = d ?? _startsAt),
          ),
          const SizedBox(height: 16),
          DateField(
            label: 'Ends',
            placeholder: 'No end date',
            value: _endDate,
            allowClear: true,
            firstDate: _startsAt,
            onChanged: (d) => setState(() => _endDate = d),
          ),
          const SizedBox(height: 18),

          FieldShell(
            label: 'Alert at ${_alertThreshold.round()}% spent',
            hint: 'You get a notification once this share of the filled pot is gone.',
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: t.primary,
                inactiveTrackColor: t.surfaceMuted,
                thumbColor: t.primary,
                overlayColor: t.primary.withValues(alpha: 0.12),
                trackHeight: 4,
              ),
              child: Slider(
                value: _alertThreshold,
                min: 10,
                max: 100,
                divisions: 18,
                onChanged: (v) => setState(() => _alertThreshold = v),
              ),
            ),
          ),
          const SizedBox(height: 8),

          ColorPickerRow(
            value: _color,
            colors: financeColors,
            onChanged: (c) => setState(() => _color = c),
          ),
          const SizedBox(height: 18),
          IconPickerGrid(
            value: _icon,
            names: iconNames,
            iconOf: financeIcon,
            tint: tint,
            onChanged: (i) => setState(() => _icon = i),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _note,
            label: 'Note',
            placeholder: 'What is this pot for?',
            maxLines: 2,
            prefixIcon: Icons.notes_outlined,
          ),

          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: t.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: t.danger.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: t.danger),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(fontSize: 13, height: 1.4, color: t.foreground),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          AppButton(
            label: _isEdit ? 'Save changes' : 'Create plan',
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

/// Fill the pot from a wallet, or give money back to one.
Future<bool?> showFundSheet(
  BuildContext context, {
  required BudgetDetail detail,
  required bool release,
}) {
  return showAppSheet<bool>(
    context,
    title: release ? 'Give money back' : 'Fill the pot',
    subtitle: release
        ? 'Returns reserved money to a wallet, freeing it to spend elsewhere.'
        : 'Moves money out of your available balance and reserves it here.',
    builder: (ctx) => _FundSheet(detail: detail, release: release),
  );
}

class _FundSheet extends StatefulWidget {
  const _FundSheet({required this.detail, required this.release});

  final BudgetDetail detail;
  final bool release;

  @override
  State<_FundSheet> createState() => _FundSheetState();
}

class _FundSheetState extends State<_FundSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _accountId;
  DateTime _date = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<DataState>().loadAccounts();
      if (!mounted) return;
      if (widget.release) {
        // Default to whichever wallet funded the largest share.
        final sources = [...widget.detail.sources]
          ..sort((a, b) => toNum(b.available).compareTo(toNum(a.available)));
        setState(() => _accountId = sources.firstOrNull?.account?.id);
      } else {
        final accounts = context.read<DataState>().scopedAccounts;
        final fallback = accounts.where((a) => a.isDefault).firstOrNull ?? accounts.firstOrNull;
        setState(() => _accountId = fallback?.id);
      }
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final b = widget.detail.row;
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    if (!widget.release && _accountId == null) {
      setState(() => _error = 'Pick the wallet the money comes from.');
      return;
    }
    if (!widget.release && amount > toNum(b.fillable)) {
      setState(() => _error =
          'Only ${formatMoney(b.fillable, currency: b.currency)} more can go in before '
          'this hits the plan amount.');
      return;
    }
    if (widget.release && amount > toNum(b.balance)) {
      setState(() => _error =
          'The pot only holds ${formatMoney(b.balance, currency: b.currency)}.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await context.read<ApiClient>().post(
        '/budgets/${b.id}/${widget.release ? 'release' : 'fund'}',
        body: {
          if (_accountId != null) 'accountId': _accountId,
          'amount': amount,
          'date': _date.toUtc().toIso8601String(),
          if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
        },
      );
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

    // Releasing can only go back to a wallet that actually funded the pot.
    final options = widget.release
        ? widget.detail.sources
            .where((s) => s.account != null)
            .map((s) => (s.account!.id, s.account!.name, s.available))
            .toList()
        : data.scopedAccounts.map((a) => (a.id, a.name, a.balance)).toList();

    final ceiling = widget.release ? b.balance : b.fillable;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AmountField(
            controller: _amount,
            currency: b.currency,
            tint: widget.release ? t.warning : t.primary,
            autofocus: true,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final pct in const [25, 50, 100]) ...[
                if (pct != 25) const SizedBox(width: 8),
                Expanded(
                  child: _QuickFill(
                    label: pct == 100 ? 'Max' : '$pct%',
                    onTap: () {
                      final cap = toNum(ceiling);
                      final v = pct == 100 ? cap : (cap * pct / 100);
                      _amount.text = v == v.roundToDouble()
                          ? '${v.round()}'
                          : v.toStringAsFixed(2);
                      setState(() {});
                    },
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Muted(
            widget.release
                ? 'Up to ${formatMoney(ceiling, currency: b.currency)} in the pot'
                : 'Up to ${formatMoney(ceiling, currency: b.currency)} still fits',
            size: 11.5,
          ),
          const SizedBox(height: 16),
          PickerField<(String, String, String)>(
            label: widget.release ? 'Give back to' : 'Take from',
            value: options.where((o) => o.$1 == _accountId).firstOrNull,
            options: options,
            labelOf: (o) => o.$2,
            subtitleOf: (o) =>
                '${formatMoney(o.$3, currency: b.currency)} ${widget.release ? 'from this wallet' : 'available'}',
            iconOf: (_) => Icons.account_balance_wallet_outlined,
            onChanged: (o) => setState(() => _accountId = o?.$1),
          ),
          const SizedBox(height: 16),
          DateField(
            label: 'Date',
            value: _date,
            onChanged: (d) => setState(() => _date = d ?? _date),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _note,
            label: 'Note',
            placeholder: 'Optional',
            prefixIcon: Icons.notes_outlined,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: t.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: t.danger.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: t.danger),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(fontSize: 13, height: 1.4, color: t.foreground),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          AppButton(
            label: widget.release ? 'Give back' : 'Fill the pot',
            icon: widget.release ? Icons.undo : Icons.savings_outlined,
            size: BtnSize.lg,
            expand: true,
            loading: _saving,
            onPressed: _saving ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _QuickFill extends StatelessWidget {
  const _QuickFill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: t.surfaceMuted.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: t.border.withValues(alpha: 0.8)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: t.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Raise or cut the plan amount mid-cycle. The direction is explicit so a
/// stray minus sign can never turn a top-up into a cut.
Future<bool?> showAdjustSheet(BuildContext context, {required BudgetRow budget}) {
  return showAppSheet<bool>(
    context,
    title: 'Change the plan amount',
    subtitle: 'Filed against the cycle it happens in, so history stays honest.',
    builder: (ctx) => _AdjustSheet(budget: budget),
  );
}

class _AdjustSheet extends StatefulWidget {
  const _AdjustSheet({required this.budget});
  final BudgetRow budget;

  @override
  State<_AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends State<_AdjustSheet> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _add = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
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
      await context.read<ApiClient>().post(
        '/budgets/${widget.budget.id}/adjust',
        body: {
          'direction': _add ? 'ADD' : 'DEDUCT',
          'amount': amount,
          if (_reason.text.trim().isNotEmpty) 'reason': _reason.text.trim(),
        },
      );
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
    final b = widget.budget;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedTabs<bool>(
            value: _add,
            options: const [true, false],
            labelOf: (v) => v ? 'Raise' : 'Cut',
            iconOf: (v) => v ? Icons.add : Icons.remove,
            colorOf: (v) => v ? t.success : t.warning,
            onChanged: (v) => setState(() => _add = v),
          ),
          const SizedBox(height: 18),
          AmountField(
            controller: _amount,
            currency: b.currency,
            tint: _add ? t.success : t.warning,
            autofocus: true,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.surfaceMuted.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Muted('Opened at', size: 10.5),
                      Amount(formatMoney(b.openingPlanned, currency: b.currency), size: 13),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Muted('Adjusted so far', size: 10.5),
                      Amount(
                        formatMoney(b.adjustedThisCycle, currency: b.currency),
                        size: 13,
                        color: toNum(b.adjustedThisCycle) >= 0 ? t.success : t.warning,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Muted('Now', size: 10.5),
                      Amount(formatMoney(b.plannedAmount, currency: b.currency), size: 13),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _reason,
            label: 'Reason',
            placeholder: 'Prices went up',
            prefixIcon: Icons.help_outline,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: t.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: t.danger.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: t.danger),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(fontSize: 13, height: 1.4, color: t.foreground),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          AppButton(
            label: _add ? 'Raise the plan' : 'Cut the plan',
            icon: Icons.check,
            size: BtnSize.lg,
            expand: true,
            loading: _saving,
            onPressed: _saving ? null : _submit,
          ),
        ],
      ),
    );
  }
}
