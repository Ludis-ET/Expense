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
import '../../widgets/money_delta.dart';
import '../../widgets/ui.dart';

/// Turning a plan from one kind into the other.
///
/// Moves no money - the pot keeps every birr - but changes what all of its
/// numbers *mean*, which is why this is a sheet with questions rather than a
/// toggle. A monthly grocery ceiling makes a nonsense savings goal, and a
/// saving plan has no cadence to reset against, so each direction asks for the
/// piece the other does not have.
Future<bool?> showConvertSheet(
  BuildContext context, {
  required BudgetDetail detail,
}) {
  final toSaving = !detail.row.type.isSaving;
  return showAppSheet<bool>(
    context,
    title: toSaving ? 'Make it a saving plan' : 'Make it a spending plan',
    subtitle: 'The money stays where it is. What changes is what it is for.',
    builder: (ctx) => _ConvertSheet(detail: detail),
  );
}

class _ConvertSheet extends StatefulWidget {
  const _ConvertSheet({required this.detail});
  final BudgetDetail detail;

  @override
  State<_ConvertSheet> createState() => _ConvertSheetState();
}

class _ConvertSheetState extends State<_ConvertSheet> {
  final _amount = TextEditingController();
  final _goal = TextEditingController();

  late BudgetKind _kind;
  RecurrenceUnit? _unit = RecurrenceUnit.month;
  String? _releaseTo;
  bool _saving = false;
  String? _error;

  bool get _toSaving => !widget.detail.row.type.isSaving;

  @override
  void initState() {
    super.initState();
    final b = widget.detail.row;

    // Becoming a saving plan defaults to a one-off goal; becoming a spending
    // plan keeps whatever cadence it had, or falls back to monthly.
    _kind = _toSaving
        ? BudgetKind.oneTime
        : (b.kind == BudgetKind.recurring ? BudgetKind.recurring : BudgetKind.oneTime);
    _unit = b.recurrenceUnit ?? RecurrenceUnit.month;

    // Pre-filled with something sensible, never silently reused: the pot's
    // current balance is a far better starting guess for a savings target than
    // a monthly spending ceiling.
    final suggestion = _toSaving
        ? (toNum(b.balance) > 0 ? toNum(b.balance) : toNum(b.plannedAmount))
        : toNum(b.plannedAmount);
    _amount.text = suggestion == suggestion.roundToDouble()
        ? '${suggestion.round()}'
        : suggestion.toStringAsFixed(2);

    _amount.addListener(_onTyped);
    _goal.addListener(_onTyped);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DataState>().loadAccounts();
    });
  }

  void _onTyped() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _amount.removeListener(_onTyped);
    _goal.removeListener(_onTyped);
    _amount.dispose();
    _goal.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final b = widget.detail.row;
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
        '/budgets/${b.id}/convert',
        body: {
          'type': _toSaving ? 'SAVING' : 'SPENDING',
          'plannedAmount': amount,
          if (_toSaving && _kind == BudgetKind.recurring)
            'goalAmount': double.tryParse(_goal.text.trim()),
          'kind': _kind.wire,
          if (_kind == BudgetKind.recurring) 'recurrenceUnit': _unit?.wire,
          if (_releaseTo != null) 'releaseSurplusTo': _releaseTo,
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
    final balance = toNum(b.balance);
    final typed = double.tryParse(_amount.text.trim()) ?? 0;

    // Becoming a spending plan puts the balance inside a cycle that has a
    // ceiling. Opening already over your own line is the worst outcome, so the
    // surplus is offered back before it can happen.
    final surplus = !_toSaving && typed > 0 && balance > typed ? balance - typed : 0.0;

    final wallets = data.scopedAccounts
        .where((a) => a.currency == b.currency)
        .toList();

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
          MoneyFlow(
            tone: _toSaving ? t.save : t.primary,
            from: FlowSide(
              label: b.type.label,
              amount: formatMoney(b.plannedAmount, currency: b.currency),
              caption: b.type.isSaving ? 'target' : 'ceiling',
              icon: b.type.isSaving
                  ? Icons.savings_rounded
                  : Icons.shopping_bag_outlined,
              color: b.type.isSaving ? t.save : t.primary,
            ),
            to: FlowSide(
              label: _toSaving ? 'Saving' : 'Spending',
              amount: typed > 0
                  ? formatMoney(typed, currency: b.currency)
                  : '—',
              caption: _toSaving ? 'target' : 'ceiling',
              icon: _toSaving
                  ? Icons.savings_rounded
                  : Icons.shopping_bag_outlined,
              color: _toSaving ? t.save : t.primary,
            ),
            footnote:
                '${formatMoney(b.balance, currency: b.currency)} in the pot '
                'carries across untouched.',
          ),
          const Gap(S.lg),

          AmountField(
            controller: _amount,
            currency: b.currency,
            label: _toSaving
                ? (_kind == BudgetKind.recurring ? 'Save each cycle' : 'Target')
                : 'Planned per cycle',
            tint: _toSaving ? t.save : t.primary,
            autofocus: true,
          ),

          if (_toSaving && _kind == BudgetKind.recurring) ...[
            const Gap(S.lg),
            AmountField(
              controller: _goal,
              currency: b.currency,
              label: 'Until you reach (optional)',
              hint: 'Leave empty for a habit with no end.',
              tint: t.save,
            ),
          ],

          const Gap(S.lg),
          SegmentedTabs<BudgetKind>(
            value: _kind,
            options: const [BudgetKind.oneTime, BudgetKind.recurring],
            labelOf: (k) => k == BudgetKind.oneTime ? 'One-off' : 'Repeating',
            iconOf: (k) =>
                k == BudgetKind.oneTime ? Icons.flag_outlined : Icons.autorenew,
            onChanged: (k) => setState(() => _kind = k),
          ),

          if (_kind == BudgetKind.recurring) ...[
            const Gap(S.lg),
            PickerField<RecurrenceUnit>(
              label: 'Every',
              value: _unit,
              options: RecurrenceUnit.values,
              labelOf: (u) => u.label,
              onChanged: (u) => setState(() => _unit = u ?? _unit),
            ),
          ],

          if (surplus > 0) ...[
            const Gap(S.lg),
            PickerField<Account>(
              label: 'Give the surplus back to',
              value: wallets.where((a) => a.id == _releaseTo).firstOrNull,
              options: wallets,
              labelOf: (a) => a.name,
              subtitleOf: (a) =>
                  '${formatMoney(a.balance, currency: a.currency)} available',
              iconOf: (a) => accountTypeIcon(a.type.wire),
              colorOf: (a) => parseHexColor(a.color) ?? t.mutedForeground,
              onChanged: (a) => setState(() => _releaseTo = a?.id),
            ),
            const Gap(S.sm),
            MoneyImpact(
              warning: _releaseTo == null
                  ? 'The pot holds ${formatMoney(surplus, currency: b.currency)} '
                        'more than the new ceiling. Pick a wallet, or the plan '
                        'opens already over its line.'
                  : null,
              rows: [
                MoneyDelta(
                  label: b.name,
                  caption: 'in the pot',
                  currency: b.currency,
                  before: balance,
                  after: typed,
                  icon: financeIcon(b.icon),
                  color: t.primary,
                ),
              ],
            ),
          ],

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
            label: _toSaving ? 'Make it saving' : 'Make it spending',
            icon: Icons.swap_vert_rounded,
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
