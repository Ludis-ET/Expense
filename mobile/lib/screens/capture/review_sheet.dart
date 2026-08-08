import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatting.dart';
import '../../models/ingest.dart';
import '../../state/capture_store.dart';
import '../../state/data_store.dart';
import '../../widgets/common.dart';

/// Confirm, correct, or dismiss one captured bank message.
///
/// Everything the parser read is pre-filled and every field is editable - the
/// parser is a first draft, not an authority. Confirming routes through the
/// normal transaction endpoint, so the overdraw guard and budget reservations
/// behave exactly as they would for a hand-typed entry.
class ReviewSheet extends StatefulWidget {
  const ReviewSheet({super.key, required this.message});

  final InboxMessage message;

  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<ReviewSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _payee;

  late String _kind;
  late DateTime _date;
  String? _accountId;
  String? _categoryId;
  String? _budgetId;
  bool _remember = false;
  bool _busy = false;
  bool _showRaw = false;

  @override
  void initState() {
    super.initState();
    final m = widget.message;
    final data = context.read<DataStore>();

    _kind = m.parsedKind ?? 'EXPENSE';
    _date = m.effectiveDate;
    _amount = TextEditingController(text: m.parsedAmount ?? '');
    _payee = TextEditingController(text: m.parsedPayee ?? '');

    // Account precedence: what the sender rule already mapped, else the
    // default wallet. Category is left blank on purpose - guessing it wrong is
    // worse than asking, because it silently distorts every report.
    _accountId = m.accountId ??
        data.activeAccounts.where((a) => a.isDefault).firstOrNull?.id ??
        data.activeAccounts.firstOrNull?.id;

    final rule = context
        .read<CaptureStore>()
        .senderRules
        .where((r) => r.sender == m.sender)
        .firstOrNull;
    _categoryId = rule?.defaultCategoryId;
  }

  @override
  void dispose() {
    _amount.dispose();
    _payee.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      showError(context, 'Enter an amount above zero');
      return;
    }
    if (_accountId == null) {
      showError(context, 'Pick which account this belongs to');
      return;
    }
    if (_categoryId == null) {
      showError(context, 'Pick a category');
      return;
    }

    setState(() => _busy = true);
    final capture = context.read<CaptureStore>();
    final data = context.read<DataStore>();

    try {
      await capture.confirm(widget.message.id, {
        'kind': _kind,
        'amount': amount,
        'currency': widget.message.parsedCurrency ?? 'ETB',
        'date': _date.toUtc().toIso8601String(),
        'accountId': _accountId,
        'categoryId': _categoryId,
        if (_budgetId != null) 'budgetId': _budgetId,
        if (_payee.text.trim().isNotEmpty) 'payee': _payee.text.trim(),
        'rememberMapping': _remember,
      });

      // The ledger moved, so balances and plan pots are now stale.
      await data.refreshAfterLedgerChange();

      if (!mounted) return;
      Navigator.pop(context);
      showOk(context, 'Recorded');
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } catch (_) {
      if (mounted) showError(context, 'Could not save. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _busy = true);
    try {
      await context.read<CaptureStore>().reject(widget.message.id);
      if (!mounted) return;
      Navigator.pop(context);
      showOk(context, 'Dismissed');
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = context.watch<DataStore>();
    final m = widget.message;
    final categories = _kind == 'INCOME' ? data.incomeCategories : data.expenseCategories;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    m.bankLabel ?? m.sender,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  Dates.relative(m.receivedAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _RawMessage(
              body: m.body,
              expanded: _showRaw,
              onToggle: () => setState(() => _showRaw = !_showRaw),
            ),

            if (m.parsedBalance != null) ...[
              const SizedBox(height: 10),
              _BalanceNote(
                reported: m.parsedBalance!,
                currency: m.parsedCurrency ?? 'ETB',
              ),
            ],

            const SizedBox(height: 20),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'EXPENSE', label: Text('Money out')),
                ButtonSegment(value: 'INCOME', label: Text('Money in')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() {
                _kind = s.first;
                // Category kind must match the direction, so it cannot survive
                // a flip.
                _categoryId = null;
                if (_kind == 'INCOME') _budgetId = null;
              }),
            ),

            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(labelText: 'Amount', prefixText: 'Br  '),
            ),

            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Account'),
              items: [
                for (final a in data.activeAccounts)
                  DropdownMenuItem(
                    value: a.id,
                    child: Row(
                      children: [
                        Expanded(child: Text(a.name, overflow: TextOverflow.ellipsis)),
                        Text(
                          Money.format(a.available, currency: a.currency),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _accountId = v),
            ),

            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final c in categories)
                  DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),

            if (_kind == 'EXPENSE' && data.spendableBudgets.isNotEmpty) ...[
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _budgetId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Pay from a plan (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('No plan')),
                  for (final b in data.spendableBudgets)
                    DropdownMenuItem(value: b.id, child: Text(b.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _budgetId = v),
              ),
            ],

            const SizedBox(height: 14),
            TextField(
              controller: _payee,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Who / where'),
            ),

            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Date'),
              subtitle: Text(Dates.full(_date)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickDate,
            ),

            const Divider(height: 26),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _remember,
              onChanged: (v) => setState(() => _remember = v),
              title: const Text('Remember this for future messages'),
              subtitle: Text(
                'Messages from ${m.sender} will pre-fill this account and category.',
                style: theme.textTheme.bodySmall,
              ),
            ),

            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _confirm,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Text('Record it'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _reject,
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              child: const Text('Not a transaction — dismiss'),
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
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _date = DateTime(
            picked.year,
            picked.month,
            picked.day,
            _date.hour,
            _date.minute,
          ));
    }
  }
}

/// The original SMS, collapsed. Worth keeping one tap away: when a parse looks
/// wrong, the raw text is the only thing that settles it.
class _RawMessage extends StatelessWidget {
  const _RawMessage({required this.body, required this.expanded, required this.onToggle});

  final String body;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onToggle,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              body,
              maxLines: expanded ? null : 3,
              overflow: expanded ? null : TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              expanded ? 'Tap to collapse' : 'Tap to see the full message',
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the bank said the balance was afterwards.
///
/// Santim does not write this anywhere - balances here are derived from the
/// ledger, and overwriting them from an SMS would paper over the very gaps
/// worth noticing. Showing it lets the user spot a mismatch themselves.
class _BalanceNote extends StatelessWidget {
  const _BalanceNote({required this.reported, required this.currency});

  final String reported;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(Icons.account_balance_outlined, size: 15, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Bank reported a balance of ${Money.format(reported, currency: currency)} after this',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const InfoHint(
          title: 'Reported balance',
          message:
              'Santim works out your balances from the transactions you record, so it does '
              'not overwrite them with this figure. If the two drift apart, something is '
              'missing from your ledger — which is worth knowing about.',
        ),
      ],
    );
  }
}
