import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/formatting.dart';
import '../core/theme.dart';
import '../models/finance.dart';
import '../state/data_store.dart';
import '../widgets/common.dart';

/// Add an income or expense by hand.
///
/// Prefilled variants of this form are what the SMS review sheet reuses, so
/// everything here takes optional initial values.
class TransactionForm extends StatefulWidget {
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
  State<TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<TransactionForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _payee;
  final _note = TextEditingController();

  late String _kind;
  late DateTime _date;
  String? _accountId;
  String? _categoryId;
  String? _budgetId;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _date = widget.initialDate ?? DateTime.now();
    _amount = TextEditingController(text: widget.initialAmount ?? '');
    _payee = TextEditingController(text: widget.initialPayee ?? '');

    final data = context.read<DataStore>();
    _accountId = widget.initialAccountId ??
        data.activeAccounts.where((a) => a.isDefault).firstOrNull?.id ??
        data.activeAccounts.firstOrNull?.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _payee.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Switching direction invalidates the category, since the API rejects a
  /// category whose kind does not match the transaction.
  void _setKind(String kind) {
    setState(() {
      _kind = kind;
      _categoryId = null;
      if (kind == 'INCOME') _budgetId = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    final data = context.read<DataStore>();

    try {
      final sent = await data.createTransaction({
        'kind': _kind,
        'amount': double.parse(_amount.text.replaceAll(',', '')),
        'currency': 'ETB',
        'date': _date.toUtc().toIso8601String(),
        'accountId': _accountId,
        'categoryId': _categoryId,
        if (_budgetId != null) 'budgetId': _budgetId,
        if (_payee.text.trim().isNotEmpty) 'payee': _payee.text.trim(),
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      });

      if (!mounted) return;
      Navigator.pop(context, true);
      showOk(context, sent ? 'Saved' : 'Saved offline — will sync when you are back online');
    } on ApiException catch (e) {
      // The overdraw guard's message names the account and the shortfall, so
      // it is far more useful than anything generic we could substitute.
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
    final categories = _kind == 'INCOME' ? data.incomeCategories : data.expenseCategories;

    return Scaffold(
      appBar: AppBar(title: const Text('Add transaction')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'EXPENSE', label: Text('Money out'), icon: Icon(Icons.north_east)),
                ButtonSegment(value: 'INCOME', label: Text('Money in'), icon: Icon(Icons.south_west)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => _setKind(s.first),
            ),
            const SizedBox(height: 20),

            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(labelText: 'Amount', prefixText: 'Br  '),
              validator: (v) {
                final parsed = double.tryParse((v ?? '').replaceAll(',', ''));
                if (parsed == null || parsed <= 0) return 'Enter an amount above zero';
                return null;
              },
            ),
            const SizedBox(height: 16),

            _AccountPicker(
              accounts: data.activeAccounts.toList(),
              value: _accountId,
              onChanged: (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final c in categories)
                  DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
              validator: (v) => v == null ? 'Pick a category' : null,
            ),

            if (_kind == 'EXPENSE') ...[
              const SizedBox(height: 16),
              _BudgetPicker(
                budgets: data.spendableBudgets.toList(),
                value: _budgetId,
                onChanged: (v) => setState(() => _budgetId = v),
              ),
            ],

            const SizedBox(height: 16),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              leading: const Icon(Icons.event_outlined),
              title: const Text('Date'),
              subtitle: Text(Dates.full(_date)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickDate,
            ),

            const SizedBox(height: 16),
            TextFormField(
              controller: _payee,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Who / where',
                hintText: 'Shoa Supermarket',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Note'),
            ),

            const SizedBox(height: 26),
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

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );

    setState(() {
      _date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        time?.hour ?? _date.hour,
        time?.minute ?? _date.minute,
      );
    });
  }
}

/// Account dropdown showing each wallet's *available* balance, so an overdraw
/// is visible before the server has to refuse it.
class _AccountPicker extends StatelessWidget {
  const _AccountPicker({required this.accounts, required this.value, required this.onChanged});

  final List<Account> accounts;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Account'),
      items: [
        for (final a in accounts)
          DropdownMenuItem(
            value: a.id,
            child: Row(
              children: [
                Expanded(child: Text(a.name, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Text(
                  Money.format(a.available, currency: a.currency),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
      onChanged: onChanged,
      validator: (v) => v == null ? 'Pick an account' : null,
    );
  }
}

/// Optional plan to pay from. Choosing one spends reserved money instead of
/// free money, which is a different thing entirely - hence the hint.
class _BudgetPicker extends StatelessWidget {
  const _BudgetPicker({required this.budgets, required this.value, required this.onChanged});

  final List<Budget> budgets;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (budgets.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Pay from a plan (optional)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('No plan — pay from the account')),
              for (final b in budgets)
                DropdownMenuItem(
                  value: b.id,
                  child: Row(
                    children: [
                      Expanded(child: Text(b.name, overflow: TextOverflow.ellipsis)),
                      if (!b.isUnplanned) ...[
                        const SizedBox(width: 8),
                        Text(
                          Money.format(b.potBalance, currency: b.currency),
                          style: const TextStyle(fontSize: 12, color: SantimTheme.income),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
        ),
        const InfoHint(
          title: 'Paying from a plan',
          message:
              'A plan holds money you already set aside. Spending from it uses that '
              'reservation instead of your free balance — the cash still leaves the '
              'account you picked above.',
        ),
      ],
    );
  }
}
