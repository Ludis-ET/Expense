import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/formatting.dart';
import '../core/theme.dart';
import '../state/data_store.dart';
import '../widgets/common.dart';
import '../widgets/web_chrome.dart';

const _planPrefix = 'plan:';

Future<bool?> showTransactionFormSheet(
  BuildContext context, {
  String initialKind = 'EXPENSE',
  String? initialAmount,
  String? initialPayee,
  DateTime? initialDate,
  String? initialAccountId,
}) {
  return showSantimSheet<bool>(
    context: context,
    title: 'Add transaction',
    builder: (ctx) => TransactionFormBody(
      initialKind: initialKind,
      initialAmount: initialAmount,
      initialPayee: initialPayee,
      initialDate: initialDate,
      initialAccountId: initialAccountId,
    ),
  );
}

/// Website-matching add form (modal body).
class TransactionFormBody extends StatefulWidget {
  const TransactionFormBody({
    super.key,
    this.initialKind = 'EXPENSE',
    this.initialAmount,
    this.initialPayee,
    this.initialDate,
    this.initialAccountId,
  });

  final String initialKind;
  final String? initialAmount;
  final String? initialPayee;
  final DateTime? initialDate;
  final String? initialAccountId;

  @override
  State<TransactionFormBody> createState() => _TransactionFormBodyState();
}

class _TransactionFormBodyState extends State<TransactionFormBody> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _payee;
  final _note = TextEditingController();
  final _tags = TextEditingController();

  late String _kind;
  late DateTime _date;
  String _source = '';
  String? _drawFromId;
  String? _categoryId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind == 'INCOME' ? 'INCOME' : 'EXPENSE';
    _date = widget.initialDate ?? DateTime.now();
    _amount = TextEditingController(text: widget.initialAmount ?? '');
    _payee = TextEditingController(text: widget.initialPayee ?? '');
    final data = context.read<DataStore>();
    _drawFromId = widget.initialAccountId ??
        data.activeAccounts.where((a) => a.isDefault).firstOrNull?.id ??
        data.activeAccounts.firstOrNull?.id;
    final unplanned = data.budgets.where((b) => b.isUnplanned).firstOrNull;
    if (_kind == 'EXPENSE' && unplanned != null) {
      _source = '$_planPrefix${unplanned.id}';
    } else if (_kind == 'INCOME') {
      _source = _drawFromId ?? '';
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _payee.dispose();
    _note.dispose();
    _tags.dispose();
    super.dispose();
  }

  void _setKind(String kind) {
    final data = context.read<DataStore>();
    setState(() {
      _kind = kind;
      _categoryId = null;
      if (kind == 'EXPENSE') {
        final unplanned = data.budgets.where((b) => b.isUnplanned).firstOrNull;
        _source = unplanned != null ? '$_planPrefix${unplanned.id}' : '';
      } else {
        _source = data.activeAccounts.where((a) => a.isDefault).firstOrNull?.id ??
            data.activeAccounts.firstOrNull?.id ??
            '';
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final data = context.read<DataStore>();
    final isPlan = _source.startsWith(_planPrefix);
    final accountId = isPlan ? _drawFromId : _source;
    if (_kind == 'EXPENSE' && !isPlan) {
      showError(context, 'Pick a plan');
      return;
    }
    if (accountId == null || accountId.isEmpty) {
      showError(context, _kind == 'EXPENSE' ? 'Pick which account this comes out of' : 'Pick an account');
      return;
    }
    if (_categoryId == null) {
      showError(context, 'Pick a category');
      return;
    }

    setState(() => _busy = true);
    final tagList = _tags.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    final currency = data.accountById(accountId)?.currency ?? 'ETB';

    try {
      final body = <String, dynamic>{
        'kind': _kind,
        'amount': double.parse(_amount.text.replaceAll(',', '')),
        'currency': currency,
        'date': DateFormat('yyyy-MM-dd').format(_date),
        'accountId': accountId,
        'categoryId': _categoryId,
        if (isPlan) 'budgetId': _source.substring(_planPrefix.length),
        if (_payee.text.trim().isNotEmpty) 'payee': _payee.text.trim(),
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
        if (tagList.isNotEmpty) 'tags': tagList,
      };
      final sent = await data.createTransaction(body);
      if (!mounted) return;
      Navigator.pop(context, true);
      showOk(context, sent ? 'Transaction added' : 'Saved offline — will sync when you reconnect');
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } on NetworkException {
      if (mounted) showError(context, 'Could not save. Check your connection.');
    } catch (_) {
      if (mounted) showError(context, 'Could not save. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final colors = Theme.of(context).extension<SantimColors>()!;
    final categories = (_kind == 'INCOME' ? data.incomeCategories : data.expenseCategories).toList();
    final accounts = data.activeAccounts.toList();
    final plans = data.spendableBudgets.toList();
    final unplanned = data.budgets.where((b) => b.isUnplanned).firstOrNull;
    final isPlan = _source.startsWith(_planPrefix);
    final selectedPlan = isPlan
        ? data.budgets.where((b) => b.id == _source.substring(_planPrefix.length)).firstOrNull
        : null;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final k in ['EXPENSE', 'INCOME'])
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: k == 'EXPENSE' ? 8 : 0),
                    child: InkWell(
                      onTap: () => _setKind(k),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _kind == k
                                ? (k == 'INCOME' ? colors.success : colors.primary)
                                : colors.border,
                          ),
                          color: _kind == k
                              ? (k == 'INCOME' ? colors.success : colors.primary).withValues(alpha: 0.1)
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          k == 'EXPENSE' ? 'Expense' : 'Income',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: _kind == k
                                ? (k == 'INCOME' ? colors.success : colors.primary)
                                : colors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
                  decoration: const InputDecoration(labelText: 'Amount', hintText: '0.00'),
                  validator: (v) {
                    final parsed = double.tryParse((v ?? '').replaceAll(',', ''));
                    if (parsed == null || parsed <= 0) return 'Enter an amount';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date'),
                    child: Text(DateFormat('yyyy-MM-dd').format(_date)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_kind == 'EXPENSE') ...[
            SantimSelect<String>(
              label: 'Pay from',
              value: _source.isEmpty ? null : _source,
              hint: 'Pick a plan',
              items: [
                for (final b in plans.where((b) => !b.isUnplanned))
                  MapEntry(
                    '$_planPrefix${b.id}',
                    '${b.name} — ${Money.format(b.potBalance, currency: b.currency)} left',
                  ),
                if (unplanned != null)
                  MapEntry('$_planPrefix${unplanned.id}', unplanned.name),
              ],
              onChanged: (v) => setState(() {
                _source = v ?? '';
                final plan = plans.where((b) => '$_planPrefix${b.id}' == _source).firstOrNull;
                // Keep draw-from account valid.
                _drawFromId ??= accounts.where((a) => a.isDefault).firstOrNull?.id ?? accounts.firstOrNull?.id;
                if (plan != null) {/* category may follow later */}
              }),
            ),
            const SizedBox(height: 14),
            SantimSelect<String>(
              label: 'Take it out of',
              value: _drawFromId,
              hint: 'Account',
              items: [
                for (final a in accounts)
                  MapEntry(
                    a.id,
                    '${a.name} — ${Money.format(a.available, currency: a.currency)} available',
                  ),
              ],
              onChanged: (v) => setState(() => _drawFromId = v),
            ),
            if (selectedPlan != null && !selectedPlan.isUnplanned) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.account_balance_wallet_outlined, size: 14, color: colors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Comes out of the money already set aside in ${selectedPlan.name}',
                        style: TextStyle(fontSize: 12, color: colors.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ] else
            SantimSelect<String>(
              label: 'Deposit to',
              value: _source.isEmpty ? null : _source,
              hint: 'Account',
              items: [
                for (final a in accounts)
                  MapEntry(
                    a.id,
                    '${a.name} — ${Money.format(a.available, currency: a.currency)} available',
                  ),
              ],
              onChanged: (v) => setState(() => _source = v ?? ''),
            ),
          const SizedBox(height: 14),
          SantimSelect<String>(
            label: 'Category',
            value: _categoryId,
            hint: 'Pick a category',
            items: [for (final c in categories) MapEntry(c.id, c.name)],
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _payee,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Payee', hintText: 'Who / where'),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _note,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Note'),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _tags,
            decoration: const InputDecoration(labelText: 'Tags', hintText: 'comma, separated'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }
}

/// Full-page wrapper kept for SMS review deep links.
class TransactionForm extends StatelessWidget {
  const TransactionForm({
    super.key,
    this.initialKind = 'EXPENSE',
    this.initialAmount,
    this.initialPayee,
    this.initialDate,
    this.initialAccountId,
  });

  final String initialKind;
  final String? initialAmount;
  final String? initialPayee;
  final DateTime? initialDate;
  final String? initialAccountId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add transaction')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          TransactionFormBody(
            initialKind: initialKind,
            initialAmount: initialAmount,
            initialPayee: initialPayee,
            initialDate: initialDate,
            initialAccountId: initialAccountId,
          ),
        ],
      ),
    );
  }
}
