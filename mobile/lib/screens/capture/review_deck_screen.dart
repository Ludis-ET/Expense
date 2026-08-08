import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatting.dart';
import '../../core/theme.dart';
import '../../models/ingest.dart';
import '../../state/capture_store.dart';
import '../../state/data_store.dart';
import '../../widgets/common.dart';

/// Full-screen, one-message-at-a-time review.
///
/// The whole point is rhythm: a stack of cards you flick through, deciding each
/// in a second or two. Swipe right to record it, left to dismiss it. Anything
/// the parser could not work out is a tap on the card itself, so a message
/// needing one extra field does not break the flow into a separate form.
class ReviewDeckScreen extends StatefulWidget {
  const ReviewDeckScreen({super.key, this.startAt = 0});

  final int startAt;

  @override
  State<ReviewDeckScreen> createState() => _ReviewDeckScreenState();
}

class _ReviewDeckScreenState extends State<ReviewDeckScreen> with TickerProviderStateMixin {
  /// Local working copy: the deck must not reshuffle under the user's thumb
  /// when the store refetches after each decision.
  late List<InboxMessage> _queue;
  final Map<String, _Draft> _drafts = {};

  int _index = 0;
  bool _busy = false;

  /// -1 (fully left) .. 1 (fully right), driven by the drag.
  double _drag = 0;
  late final AnimationController _settle;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(() => setState(() {}));

    final capture = context.read<CaptureStore>();
    _queue = capture.inbox.where((m) => m.needsReview).toList();
    _index = widget.startAt.clamp(0, math.max(0, _queue.length - 1));
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  InboxMessage? get _current => _index < _queue.length ? _queue[_index] : null;

  _Draft _draftFor(InboxMessage m) {
    return _drafts.putIfAbsent(m.id, () {
      final data = context.read<DataStore>();
      final rule = context
          .read<CaptureStore>()
          .senderRules
          .where((r) => r.sender == m.sender)
          .firstOrNull;

      // The server's suggestion wins over the raw parse: it is the thing that
      // knows an ATM withdrawal belongs in the cash wallet.
      final kind = m.suggestion?.kind ?? m.parsedKind ?? 'EXPENSE';

      return _Draft(
        kind: kind,
        amount: m.parsedAmount ?? '',
        accountId: m.accountId ??
            rule?.accountId ??
            data.activeAccounts.where((a) => a.isDefault).firstOrNull?.id ??
            data.activeAccounts.firstOrNull?.id,
        categoryId: kind == 'TRANSFER' ? null : rule?.defaultCategoryId,
        transferAccountId: m.suggestion?.transferAccountId,
        payee: m.parsedPayee,
        date: m.effectiveDate,
      );
    });
  }

  /// What still has to be answered before this card can be recorded.
  List<String> _missing(InboxMessage m, _Draft d) {
    final gaps = <String>[];
    if (double.tryParse(d.amount.replaceAll(',', '')) == null) gaps.add('amount');
    if (d.accountId == null) gaps.add('account');
    if (d.kind == 'TRANSFER') {
      if (d.transferAccountId == null) gaps.add('destination');
    } else if (d.categoryId == null) {
      gaps.add('category');
    }
    return gaps;
  }

  Future<void> _confirm() async {
    final m = _current;
    if (m == null || _busy) return;

    final draft = _draftFor(m);
    final gaps = _missing(m, draft);
    if (gaps.isNotEmpty) {
      // Snap back rather than half-committing, and say what is missing.
      setState(() => _drag = 0);
      HapticFeedback.mediumImpact();
      showError(context, 'Still need the ${gaps.join(' and ')}');
      return;
    }

    setState(() => _busy = true);
    final capture = context.read<CaptureStore>();
    final data = context.read<DataStore>();

    try {
      await capture.confirm(m.id, {
        'kind': draft.kind,
        'amount': double.parse(draft.amount.replaceAll(',', '')),
        'currency': m.parsedCurrency ?? 'ETB',
        'date': draft.date.toUtc().toIso8601String(),
        'accountId': draft.accountId,
        if (draft.kind == 'TRANSFER') 'transferAccountId': draft.transferAccountId,
        if (draft.kind != 'TRANSFER') 'categoryId': draft.categoryId,
        if (draft.budgetId != null) 'budgetId': draft.budgetId,
        if (draft.payee?.trim().isNotEmpty == true) 'payee': draft.payee!.trim(),
        'rememberMapping': draft.remember,
      });
      await data.refreshAfterLedgerChange();
      HapticFeedback.lightImpact();
      _advance();
    } on ApiException catch (e) {
      setState(() => _drag = 0);
      if (mounted) showError(context, e.message);
    } catch (_) {
      setState(() => _drag = 0);
      if (mounted) showError(context, 'Could not save. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dismiss() async {
    final m = _current;
    if (m == null || _busy) return;

    setState(() => _busy = true);
    try {
      await context.read<CaptureStore>().reject(m.id);
      HapticFeedback.selectionClick();
      _advance();
    } on ApiException catch (e) {
      setState(() => _drag = 0);
      if (mounted) showError(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _advance() {
    if (!mounted) return;
    setState(() {
      _drag = 0;
      _index += 1;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    // Either a decisive flick or having dragged most of the way across counts
    // as a decision; anything less springs back.
    final decided = _drag.abs() > 0.42 || velocity.abs() > 700;

    if (!decided) {
      setState(() => _drag = 0);
      return;
    }
    if (_drag > 0 || velocity > 0) {
      _confirm();
    } else {
      _dismiss();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = _queue.length - _index;
    final message = _current;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(message == null ? 'All done' : '$remaining to review'),
        actions: [
          if (message != null)
            TextButton(
              onPressed: _busy ? null : _advance,
              child: const Text('Skip'),
            ),
        ],
      ),
      body: message == null
          ? _DeckFinished(reviewed: _queue.length)
          : Column(
              children: [
                _DeckProgress(current: _index, total: _queue.length),
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // A peek at the next card, so the deck feels like a stack
                      // rather than a series of unrelated screens.
                      if (_index + 1 < _queue.length)
                        Transform.scale(
                          scale: 0.94 - (0.02 * (1 - _drag.abs())),
                          child: Opacity(
                            opacity: 0.5,
                            child: IgnorePointer(
                              child: _ReviewCard(
                                message: _queue[_index + 1],
                                draft: _Draft.placeholder(),
                                onChanged: (_) {},
                                interactive: false,
                              ),
                            ),
                          ),
                        ),
                      GestureDetector(
                        onHorizontalDragUpdate: (d) {
                          final width = MediaQuery.of(context).size.width;
                          setState(() => _drag = (_drag + d.delta.dx / width).clamp(-1.0, 1.0));
                        },
                        onHorizontalDragEnd: _onDragEnd,
                        child: Transform.translate(
                          offset: Offset(_drag * MediaQuery.of(context).size.width * 0.72, 0),
                          child: Transform.rotate(
                            angle: _drag * 0.14,
                            child: _ReviewCard(
                              message: message,
                              draft: _draftFor(message),
                              dragProgress: _drag,
                              onChanged: (d) => setState(() => _drafts[message.id] = d),
                            ),
                          ),
                        ),
                      ),
                      if (_busy)
                        const Positioned.fill(
                          child: ColoredBox(
                            color: Color(0x22000000),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        ),
                    ],
                  ),
                ),
                _DeckActions(
                  onDismiss: _busy ? null : _dismiss,
                  onConfirm: _busy ? null : _confirm,
                ),
              ],
            ),
    );
  }
}

/// Mutable working state for one card.
class _Draft {
  _Draft({
    required this.kind,
    required this.amount,
    required this.date,
    this.accountId,
    this.categoryId,
    this.transferAccountId,
    this.budgetId,
    this.payee,
    this.remember = false,
  });

  _Draft.placeholder()
      : kind = 'EXPENSE',
        amount = '',
        date = DateTime.now(),
        accountId = null,
        categoryId = null,
        transferAccountId = null,
        budgetId = null,
        payee = null,
        remember = false;

  String kind;
  String amount;
  DateTime date;
  String? accountId;
  String? categoryId;
  String? transferAccountId;
  String? budgetId;
  String? payee;
  bool remember;

  _Draft copy() => _Draft(
        kind: kind,
        amount: amount,
        date: date,
        accountId: accountId,
        categoryId: categoryId,
        transferAccountId: transferAccountId,
        budgetId: budgetId,
        payee: payee,
        remember: remember,
      );
}

class _DeckProgress extends StatelessWidget {
  const _DeckProgress({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: total == 0 ? 0 : current / total,
          minHeight: 5,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

/// The card itself: what the bank said, what Santim made of it, and whatever
/// is still missing rendered as tappable chips.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.message,
    required this.draft,
    required this.onChanged,
    this.dragProgress = 0,
    this.interactive = true,
  });

  final InboxMessage message;
  final _Draft draft;
  final ValueChanged<_Draft> onChanged;
  final double dragProgress;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = context.watch<DataStore>();
    final isTransfer = draft.kind == 'TRANSFER';
    final isIncome = draft.kind == 'INCOME';

    final accent = isTransfer
        ? theme.colorScheme.primary
        : isIncome
            ? SantimTheme.income
            : SantimTheme.expense;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: theme.colorScheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 26,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isTransfer
                              ? (message.isAtmWithdrawal ? Icons.local_atm : Icons.swap_horiz)
                              : isIncome
                                  ? Icons.south_west
                                  : Icons.north_east,
                          color: accent,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message.bankLabel ?? message.sender,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              Dates.relative(message.receivedAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),
                  _AmountField(
                    value: draft.amount,
                    currency: message.parsedCurrency ?? 'ETB',
                    accent: accent,
                    enabled: interactive,
                    onChanged: (v) => onChanged(draft.copy()..amount = v),
                  ),

                  // The server's read on why this is not a plain expense.
                  if (message.suggestion?.reason != null) ...[
                    const SizedBox(height: 12),
                    _SuggestionNote(
                      reason: message.suggestion!.reason!,
                      needsCashAccount: message.suggestion!.needsCashAccount,
                    ),
                  ],

                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'EXPENSE', label: Text('Out')),
                      ButtonSegment(value: 'INCOME', label: Text('In')),
                      ButtonSegment(value: 'TRANSFER', label: Text('Move')),
                    ],
                    selected: {draft.kind},
                    onSelectionChanged: interactive
                        ? (s) {
                            final next = draft.copy()..kind = s.first;
                            // Category and destination are mutually exclusive,
                            // and a category's kind must match the direction.
                            next.categoryId = null;
                            if (next.kind != 'TRANSFER') next.transferAccountId = null;
                            if (next.kind != 'EXPENSE') next.budgetId = null;
                            onChanged(next);
                          }
                        : null,
                  ),

                  const SizedBox(height: 16),
                  _CardPicker(
                    label: isTransfer ? 'From' : 'Account',
                    icon: Icons.account_balance_wallet_outlined,
                    value: draft.accountId,
                    options: [
                      for (final a in data.activeAccounts) (a.id, a.name, a.available),
                    ],
                    enabled: interactive,
                    onChanged: (v) => onChanged(draft.copy()..accountId = v),
                  ),

                  const SizedBox(height: 10),
                  if (isTransfer)
                    _CardPicker(
                      label: 'To',
                      icon: Icons.south_east,
                      value: draft.transferAccountId,
                      // Cannot transfer into the same wallet it came from.
                      options: [
                        for (final a in data.activeAccounts.where((a) => a.id != draft.accountId))
                          (a.id, a.name, a.available),
                      ],
                      enabled: interactive,
                      onChanged: (v) => onChanged(draft.copy()..transferAccountId = v),
                    )
                  else
                    _CardPicker(
                      label: 'What was it for',
                      icon: Icons.sell_outlined,
                      value: draft.categoryId,
                      options: [
                        for (final c in (isIncome ? data.incomeCategories : data.expenseCategories))
                          (c.id, c.name, null),
                      ],
                      enabled: interactive,
                      onChanged: (v) => onChanged(draft.copy()..categoryId = v),
                    ),

                  if (!isTransfer && !isIncome && data.spendableBudgets.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _CardPicker(
                      label: 'From a plan',
                      icon: Icons.pie_chart_outline,
                      value: draft.budgetId,
                      optional: true,
                      options: [
                        for (final b in data.spendableBudgets) (b.id, b.name, b.potBalance),
                      ],
                      enabled: interactive,
                      onChanged: (v) => onChanged(draft.copy()..budgetId = v),
                    ),
                  ],

                  const SizedBox(height: 14),
                  _RawMessagePeek(body: message.body),

                  const SizedBox(height: 6),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: draft.remember,
                    onChanged: interactive
                        ? (v) => onChanged(draft.copy()..remember = v ?? false)
                        : null,
                    title: Text(
                      'Always use these for ${message.sender}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Verdict stamps that fade in as you drag, so the gesture's meaning
          // is obvious before you commit to it.
          if (dragProgress > 0.05)
            _Stamp(
              label: 'RECORD',
              color: SantimTheme.income,
              alignment: Alignment.topLeft,
              opacity: (dragProgress * 2).clamp(0, 1).toDouble(),
              angle: -0.28,
            ),
          if (dragProgress < -0.05)
            _Stamp(
              label: 'SKIP',
              color: SantimTheme.expense,
              alignment: Alignment.topRight,
              opacity: (-dragProgress * 2).clamp(0, 1).toDouble(),
              angle: 0.28,
            ),
        ],
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({
    required this.label,
    required this.color,
    required this.alignment,
    required this.opacity,
    required this.angle,
  });

  final String label;
  final Color color;
  final Alignment alignment;
  final double opacity;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Opacity(
            opacity: opacity,
            child: Transform.rotate(
              angle: angle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  border: Border.all(color: color, width: 3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AmountField extends StatefulWidget {
  const _AmountField({
    required this.value,
    required this.currency,
    required this.accent,
    required this.onChanged,
    required this.enabled,
  });

  final String value;
  final String currency;
  final Color accent;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  State<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<_AmountField> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
      onChanged: widget.onChanged,
      style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: widget.accent),
      decoration: InputDecoration(
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        isDense: true,
        prefixText: '${widget.currency == 'ETB' ? 'Br' : widget.currency}  ',
        prefixStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: widget.accent.withValues(alpha: 0.7),
        ),
        hintText: '0.00',
      ),
    );
  }
}

/// A labelled chip row that opens a picker sheet. Chosen over a dropdown so a
/// missing value reads as an obvious gap on the card rather than a quiet blank.
class _CardPicker extends StatelessWidget {
  const _CardPicker({
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.enabled,
    this.optional = false,
  });

  final String label;
  final IconData icon;
  final String? value;

  /// (id, name, trailing detail such as a balance)
  final List<(String, String, String?)> options;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = options.where((o) => o.$1 == value).firstOrNull;
    final missing = selected == null && !optional;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: enabled ? () => _open(context) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: missing
              ? SantimTheme.warning.withValues(alpha: 0.07)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          border: Border.all(
            color: missing
                ? SantimTheme.warning.withValues(alpha: 0.45)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    selected?.$2 ?? (optional ? 'None' : 'Tap to choose'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: missing ? SantimTheme.warning : null,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.expand_more, size: 19, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (optional)
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('None'),
                onTap: () => Navigator.pop(context, null),
              ),
            for (final (id, name, detail) in options)
              ListTile(
                selected: id == value,
                leading: Icon(
                  id == value ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                ),
                title: Text(name),
                trailing: detail == null
                    ? null
                    : Text(
                        Money.format(detail),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                onTap: () => Navigator.pop(context, id),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    // A sheet dismissed by tapping outside returns null too, which for an
    // optional field is a legitimate "clear it" - so only optional fields
    // accept null back.
    if (picked != null || optional) onChanged(picked);
  }
}

class _SuggestionNote extends StatelessWidget {
  const _SuggestionNote({required this.reason, required this.needsCashAccount});

  final String reason;
  final bool needsCashAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = needsCashAccount ? SantimTheme.warning : theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(needsCashAccount ? Icons.error_outline : Icons.lightbulb_outline,
              size: 17, color: tone),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              needsCashAccount
                  ? '$reason Pick your cash wallet in Settings first.'
                  : reason,
              style: theme.textTheme.bodySmall?.copyWith(color: tone),
            ),
          ),
        ],
      ),
    );
  }
}

class _RawMessagePeek extends StatefulWidget {
  const _RawMessagePeek({required this.body});

  final String body;

  @override
  State<_RawMessagePeek> createState() => _RawMessagePeekState();
}

class _RawMessagePeekState extends State<_RawMessagePeek> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: () => setState(() => _open = !_open),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sms_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 7),
                Text(
                  _open ? 'Original message' : 'See original message',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (_open) ...[
              const SizedBox(height: 7),
              Text(widget.body, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// Buttons mirroring the swipes, because a gesture-only UI is undiscoverable
/// and awkward one-handed on a large phone.
class _DeckActions extends StatelessWidget {
  const _DeckActions({required this.onDismiss, required this.onConfirm});

  final VoidCallback? onDismiss;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 26),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onDismiss,
              icon: const Icon(Icons.close),
              label: const Text('Skip'),
              style: OutlinedButton.styleFrom(
                foregroundColor: SantimTheme.expense,
                side: const BorderSide(color: SantimTheme.expense),
                minimumSize: const Size.fromHeight(54),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: onConfirm,
              icon: const Icon(Icons.check),
              label: const Text('Record'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeckFinished extends StatelessWidget {
  const _DeckFinished({required this.reviewed});

  final int reviewed;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.check_circle_outline,
      title: reviewed == 0 ? 'Nothing to review' : 'Inbox cleared',
      message: reviewed == 0
          ? 'New bank messages will land here as they arrive.'
          : 'You went through $reviewed message${reviewed == 1 ? '' : 's'}.',
      action: FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(180, 48)),
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    );
  }
}
