import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatting.dart';
import '../../core/native_ingest.dart';
import '../../core/theme.dart';
import '../../models/ingest.dart';
import '../../state/capture_store.dart';
import '../../state/data_store.dart';
import '../../widgets/common.dart';

/// Pick which SMS senders on this phone are banks.
///
/// The list comes off the handset rather than from a hardcoded table, because
/// sender ids vary by carrier and change without notice. Showing the user their
/// own inbox - with a sample message and a guessed bank name - turns a guessing
/// game into recognition.
class SenderPickerScreen extends StatefulWidget {
  const SenderPickerScreen({super.key});

  @override
  State<SenderPickerScreen> createState() => _SenderPickerScreenState();
}

class _SenderPickerScreenState extends State<SenderPickerScreen> {
  List<InboxSender> _senders = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await context.read<CaptureStore>().loadBanks();
      final senders = await NativeIngest.listInboxSenders();
      if (!mounted) return;
      setState(() {
        _senders = senders;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not read the SMS inbox. Check the SMS permission.';
        _loading = false;
      });
    }
  }

  /// Adds a sender the inbox scan did not turn up.
  ///
  /// Needed because the scan only sees messages already on the phone — a bank
  /// you have not been texted by yet, or one whose messages were deleted,
  /// would otherwise be unreachable.
  Future<void> _addManualSender(BuildContext context) async {
    final controller = TextEditingController();
    final capture = context.read<CaptureStore>();

    final sender = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a messaging point'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Sender ID',
                hintText: 'CBE',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Exactly as it appears in your Messages app — the name or shortcode '
              'the texts come from.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (sender == null || sender.isEmpty) return;
    try {
      await capture.upsertSenderRule(
        sender: sender,
        bankKey: capture.bankKeyForSender(sender),
      );
      if (context.mounted) showOk(context, 'Watching $sender');
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final capture = context.watch<CaptureStore>();
    final approved = {for (final r in capture.senderRules) r.sender: r};

    // A hand-added sender has no messages on the phone yet, so the inbox scan
    // will not turn it up. Merge those in or they would vanish from the list
    // the moment they were created.
    final scanned = {for (final s in _senders) s.sender};
    final manual = capture.senderRules
        .where((r) => !scanned.contains(r.sender))
        .map((r) => InboxSender(
              sender: r.sender,
              messageCount: 0,
              lastMessageAt: null,
              samples: const [],
            ));

    // Anything the server recognises as a bank floats to the top; the rest stay
    // in most-messages order so a missed bank is still easy to find.
    final sorted = [..._senders, ...manual]..sort((a, b) {
        final aOn = approved[a.sender]?.enabled ?? false;
        final bOn = approved[b.sender]?.enabled ?? false;
        if (aOn != bOn) return aOn ? -1 : 1;

        final aKnown = capture.bankLabelForSender(a.sender) != null;
        final bKnown = capture.bankLabelForSender(b.sender) != null;
        if (aKnown != bKnown) return aKnown ? -1 : 1;
        return b.messageCount.compareTo(a.messageCount);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messaging points'),
        actions: [
          IconButton(
            tooltip: 'Add a sender by hand',
            icon: const Icon(Icons.add),
            onPressed: () => _addManualSender(context),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(
                  icon: Icons.lock_outline,
                  title: 'Cannot read messages',
                  message: _error,
                  action: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(160, 46)),
                    onPressed: _load,
                    child: const Text('Try again'),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  children: [
                    Text(
                      'Turn on the senders that are your banks. Messages from anyone '
                      'else never leave this phone.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 16),
                    if (sorted.isEmpty)
                      const EmptyState(
                        icon: Icons.sms_outlined,
                        title: 'No messages found',
                        message: 'This phone has no SMS to scan yet.',
                      ),
                    for (final s in sorted)
                      _SenderTile(
                        sender: s,
                        rule: approved[s.sender],
                        bankLabel: capture.bankLabelForSender(s.sender),
                      ),
                  ],
                ),
    );
  }
}

class _SenderTile extends StatelessWidget {
  const _SenderTile({required this.sender, required this.rule, required this.bankLabel});

  final InboxSender sender;
  final SenderRule? rule;

  /// Null when the server catalog does not recognise this sender.
  final String? bankLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capture = context.read<CaptureStore>();
    final enabled = rule?.enabled ?? false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              bankLabel ?? sender.sender,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (bankLabel != null) ...[
                            const SizedBox(width: 8),
                            const StatusPill(label: 'Known bank', tone: PillTone.good),
                          ],
                        ],
                      ),
                      Text(
                        '${sender.sender} · ${sender.messageCount} messages · '
                        'last ${Dates.relative(sender.lastMessageAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: enabled,
                  onChanged: (value) => _toggle(context, capture, value),
                ),
              ],
            ),

            if (sender.samples.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  sender.samples.first,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],

            if (enabled) ...[
              const SizedBox(height: 12),
              _RuleControls(rule: rule!),
            ],

            if (sender.samples.isNotEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _testParse(context, capture, sender),
                  icon: const Icon(Icons.science_outlined, size: 17),
                  label: const Text('Test how Santim reads it'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, CaptureStore capture, bool value) async {
    try {
      if (rule != null && !value) {
        await capture.deleteSenderRule(rule!.id);
      } else {
        await capture.upsertSenderRule(
          sender: sender.sender,
          bankKey: capture.bankKeyForSender(sender.sender),
          accountId: rule?.accountId,
          defaultCategoryId: rule?.defaultCategoryId,
          enabled: value,
          autoCommit: rule?.autoCommit ?? false,
        );
      }
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e.message);
    }
  }

  /// Runs a real message from this sender through the server's parsers, so a
  /// bad pattern is visible here rather than discovered later in the inbox.
  Future<void> _testParse(
    BuildContext context,
    CaptureStore capture,
    InboxSender sender,
  ) async {
    try {
      final preview = await capture.preview(sender.sender, sender.samples.first);
      if (!context.mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => _PreviewDialog(preview: preview, body: sender.samples.first),
      );
    } on ApiException catch (e) {
      if (context.mounted) showError(context, e.message);
    }
  }
}

/// Account / category mapping and the auto-post switch for one sender.
class _RuleControls extends StatelessWidget {
  const _RuleControls({required this.rule});

  final SenderRule rule;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final capture = context.read<CaptureStore>();
    final theme = Theme.of(context);

    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: rule.accountId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Goes into',
            isDense: true,
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('Ask me each time')),
            for (final a in data.activeAccounts)
              DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => capture.upsertSenderRule(
            sender: rule.sender,
            bankKey: rule.bankKey,
            accountId: v,
            defaultCategoryId: rule.defaultCategoryId,
            enabled: true,
            autoCommit: rule.autoCommit,
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: rule.defaultCategoryId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Default category for spending',
            isDense: true,
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('Ask me each time')),
            for (final c in data.expenseCategories)
              DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => capture.upsertSenderRule(
            sender: rule.sender,
            bankKey: rule.bankKey,
            accountId: rule.accountId,
            defaultCategoryId: v,
            enabled: true,
            autoCommit: rule.autoCommit,
          ),
        ),

        // Teaching Santim this wallet's account number is what lets a
        // "transferred to 1000****4821" message be recognised as a move
        // between the user's own accounts rather than as spending.
        if (rule.accountId != null) ...[
          const SizedBox(height: 6),
          _AccountNumberField(accountId: rule.accountId!),
        ],

        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          // Auto-posting needs somewhere to post to. Without both a wallet and
          // a category the server would only reject it, so the switch stays
          // locked until they are set.
          value: rule.autoCommit && rule.canAutoCommit,
          onChanged: rule.canAutoCommit
              ? (v) => capture.upsertSenderRule(
                    sender: rule.sender,
                    bankKey: rule.bankKey,
                    accountId: rule.accountId,
                    defaultCategoryId: rule.defaultCategoryId,
                    enabled: true,
                    autoCommit: v,
                  )
              : null,
          title: const Text('Record without asking'),
          subtitle: Text(
            rule.canAutoCommit
                ? 'Only for messages Santim reads with high confidence.'
                : 'Set an account and a category first.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// The bank's account number for a wallet, as it appears in SMS.
///
/// Only the last four digits are ever compared, so pasting the masked form
/// straight out of a message is enough. Without it, a transfer between two of
/// the user's own accounts reads as spending and inflates their outgoings.
class _AccountNumberField extends StatefulWidget {
  const _AccountNumberField({required this.accountId});

  final String accountId;

  @override
  State<_AccountNumberField> createState() => _AccountNumberFieldState();
}

class _AccountNumberFieldState extends State<_AccountNumberField> {
  late final TextEditingController _controller;
  String _initial = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _initial = context.read<DataStore>().accountById(widget.accountId)?.accountNumber ?? '';
    _controller = TextEditingController(text: _initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _controller.text.trim();
    if (value == _initial || _saving) return;

    setState(() => _saving = true);
    try {
      await context
          .read<DataStore>()
          .setAccountNumber(widget.accountId, value.isEmpty ? null : value);
      _initial = value;
      if (mounted) showOk(context, 'Account number saved');
    } on ApiException catch (e) {
      if (mounted) showError(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onTapOutside: (_) => _save(),
      onSubmitted: (_) => _save(),
      decoration: InputDecoration(
        isDense: true,
        labelText: 'This wallet’s account number (optional)',
        hintText: '1000****4821',
        suffixIcon: _saving
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : const InfoHint(
                title: 'Why an account number?',
                message:
                    'When a message says money went to another account, Santim compares the '
                    'last four digits against your wallets. If it matches one of your own, it '
                    'offers a transfer instead of recording spending that never happened.',
              ),
      ),
    );
  }
}

class _PreviewDialog extends StatelessWidget {
  const _PreviewDialog({required this.preview, required this.body});

  final ParsePreview preview;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(preview.matched ? 'Santim reads this as' : "Santim can't read this"),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(body, style: theme.textTheme.bodySmall),
            ),
            const SizedBox(height: 16),

            if (!preview.matched)
              Text(
                'It will still land in your inbox so you can record it by hand — nothing '
                'is thrown away.',
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              _Row(
                label: 'Direction',
                value: preview.kind == 'INCOME' ? 'Money in' : 'Money out',
              ),
              _Row(
                label: 'Amount',
                value: Money.format(preview.amount, currency: preview.currency ?? 'ETB'),
              ),
              if (preview.balance != null)
                _Row(
                  label: 'Balance after',
                  value: Money.format(preview.balance, currency: preview.currency ?? 'ETB'),
                ),
              if (preview.payee != null) _Row(label: 'Who', value: preview.payee!),
              if (preview.ref != null) _Row(label: 'Reference', value: preview.ref!),
              _Row(label: 'Confidence', value: '${preview.confidence}%'),

              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    preview.autoCommitEligible ? Icons.bolt : Icons.pan_tool_outlined,
                    size: 16,
                    color: preview.autoCommitEligible ? SantimTheme.income : SantimTheme.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      preview.autoCommitEligible
                          ? 'Clear enough to record without asking.'
                          : 'Below the ${preview.autoCommitFloor}% bar, so it will always '
                              'wait for your review.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
