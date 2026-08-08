import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/theme.dart';
import '../state/data_store.dart';
import '../widgets/common.dart';
import '../widgets/web_chrome.dart';

Future<bool?> showTransferSheet(BuildContext context) {
  return showSantimSheet<bool>(
    context: context,
    title: 'Transfer between accounts',
    builder: (_) => const TransferFormBody(),
  );
}

class TransferFormBody extends StatefulWidget {
  const TransferFormBody({super.key});

  @override
  State<TransferFormBody> createState() => _TransferFormBodyState();
}

class _TransferFormBodyState extends State<TransferFormBody> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late DateTime _date;
  String? _from;
  String? _to;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    final accounts = context.read<DataStore>().activeAccounts.toList();
    _from = accounts.where((a) => a.isDefault).firstOrNull?.id ?? accounts.firstOrNull?.id;
    _to = accounts.where((a) => a.id != _from).firstOrNull?.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<DataStore>().activeAccounts.toList();
    final colors = Theme.of(context).extension<SantimColors>()!;

    if (accounts.length < 2) {
      return Text(
        'You need at least two wallets to transfer.',
        style: TextStyle(color: colors.muted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SantimSelect<String>(
                label: 'From',
                value: _from,
                items: [for (final a in accounts) MapEntry(a.id, a.name)],
                onChanged: (v) => setState(() {
                  _from = v;
                  if (_to == _from) {
                    _to = accounts.where((a) => a.id != _from).firstOrNull?.id;
                  }
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SantimSelect<String>(
                label: 'To',
                value: _to,
                items: [for (final a in accounts) MapEntry(a.id, a.name)],
                onChanged: (v) => setState(() => _to = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
          decoration: const InputDecoration(labelText: 'Amount', hintText: '0.00'),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2015),
              lastDate: DateTime.now(),
            );
            if (picked != null) setState(() => _date = picked);
          },
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Date'),
            child: Text(DateFormat('yyyy-MM-dd').format(_date)),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _note,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Note', hintText: 'Optional…'),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: const Text('Transfer'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_from == null || _to == null) return;
    if (_from == _to) {
      showError(context, 'Choose two different accounts');
      return;
    }
    final amount = double.tryParse(_amount.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      showError(context, 'Enter an amount');
      return;
    }
    final data = context.read<DataStore>();
    final fromAccount = data.accountById(_from);
    setState(() => _busy = true);
    try {
      final sent = await data.createTransfer(
        fromAccountId: _from!,
        toAccountId: _to!,
        amount: amount,
        currency: fromAccount?.currency ?? 'ETB',
        date: DateFormat('yyyy-MM-dd').format(_date),
        note: _note.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      showOk(context, sent ? 'Transfer recorded' : 'Transfer saved offline — will sync later');
      await data.refreshAll();
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
