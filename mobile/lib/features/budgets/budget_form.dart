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
import '../../data/outbox_store.dart';
import '../../widgets/fields.dart';
import '../../widgets/money_delta.dart';
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
    text: widget.existing == null
        ? ''
        : toNum(widget.existing!.plannedAmount).toString(),
  );
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late final _interval = TextEditingController(
    text: '${widget.existing?.recurrenceInterval ?? 1}',
  );

  late BudgetKind _kind = widget.existing?.kind ?? BudgetKind.oneTime;
  late RecurrenceUnit? _unit =
      widget.existing?.recurrenceUnit ?? RecurrenceUnit.month;
  late String? _categoryId = widget.existing?.categoryId;
  late String? _icon = widget.existing?.icon;
  late String? _color = widget.existing?.color;
  late double _alertThreshold = (widget.existing?.alertThreshold ?? 80)
      .toDouble();
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

    final data = context.read<DataState>();
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'kind': _kind.wire,
      'plannedAmount': amount,
      'alertThreshold': _alertThreshold.round(),
      'startsAt': wireDate(_startsAt),
      'categoryId': _categoryId,
      'icon': _icon,
      'color': _color,
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      'endDate': _endDate == null ? null : wireDate(_endDate!),
      if (_kind == BudgetKind.recurring) ...{
        'recurrenceUnit': _unit!.wire,
        'recurrenceInterval': int.tryParse(_interval.text.trim()) ?? 1,
      } else ...{
        'recurrenceUnit': null,
      },
      if (!_isEdit) 'currency': data.activeCurrency,
    };

    try {
      final sync = context.read<SyncState>();
      final result = await sync.saveBudget(
        body: body,
        id: _isEdit ? widget.existing!.id : null,
        name: _name.text.trim(),
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
    final categories = data.categoriesOfKind(TxKind.expense);
    final tint = parseHexColor(_color) ?? t.primary;

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
            child: IconTile(
              icon: financeIcon(_icon),
              color: tint,
              size: 56,
              radius: R.lg,
            ),
          ),
          const Gap(S.xl),
          AppTextField(
            controller: _name,
            label: 'Name',
            placeholder: 'Groceries',
            prefixIcon: Icons.badge_outlined,
            autofocus: !_isEdit,
            textCapitalization: TextCapitalization.sentences,
          ),
          const Gap(S.lg),
          AmountField(
            controller: _amount,
            currency: widget.existing?.currency ?? data.activeCurrency,
            label: 'Planned per cycle',
            hint:
                'Both what you intend to spend and the ceiling the pot can be '
                'filled to.',
            tint: tint,
          ),
          const Gap(S.lg),

          SegmentedTabs<BudgetKind>(
            value: _kind,
            options: const [BudgetKind.oneTime, BudgetKind.recurring],
            labelOf: (k) => k.label,
            iconOf: (k) =>
                k == BudgetKind.oneTime ? Icons.flag_outlined : Icons.autorenew,
            onChanged: (k) => setState(() => _kind = k),
          ),
          const Gap(S.lg),

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
                const GapX(S.md),
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
            const Gap(S.lg),
          ],

          PickerField<TxCategory>(
            label: 'Category',
            hint:
                'Optional. It only pre-selects itself when you spend from '
                'this plan   it does not restrict what the pot can pay for.',
            value: categories.where((c) => c.id == _categoryId).firstOrNull,
            options: categories,
            labelOf: (c) => c.name,
            iconOf: (c) => financeIcon(c.icon),
            colorOf: (c) => parseHexColor(c.color) ?? t.mutedForeground,
            onChanged: (c) => setState(() => _categoryId = c?.id),
            allowClear: true,
            placeholder: 'No category',
          ),
          const Gap(S.lg),

          DateField(
            label: 'Starts',
            hint: 'Nothing can be spent from the plan before this date.',
            value: _startsAt,
            onChanged: (d) => setState(() => _startsAt = d ?? _startsAt),
          ),
          const Gap(S.lg),
          DateField(
            label: 'Ends',
            placeholder: 'No end date',
            value: _endDate,
            allowClear: true,
            firstDate: _startsAt,
            onChanged: (d) => setState(() => _endDate = d),
          ),
          const Gap(S.lg),

          FieldShell(
            label: 'Alert at ${_alertThreshold.round()}% spent',
            hint:
                'You get a notification once this share of the filled pot is gone.',
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
          const Gap(S.sm),

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
          const Gap(S.lg),
          AppTextField(
            controller: _note,
            label: 'Note',
            placeholder: 'What is this pot for?',
            maxLines: 2,
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
    _amount.addListener(_onTyped);
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
        final fallback =
            accounts.where((a) => a.isDefault).firstOrNull ??
            accounts.firstOrNull;
        setState(() => _accountId = fallback?.id);
      }
    });
  }

  void _onTyped() {
    if (mounted) setState(() {});
  }

  /// The one number that can stop this, phrased as the cap it exceeds.
  String? _impactWarning(double typed, Object? ceiling) {
    final cap = toNum(ceiling);
    if (typed <= 0 || typed <= cap) return null;
    final currency = widget.detail.row.currency;
    return widget.release
        ? 'The pot only holds ${formatMoney(cap, currency: currency)}.'
        : 'Only ${formatMoney(cap, currency: currency)} more fits in this plan.';
  }

  @override
  void dispose() {
    _amount.removeListener(_onTyped);
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
      setState(
        () => _error =
            'Only ${formatMoney(b.fillable, currency: b.currency)} more can go in before '
            'this hits the plan amount.',
      );
      return;
    }
    if (widget.release && amount > toNum(b.balance)) {
      setState(
        () => _error =
            'The pot only holds ${formatMoney(b.balance, currency: b.currency)}.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final body = {
        if (_accountId != null) 'accountId': _accountId,
        'amount': amount,
        'date': wireDate(_date),
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      };
      final result = await context.read<SyncState>().budgetAction(
        budgetId: b.id,
        action: widget.release ? OutboxAction.release : OutboxAction.fund,
        label: widget.release ? 'Give money back' : 'Fill the pot',
        detail: b.name,
        body: body,
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
    final b = widget.detail.row;

    // Releasing can only go back to a wallet that actually funded the pot.
    final options = widget.release
        ? widget.detail.sources
              .where((s) => s.account != null)
              .map((s) => (s.account!.id, s.account!.name, s.available))
              .toList()
        : data.scopedAccounts.map((a) => (a.id, a.name, a.balance)).toList();

    final ceiling = widget.release ? b.balance : b.fillable;
    final typed = double.tryParse(_amount.text.trim()) ?? 0;

    // The picker in release mode lists what the *plan* holds in each wallet,
    // which is a different figure from what the wallet has available   the
    // preview needs the wallet itself.
    final wallet = data.scopedAccounts
        .where((a) => a.id == _accountId)
        .firstOrNull;

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
            currency: b.currency,
            tint: widget.release ? t.warning : t.primary,
            autofocus: true,
          ),
          const Gap(S.sm),
          Row(
            children: [
              for (final pct in const [25, 50, 100]) ...[
                if (pct != 25) const GapX(S.sm),
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
          const Gap(S.xs),
          Muted(
            widget.release
                ? 'Up to ${formatMoney(ceiling, currency: b.currency)} in the pot'
                : 'Up to ${formatMoney(ceiling, currency: b.currency)} still fits',
            size: 11.5,
          ),
          const Gap(S.lg),
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

          // Reserving money moves no cash, which is exactly why it needs
          // showing: the wallet keeps the notes and loses the spending power.
          const Gap(S.lg),
          MoneyImpact(
            warning: _impactWarning(typed, ceiling),
            rows: [
              if (wallet != null)
                MoneyDelta(
                  label: wallet.name,
                  caption: 'available',
                  currency: wallet.currency,
                  before: toNum(wallet.balance),
                  after: toNum(wallet.balance) + (widget.release ? typed : -typed),
                  icon: accountTypeIcon(wallet.type.wire),
                  color: parseHexColor(wallet.color) ?? t.mutedForeground,
                ),
              MoneyDelta(
                label: b.name,
                caption: 'in the pot',
                currency: b.currency,
                before: toNum(b.balance),
                after: toNum(b.balance) + (widget.release ? -typed : typed),
                icon: financeIcon(b.icon),
                color: parseHexColor(b.color) ?? t.primary,
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
            placeholder: 'Optional',
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
              fontSize: AppType.label,
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
Future<bool?> showAdjustSheet(
  BuildContext context, {
  required BudgetRow budget,
}) {
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
      final result = await context.read<SyncState>().budgetAction(
        budgetId: widget.budget.id,
        action: OutboxAction.adjust,
        label: _add ? 'Raise plan amount' : 'Cut plan amount',
        detail: widget.budget.name,
        body: {
          'direction': _add ? 'ADD' : 'DEDUCT',
          'amount': amount,
          if (_reason.text.trim().isNotEmpty) 'reason': _reason.text.trim(),
        },
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
    final b = widget.budget;

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
          SegmentedTabs<bool>(
            value: _add,
            options: const [true, false],
            labelOf: (v) => v ? 'Raise' : 'Cut',
            iconOf: (v) => v ? Icons.add : Icons.remove,
            colorOf: (v) => v ? t.success : t.warning,
            onChanged: (v) => setState(() => _add = v),
          ),
          const Gap(S.lg),
          AmountField(
            controller: _amount,
            currency: b.currency,
            tint: _add ? t.success : t.warning,
            autofocus: true,
          ),
          const Gap(S.sm),
          Container(
            padding: const EdgeInsets.all(S.md),
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
                      Amount(
                        formatMoney(b.openingPlanned, currency: b.currency),
                        size: 13,
                      ),
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
                        color: toNum(b.adjustedThisCycle) >= 0
                            ? t.success
                            : t.warning,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Muted('Now', size: 10.5),
                      Amount(
                        formatMoney(b.plannedAmount, currency: b.currency),
                        size: 13,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Gap(S.lg),
          AppTextField(
            controller: _reason,
            label: 'Reason',
            placeholder: 'Prices went up',
            prefixIcon: Icons.help_outline,
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
