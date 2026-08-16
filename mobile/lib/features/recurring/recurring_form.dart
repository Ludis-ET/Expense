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

/// Seed values for a brand-new rule — outlook / plan detail can prefill.
class RecurringPrefill {
  const RecurringPrefill({
    required this.name,
    required this.amount,
    required this.kind,
    this.frequency = Frequency.monthly,
    this.payee,
    this.categoryId,
    this.budgetId,
  });

  final String name;
  final double amount;
  final TxKind kind;
  final Frequency frequency;
  final String? payee;
  final String? categoryId;
  final String? budgetId;
}

Future<bool?> showRecurringForm(
  BuildContext context, {
  RecurringRule? existing,
  RecurringPrefill? prefill,
  String? presetBudgetId,
}) {
  return showAppSheet<bool>(
    context,
    title: existing == null ? 'New recurring rule' : 'Edit rule',
    builder: (ctx) => RecurringForm(
      existing: existing,
      prefill: prefill,
      presetBudgetId: presetBudgetId,
    ),
  );
}

class RecurringForm extends StatefulWidget {
  const RecurringForm({
    super.key,
    this.existing,
    this.prefill,
    this.presetBudgetId,
  });

  final RecurringRule? existing;
  final RecurringPrefill? prefill;
  final String? presetBudgetId;

  @override
  State<RecurringForm> createState() => _RecurringFormState();
}

class _RecurringFormState extends State<RecurringForm> {
  late final _name = TextEditingController(
    text: widget.existing?.name ?? widget.prefill?.name ?? '',
  );
  late final _amount = TextEditingController(
    text: widget.existing != null
        ? toNum(widget.existing!.amount).toString()
        : widget.prefill != null
        ? widget.prefill!.amount.toStringAsFixed(2)
        : '',
  );
  late final _interval = TextEditingController(
    text: '${widget.existing?.interval ?? 1}',
  );
  late final _payee = TextEditingController(
    text: widget.existing?.payee ?? widget.prefill?.payee ?? '',
  );
  late final _note = TextEditingController(text: widget.existing?.note ?? '');

  late TxKind _kind =
      widget.existing?.kind ?? widget.prefill?.kind ?? TxKind.expense;
  late Frequency _frequency =
      widget.existing?.frequency ??
      widget.prefill?.frequency ??
      Frequency.monthly;
  late String? _accountId = widget.existing?.accountId;
  late String? _categoryId =
      widget.existing?.categoryId ?? widget.prefill?.categoryId;
  late String? _budgetId =
      widget.existing?.budgetId ??
      widget.prefill?.budgetId ??
      widget.presetBudgetId;
  late DateTime _nextRun = widget.existing?.nextRun ?? DateTime.now();
  late DateTime? _endDate = widget.existing?.endDate;
  late bool _autoPost = widget.existing?.autoPost ?? true;
  late bool _active = widget.existing?.active ?? true;

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  List<BudgetRow> _spendablePlans(DataState data) {
    final currency = widget.existing?.currency ?? data.activeCurrency;
    return (data.budgets.data?.items ?? const <BudgetRow>[])
        .where(
          (b) =>
              !b.isUnplanned &&
              !b.isClosed &&
              !b.type.isSaving &&
              b.currency == currency,
        )
        .toList();
  }

  void _applyPlan(BudgetRow? plan, DataState data) {
    _budgetId = plan?.id;
    if (plan == null) return;
    if (plan.categoryId != null) _categoryId = plan.categoryId;
    final sources = (data.spendSources.data ?? const <BudgetSpendSource>[])
        .where((s) => s.id == plan.id)
        .firstOrNull
        ?.sources
        .where((s) => s.account != null)
        .toList();
    if (sources != null && sources.isNotEmpty) {
      sources.sort((a, b) {
        final aa = double.tryParse(a.available) ?? 0;
        final bb = double.tryParse(b.available) ?? 0;
        return bb.compareTo(aa);
      });
      _accountId = sources.first.account!.id;
    }
  }

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final data = context.read<DataState>();
      await Future.wait([
        data.loadAccounts(),
        data.loadCategories(),
        data.loadBudgets(),
        data.loadSpendSources(force: true),
      ]);
      if (!mounted) return;
      setState(() {
        if (_accountId == null) {
          final accounts = data.scopedAccounts;
          final fallback =
              accounts.where((a) => a.isDefault).firstOrNull ??
              accounts.firstOrNull;
          _accountId = fallback?.id;
        }
        if (_kind == TxKind.expense && _budgetId != null) {
          final plan = _spendablePlans(
            data,
          ).where((b) => b.id == _budgetId).firstOrNull;
          if (plan != null) _applyPlan(plan, data);
        }
      });
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _interval.dispose();
    _payee.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the rule a name.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    if (_accountId == null) {
      setState(() => _error = 'Pick the account it posts to.');
      return;
    }
    if (_categoryId == null) {
      setState(() => _error = 'Pick a category.');
      return;
    }
    if (_kind == TxKind.expense && (_budgetId == null || _budgetId!.isEmpty)) {
      setState(() => _error = 'A recurring expense must spend from a plan.');
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
      'amount': amount,
      'accountId': _accountId,
      'categoryId': _categoryId,
      'frequency': _frequency.wire,
      'interval': int.tryParse(_interval.text.trim()) ?? 1,
      'nextRun': wireDate(_nextRun),
      'autoPost': _autoPost,
      if (_frequency == Frequency.monthly) 'dayOfMonth': _nextRun.day,
      if (_payee.text.trim().isNotEmpty) 'payee': _payee.text.trim(),
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      if (_endDate != null) 'endDate': wireDate(_endDate!),
      if (!_isEdit) 'currency': data.activeCurrency,
      if (_isEdit) 'active': _active,
      if (_kind == TxKind.expense) 'budgetId': _budgetId,
      if (_kind == TxKind.income) 'budgetId': null,
    };

    try {
      if (_isEdit) {
        await api.put('/recurring/${widget.existing!.id}', body: body);
      } else {
        await api.post('/recurring', body: body);
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
    final accounts = data.scopedAccounts;
    final categories = data.categoriesOfKind(_kind);
    final plans = _spendablePlans(data);
    final selectedPlan = plans.where((b) => b.id == _budgetId).firstOrNull;
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    final potShort =
        _kind == TxKind.expense &&
        selectedPlan != null &&
        amount > toNum(selectedPlan.balance);

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
          SegmentedTabs<TxKind>(
            value: _kind,
            options: const [TxKind.expense, TxKind.income],
            labelOf: (k) => k.label,
            colorOf: (k) => k == TxKind.income ? t.success : t.danger,
            iconOf: (k) => k == TxKind.income
                ? Icons.south_west_rounded
                : Icons.north_east_rounded,
            onChanged: (k) => setState(() {
              _kind = k;
              _categoryId = null;
              if (k == TxKind.income) _budgetId = null;
            }),
          ),
          const Gap(S.lg),
          AppTextField(
            controller: _name,
            label: 'Name',
            placeholder: _kind == TxKind.income ? 'Salary' : 'Rent',
            prefixIcon: Icons.badge_outlined,
            autofocus: !_isEdit,
          ),
          const Gap(S.lg),
          AmountField(
            controller: _amount,
            currency: widget.existing?.currency ?? data.activeCurrency,
            tint: _kind == TxKind.income ? t.success : t.danger,
          ),
          const Gap(S.lg),
          if (_kind == TxKind.expense) ...[
            PickerField<BudgetRow>(
              label: 'Pay from plan',
              hint:
                  'Every recurring spend draws from a spending plan — '
                  'one-time or recurring envelopes both work.',
              value: selectedPlan,
              options: plans,
              labelOf: (b) =>
                  '${b.name} · ${formatMoney(b.balance, currency: b.currency)} left',
              iconOf: (b) => financeIcon(b.icon),
              colorOf: (b) => parseHexColor(b.color) ?? t.primary,
              onChanged: (b) => setState(() => _applyPlan(b, data)),
              placeholder: plans.isEmpty
                  ? 'Create a spending plan first'
                  : 'Pick a plan',
              sheetTitle: 'Pay from',
            ),
            if (potShort) ...[
              const Gap(S.sm),
              Text(
                'This plan has less than the rule amount right now. '
                'Fund it before the due date or the run will be held.',
                style: TextStyle(
                  fontSize: AppType.caption,
                  color: t.warning,
                  height: 1.35,
                ),
              ),
            ],
            const Gap(S.lg),
          ],
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
                child: PickerField<Frequency>(
                  label: 'Frequency',
                  value: _frequency,
                  options: Frequency.values,
                  labelOf: (f) => f.label,
                  onChanged: (f) =>
                      setState(() => _frequency = f ?? _frequency),
                ),
              ),
            ],
          ),
          const Gap(S.lg),
          DateField(
            label: 'Next run',
            hint:
                'The first date it posts. Later runs step forward by the cadence.',
            value: _nextRun,
            onChanged: (d) => setState(() => _nextRun = d ?? _nextRun),
          ),
          const Gap(S.lg),
          PickerField<Account>(
            label: _kind == TxKind.expense ? 'Take it out of' : 'Into account',
            value: accounts.where((a) => a.id == _accountId).firstOrNull,
            options: accounts,
            labelOf: (a) => a.name,
            iconOf: (a) => accountTypeIcon(a.type.wire),
            colorOf: (a) => parseHexColor(a.color) ?? t.mutedForeground,
            onChanged: (a) => setState(() => _accountId = a?.id),
          ),
          const Gap(S.lg),
          PickerField<TxCategory>(
            label: 'Category',
            value: categories.where((c) => c.id == _categoryId).firstOrNull,
            options: categories,
            labelOf: (c) => c.name,
            iconOf: (c) => financeIcon(c.icon),
            colorOf: (c) => parseHexColor(c.color) ?? t.mutedForeground,
            onChanged: (c) => setState(() => _categoryId = c?.id),
          ),
          const Gap(S.lg),
          DateField(
            label: 'Ends',
            placeholder: 'Runs forever',
            value: _endDate,
            allowClear: true,
            firstDate: _nextRun,
            onChanged: (d) => setState(() => _endDate = d),
          ),
          const Gap(S.sm),
          SwitchRow(
            title: 'Post automatically',
            subtitle: 'Writes the transaction the moment it comes due.',
            icon: Icons.bolt_outlined,
            value: _autoPost,
            onChanged: (v) => setState(() => _autoPost = v),
          ),
          if (_isEdit)
            SwitchRow(
              title: 'Active',
              subtitle: 'Paused rules never post.',
              icon: Icons.play_circle_outline,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          const Gap(S.sm),
          AppTextField(
            controller: _payee,
            label: 'Payee',
            placeholder: 'Optional',
            prefixIcon: Icons.storefront_outlined,
          ),
          const Gap(S.lg),
          AppTextField(
            controller: _note,
            label: 'Note',
            placeholder: 'Optional',
            maxLines: 2,
            prefixIcon: Icons.notes_outlined,
          ),
          if (_error != null) ...[
            const Gap(S.md),
            Text(
              _error!,
              style: TextStyle(fontSize: AppType.bodySm, color: t.danger),
            ),
          ],
          const Gap(S.xl),
          AppButton(
            label: _isEdit ? 'Save changes' : 'Create rule',
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
