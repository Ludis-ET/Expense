import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../widgets/ui.dart';

/// Opens the add/edit sheet. Returns true when something was written.
Future<bool?> showTransactionForm(
  BuildContext context, {
  Transaction? existing,
  String? presetKind,
  String? presetBudgetId,
  String? presetAccountId,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 520),
    pageBuilder: (ctx, _, _) => Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: TransactionForm(
              existing: existing,
              presetKind: presetKind,
              presetBudgetId: presetBudgetId,
              presetAccountId: presetAccountId,
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Motion.spring);
      final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return Stack(
        fit: StackFit.expand,
        children: [
          FadeTransition(
            opacity: fade,
            child: GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 14 * animation.value,
                  sigmaY: 14 * animation.value,
                ),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.62 * animation.value),
                ),
              ),
            ),
          ),
          SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero).animate(curved),
            child: FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
                child: child,
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// The port of `transaction-form.tsx`. Three kinds share one form; the fields
/// that appear depend on the kind, and expenses can be paid from a budget
/// plan's pot instead of straight from an account.
class TransactionForm extends StatefulWidget {
  const TransactionForm({
    super.key,
    this.existing,
    this.presetKind,
    this.presetBudgetId,
    this.presetAccountId,
  });

  final Transaction? existing;
  final String? presetKind;
  final String? presetBudgetId;
  final String? presetAccountId;

  @override
  State<TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<TransactionForm> with TickerProviderStateMixin {
  late final _amount = TextEditingController(
    text: widget.existing == null ? '' : toNum(widget.existing!.amount).toString(),
  );
  late final _payee = TextEditingController(text: widget.existing?.payee ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late final _tags = TextEditingController(text: widget.existing?.tags.join(', ') ?? '');

  late TxKind _kind;
  String? _accountId;
  String? _transferAccountId;
  String? _categoryId;
  String? _budgetId;
  String? _budgetSourceAccountId;
  late DateTime _date;

  bool _saving = false;
  bool _showMore = false;
  String? _error;
  bool _amountFocused = false;

  late final AnimationController _headerPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  bool get _isEdit => widget.existing != null;

  bool get _amountReady {
    final amount = double.tryParse(_amount.text.trim());
    return amount != null && amount > 0;
  }

  @override
  void initState() {
    super.initState();
    final tx = widget.existing;
    _kind = tx?.kind ?? TxKind.parse(widget.presetKind ?? 'EXPENSE');
    _date = tx?.date ?? DateTime.now();
    _accountId = tx?.accountId ?? widget.presetAccountId;
    _transferAccountId = tx?.transferAccountId;
    _categoryId = tx?.categoryId;
    _budgetId = tx?.budgetId ?? widget.presetBudgetId;
    _budgetSourceAccountId = tx?.budgetSourceAccountId;

    _amount.addListener(() => setState(() {}));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final data = context.read<DataState>();
      await Future.wait([
        data.loadAccounts(),
        data.loadCategories(),
        data.loadSpendSources(force: true),
      ]);
      if (!mounted) return;
      setState(() {
        if (_accountId == null) {
          final accounts = data.scopedAccounts;
          final fallback =
              accounts.where((a) => a.isDefault).firstOrNull ?? accounts.firstOrNull;
          if (fallback != null) _accountId = fallback.id;
        }
        // Preset plan (e.g. Spend from plan detail) should also adopt its category.
        if (!_isEdit && _categoryId == null && _budgetId != null) {
          final planCat = _plan(data)?.categoryId;
          if (planCat != null) _categoryId = planCat;
        }
      });
    });
  }

  @override
  void dispose() {
    _headerPulse.dispose();
    _amount.dispose();
    _payee.dispose();
    _note.dispose();
    _tags.dispose();
    super.dispose();
  }

  Color _kindColor(BuildContext context, TxKind kind) => switch (kind) {
        TxKind.income => context.t.success,
        TxKind.expense => context.t.danger,
        TxKind.transfer => context.t.accent,
      };

  IconData _kindIcon(TxKind kind) => switch (kind) {
        TxKind.income => Icons.south_west_rounded,
        TxKind.expense => Icons.north_east_rounded,
        TxKind.transfer => Icons.swap_horiz_rounded,
      };

  BudgetSpendSource? _plan(DataState data) {
    if (_budgetId == null) return null;
    for (final p in data.spendSources.data ?? const <BudgetSpendSource>[]) {
      if (p.id == _budgetId) return p;
    }
    return null;
  }

  String? _validate(DataState data) {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) return 'Enter an amount greater than zero.';

    final plan = _plan(data);
    final payingFromPot = plan != null && !plan.isUnplanned;

    if (_kind == TxKind.transfer) {
      if (_accountId == null) return 'Pick the account the money leaves.';
      if (_transferAccountId == null) return 'Pick where the money goes.';
      if (_accountId == _transferAccountId) {
        return 'Transfer destination must be a different account.';
      }
      return null;
    }

    if (_categoryId == null) return 'Pick a category.';
    if (!payingFromPot && _accountId == null) {
      return 'Pick an account or a budget plan to pay from.';
    }
    if (payingFromPot && amount > toNum(plan.balance)) {
      return '${plan.name} only has ${formatMoney(plan.balance, currency: plan.currency)} left.';
    }
    return null;
  }

  Future<void> _save() async {
    final data = context.read<DataState>();
    final problem = _validate(data);
    if (problem != null) {
      setState(() => _error = problem);
      HapticFeedback.heavyImpact();
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _saving = true;
      _error = null;
    });

    final plan = _plan(data);
    final payingFromPot = plan != null && !plan.isUnplanned;
    final tags = _tags.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(10)
        .toList();

    final body = <String, dynamic>{
      'amount': double.parse(_amount.text.trim()),
      'currency': data.activeCurrency,
      'date': _date.toUtc().toIso8601String(),
      'tags': tags,
      if (_payee.text.trim().isNotEmpty) 'payee': _payee.text.trim(),
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
    };

    if (_isEdit) {
      if (_accountId != null) body['accountId'] = _accountId;
      if (_transferAccountId != null) body['transferAccountId'] = _transferAccountId;
      if (_categoryId != null) body['categoryId'] = _categoryId;
      if (_budgetSourceAccountId != null) {
        body['budgetSourceAccountId'] = _budgetSourceAccountId;
      }
      if (_payee.text.trim().isEmpty) body['payee'] = null;
      if (_note.text.trim().isEmpty) body['note'] = null;
    } else {
      body['kind'] = _kind.wire;
      switch (_kind) {
        case TxKind.income:
          body['accountId'] = _accountId;
          body['categoryId'] = _categoryId;
        case TxKind.transfer:
          body['accountId'] = _accountId;
          body['transferAccountId'] = _transferAccountId;
        case TxKind.expense:
          body['categoryId'] = _categoryId;
          if (payingFromPot) {
            body['budgetId'] = plan.id;
            if (_budgetSourceAccountId != null) {
              body['budgetSourceAccountId'] = _budgetSourceAccountId;
            }
            if (_accountId != null) body['accountId'] = _accountId;
          } else {
            body['accountId'] = _accountId;
          }
      }
    }

    try {
      final sync = context.read<SyncState>();
      final accounts = data.scopedAccounts;
      final categories = data.categoriesOfKind(_kind);
      Account? accountById(String? id) =>
          id == null ? null : accounts.where((a) => a.id == id).firstOrNull;
      TxCategory? categoryById(String? id) =>
          id == null ? null : categories.where((c) => c.id == id).firstOrNull;

      final account = accountById(_accountId);
      final category = categoryById(_categoryId);
      final transfer = accountById(_transferAccountId);

      Ref? accountRef(Account? a) => a == null
          ? null
          : Ref(id: a.id, name: a.name, icon: a.icon, color: a.color, currency: a.currency, type: a.type.wire);
      Ref? categoryRef(TxCategory? c) => c == null
          ? null
          : Ref(id: c.id, name: c.name, icon: c.icon, color: c.color);

      if (_isEdit) {
        final existing = widget.existing!;
        final optimistic = Transaction(
          id: existing.id,
          kind: existing.kind,
          amount: body['amount'].toString(),
          currency: data.activeCurrency,
          date: _date,
          accountId: _accountId ?? existing.accountId,
          tags: tags,
          account: accountRef(account) ?? existing.account,
          transferAccountId: _transferAccountId ?? existing.transferAccountId,
          transferAccount: accountRef(transfer) ?? existing.transferAccount,
          categoryId: _categoryId ?? existing.categoryId,
          category: categoryRef(category) ?? existing.category,
          budgetId: existing.budgetId,
          payee: _payee.text.trim().isEmpty ? null : _payee.text.trim(),
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          pending: PendingState.pending,
        );
        final result = await sync.updateTransaction(existing.id, body, optimistic);
        if (!mounted) return;
        if (result.queued) {
          toast(context, 'Saved offline — will sync when you are back online');
        }
        Navigator.pop(context, true);
      } else {
        final localId = newLocalId();
        final optimistic = Transaction(
          id: localId,
          kind: _kind,
          amount: body['amount'].toString(),
          currency: data.activeCurrency,
          date: _date,
          accountId: _accountId ?? '',
          tags: tags,
          account: accountRef(account),
          transferAccountId: _transferAccountId,
          transferAccount: accountRef(transfer),
          categoryId: _categoryId,
          category: categoryRef(category),
          budgetId: payingFromPot ? plan.id : null,
          payee: _payee.text.trim().isEmpty ? null : _payee.text.trim(),
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          pending: PendingState.pending,
        );
        final result = await sync.saveTransaction(body, optimistic);
        if (!mounted) return;
        if (result.queued) {
          toast(context, 'Saved offline — will sync when you are back online');
        }
        Navigator.pop(context, true);
      }
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  void _setKind(TxKind k) {
    if (k == _kind) return;
    HapticFeedback.selectionClick();
    setState(() {
      _kind = k;
      _categoryId = null;
      if (k != TxKind.expense) _budgetId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final data = context.watch<DataState>();
    final accounts = data.scopedAccounts;
    final categories = data.categoriesOfKind(_kind);
    final plans = (data.spendSources.data ?? const <BudgetSpendSource>[])
        .where((p) => p.currency == data.activeCurrency)
        .toList();

    final plan = _plan(data);
    final payingFromPot = plan != null && !plan.isUnplanned;
    final tint = _kindColor(context, _kind);

    Account? accountById(String? id) =>
        id == null ? null : accounts.where((a) => a.id == id).firstOrNull;
    TxCategory? categoryById(String? id) =>
        id == null ? null : categories.where((c) => c.id == id).firstOrNull;

    final maxH = MediaQuery.sizeOf(context).height * 0.92;

    return AnimatedBuilder(
      animation: _headerPulse,
      builder: (context, _) {
        final pulse = _headerPulse.value;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: _AmbientOrbs(tint: tint, pulse: pulse),
                ),
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          t.surface.withValues(alpha: t.isDark ? 0.9 : 0.94),
                          t.surfaceMuted.withValues(alpha: t.isDark ? 0.86 : 0.9),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: tint.withValues(alpha: 0.28 + pulse * 0.08)),
                      boxShadow: [
                        BoxShadow(
                          color: tint.withValues(alpha: 0.22 + pulse * 0.1),
                          blurRadius: 48,
                          spreadRadius: -12,
                          offset: const Offset(0, -6),
                        ),
                        ...t.elevatedShadow,
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ModalHeader(
                          pulse: pulse,
                          tint: tint,
                          icon: _kindIcon(_kind),
                          title: _isEdit ? 'Edit transaction' : 'New transaction',
                          subtitle: _isEdit
                              ? 'Update the details below'
                              : 'Log ${_kind.label.toLowerCase()} instantly',
                          onClose: () => Navigator.pop(context),
                        ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          0,
                          20,
                          20 + MediaQuery.paddingOf(context).bottom,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!_isEdit) ...[
                              FadeInUp.staggered(
                                index: 0,
                                child: _FuturisticKindPicker(
                                  value: _kind,
                                  colorOf: (k) => _kindColor(context, k),
                                  iconOf: _kindIcon,
                                  onChanged: _setKind,
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],

                            FadeInUp.staggered(
                              index: _isEdit ? 0 : 1,
                              child: _HeroAmountField(
                                controller: _amount,
                                currency: data.activeCurrency,
                                tint: tint,
                                autofocus: !_isEdit,
                                focused: _amountFocused,
                                onFocusChange: (f) => setState(() => _amountFocused = f),
                              ),
                            ),
                            const SizedBox(height: 18),

                            AnimatedSwitcher(
                              duration: Motion.fast,
                              switchInCurve: Motion.easeOut,
                              switchOutCurve: Motion.easeOut,
                              transitionBuilder: (child, anim) => FadeTransition(
                                opacity: anim,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.04),
                                    end: Offset.zero,
                                  ).animate(anim),
                                  child: child,
                                ),
                              ),
                              child: StaggerColumn(
                                key: ValueKey('fields-${_kind.wire}'),
                                spacing: 14,
                                startIndex: _isEdit ? 1 : 2,
                                children: [
                                  if (_kind == TxKind.expense && plans.isNotEmpty && !_isEdit)
                                    PickerField<BudgetSpendSource>(
                                      label: 'Pay from',
                                      hint: 'Choosing a plan spends its reserved money instead of your '
                                          'free balance. "Unplanned" is the catch-all for spending that '
                                          'was never budgeted.',
                                      value: plan,
                                      options: plans,
                                      labelOf: (p) => p.isUnplanned
                                          ? '${p.name} (from an account)'
                                          : '${p.name} · ${formatMoney(p.balance, currency: p.currency)} left',
                                      iconOf: (p) => p.isUnplanned
                                          ? Icons.account_balance_wallet_outlined
                                          : financeIcon(p.icon),
                                      colorOf: (p) => parseHexColor(p.color) ?? t.primary,
                                      onChanged: (p) => setState(() {
                                        _budgetId = p?.id;
                                        _budgetSourceAccountId = null;
                                        if (p != null && !p.isUnplanned && p.sources.length == 1) {
                                          _budgetSourceAccountId = p.sources.first.account?.id;
                                        }
                                        // Plans with a linked category pre-select it.
                                        final planCat = p?.categoryId;
                                        if (planCat != null) _categoryId = planCat;
                                      }),
                                      allowClear: true,
                                      placeholder: 'Straight from an account',
                                      sheetTitle: 'Pay from',
                                    ),

                                  if (payingFromPot && plan.sources.length > 1)
                                    PickerField<BudgetSource>(
                                      label: 'Free the reservation on',
                                      hint: 'This plan was filled from more than one wallet. '
                                          'Pick which one the money actually leaves.',
                                      value: plan.sources
                                          .where((s) => s.account?.id == _budgetSourceAccountId)
                                          .firstOrNull,
                                      options: plan.sources,
                                      labelOf: (s) =>
                                          '${s.account?.name ?? 'Unknown'} · ${formatMoney(s.available, currency: plan.currency)}',
                                      iconOf: (s) => accountTypeIcon(s.account?.type ?? 'OTHER'),
                                      onChanged: (s) =>
                                          setState(() => _budgetSourceAccountId = s?.account?.id),
                                      sheetTitle: 'Funding wallet',
                                    ),

                                  if (_kind != TxKind.transfer)
                                    PickerField<TxCategory>(
                                      label: 'Category',
                                      value: categoryById(_categoryId),
                                      options: categories,
                                      labelOf: (c) => c.name,
                                      iconOf: (c) => financeIcon(c.icon),
                                      colorOf: (c) => parseHexColor(c.color) ?? t.mutedForeground,
                                      onChanged: (c) => setState(() => _categoryId = c?.id),
                                      placeholder: 'Pick a category',
                                      sheetTitle: '${_kind.label} category',
                                    ),

                                  if (!payingFromPot)
                                    PickerField<Account>(
                                      label: _kind == TxKind.transfer
                                          ? 'From account'
                                          : _kind == TxKind.income
                                              ? 'Into account'
                                              : 'Account',
                                      value: accountById(_accountId),
                                      options: accounts,
                                      labelOf: (a) => a.name,
                                      subtitleOf: (a) =>
                                          '${formatMoney(a.balance, currency: a.currency)} available',
                                      iconOf: (a) => accountTypeIcon(a.type.wire),
                                      colorOf: (a) => parseHexColor(a.color) ?? t.mutedForeground,
                                      onChanged: (a) => setState(() => _accountId = a?.id),
                                      placeholder: 'Pick an account',
                                    ),

                                  if (_kind == TxKind.transfer)
                                    PickerField<Account>(
                                      label: 'To account',
                                      value: accountById(_transferAccountId),
                                      options: accounts.where((a) => a.id != _accountId).toList(),
                                      labelOf: (a) => a.name,
                                      subtitleOf: (a) =>
                                          '${formatMoney(a.balance, currency: a.currency)} available',
                                      iconOf: (a) => accountTypeIcon(a.type.wire),
                                      colorOf: (a) => parseHexColor(a.color) ?? t.mutedForeground,
                                      onChanged: (a) => setState(() => _transferAccountId = a?.id),
                                      placeholder: 'Pick a destination',
                                    ),

                                  DateField(
                                    label: 'Date',
                                    value: _date,
                                    onChanged: (d) => setState(() => _date = d ?? _date),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 6),
                            _MoreDetailsToggle(
                              expanded: _showMore,
                              onTap: () => setState(() => _showMore = !_showMore),
                            ),
                            AnimatedSize(
                              duration: Motion.fast,
                              curve: Motion.easeOut,
                              alignment: Alignment.topCenter,
                              child: _showMore
                                  ? FadeInUp(
                                      delay: const Duration(milliseconds: 60),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          const SizedBox(height: 12),
                                          AppTextField(
                                            controller: _payee,
                                            label: 'Payee',
                                            placeholder:
                                                _kind == TxKind.income ? 'Who paid you' : 'Who you paid',
                                            prefixIcon: Icons.storefront_outlined,
                                          ),
                                          const SizedBox(height: 14),
                                          AppTextField(
                                            controller: _note,
                                            label: 'Note',
                                            placeholder: 'What was it for?',
                                            maxLines: 3,
                                            prefixIcon: Icons.notes_outlined,
                                          ),
                                          const SizedBox(height: 14),
                                          AppTextField(
                                            controller: _tags,
                                            label: 'Tags',
                                            hint: 'Comma-separated. Tags let you slice spending in '
                                                'ways categories cannot — "wedding", "trip", "unnecessary".',
                                            placeholder: 'unnecessary, trip',
                                            prefixIcon: Icons.sell_outlined,
                                            textCapitalization: TextCapitalization.none,
                                          ),
                                        ],
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),

                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              FadeInUp(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                  decoration: BoxDecoration(
                                    color: t.danger.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(R.lg),
                                    border: Border.all(color: t.danger.withValues(alpha: 0.35)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: t.danger.withValues(alpha: 0.15),
                                        blurRadius: 16,
                                        spreadRadius: -4,
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.error_outline_rounded, size: 18, color: t.danger),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _error!,
                                          style: TextStyle(
                                            fontSize: 13,
                                            height: 1.4,
                                            color: t.foreground,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],

                            const SizedBox(height: 22),
                            FadeInUp.staggered(
                              index: 8,
                              child: _GlowSubmitButton(
                                label: _isEdit ? 'Save changes' : 'Add ${_kind.label.toLowerCase()}',
                                tint: tint,
                                loading: _saving,
                                ready: _amountReady,
                                onPressed: _saving ? null : _save,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Modal chrome ────────────────────────────────────────────────────────────

class _ModalHeader extends StatelessWidget {
  const _ModalHeader({
    required this.pulse,
    required this.tint,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final double pulse;
  final Color tint;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.pill),
              gradient: LinearGradient(
                colors: [
                  tint.withValues(alpha: 0.35 + pulse * 0.2),
                  tint.withValues(alpha: 0.65 + pulse * 0.15),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: tint.withValues(alpha: 0.35),
                  blurRadius: 8,
                  spreadRadius: -1,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: Motion.fast,
                curve: Motion.spring,
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(R.lg),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      tint.withValues(alpha: 0.35 + pulse * 0.1),
                      tint.withValues(alpha: 0.12),
                    ],
                  ),
                  border: Border.all(color: tint.withValues(alpha: 0.4)),
                  boxShadow: [
                    BoxShadow(
                      color: tint.withValues(alpha: 0.25 + pulse * 0.12),
                      blurRadius: 18,
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: Icon(icon, color: tint, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: t.foreground,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: t.mutedForeground,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, color: t.mutedForeground),
                style: IconButton.styleFrom(
                  backgroundColor: t.surfaceMuted.withValues(alpha: 0.7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AmbientOrbs extends StatelessWidget {
  const _AmbientOrbs({required this.tint, required this.pulse});

  final Color tint;
  final double pulse;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -50 + 18 * pulse,
            right: -40 + 12 * pulse,
            child: _orb(160, tint.withValues(alpha: 0.28 + pulse * 0.08)),
          ),
          Positioned(
            top: 80 - 14 * pulse,
            left: -60,
            child: _orb(110, tint.withValues(alpha: 0.16)),
          ),
          Positioned(
            bottom: -30,
            right: 40 + 20 * pulse,
            child: _orb(90, tint.withValues(alpha: 0.12 + pulse * 0.06)),
          ),
        ],
      ),
    );
  }

  Widget _orb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

// ─── Kind picker ─────────────────────────────────────────────────────────────

class _FuturisticKindPicker extends StatelessWidget {
  const _FuturisticKindPicker({
    required this.value,
    required this.colorOf,
    required this.iconOf,
    required this.onChanged,
  });

  final TxKind value;
  final Color Function(TxKind) colorOf;
  final IconData Function(TxKind) iconOf;
  final ValueChanged<TxKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final options = TxKind.values;
    final index = options.indexOf(value);
    final active = colorOf(value);

    return LayoutBuilder(
      builder: (context, constraints) {
        final tabW = constraints.maxWidth / options.length;
        return Container(
          height: 54,
          decoration: BoxDecoration(
            color: t.surfaceMuted.withValues(alpha: t.isDark ? 0.55 : 0.65),
            borderRadius: BorderRadius.circular(R.xl),
            border: Border.all(color: t.border.withValues(alpha: 0.6)),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: Motion.fast,
                curve: Motion.spring,
                left: index * tabW + 4,
                top: 4,
                bottom: 4,
                width: tabW - 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(R.lg),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        active.withValues(alpha: 0.38),
                        active.withValues(alpha: 0.14),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: active.withValues(alpha: 0.35),
                        blurRadius: 16,
                        spreadRadius: -3,
                      ),
                    ],
                    border: Border.all(color: active.withValues(alpha: 0.35)),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final k in options)
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => onChanged(k),
                          borderRadius: BorderRadius.circular(R.lg),
                          splashColor: active.withValues(alpha: 0.12),
                          child: AnimatedDefaultTextStyle(
                            duration: Motion.fast,
                            curve: Motion.easeOut,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: k == value ? FontWeight.w700 : FontWeight.w500,
                              color: k == value ? active : t.mutedForeground,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  iconOf(k),
                                  size: 18,
                                  color: k == value ? active : t.mutedForeground,
                                ),
                                const SizedBox(height: 3),
                                Text(k.label),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Hero amount ─────────────────────────────────────────────────────────────

class _HeroAmountField extends StatefulWidget {
  const _HeroAmountField({
    required this.controller,
    required this.currency,
    required this.tint,
    required this.autofocus,
    required this.focused,
    required this.onFocusChange,
  });

  final TextEditingController controller;
  final String currency;
  final Color tint;
  final bool autofocus;
  final bool focused;
  final ValueChanged<bool> onFocusChange;

  @override
  State<_HeroAmountField> createState() => _HeroAmountFieldState();
}

class _HeroAmountFieldState extends State<_HeroAmountField> with SingleTickerProviderStateMixin {
  late final FocusNode _focus = FocusNode();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    if (widget.focused) _pulse.repeat(reverse: true);
  }

  void _onFocus() {
    widget.onFocusChange(_focus.hasFocus);
    if (_focus.hasFocus) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final glow = widget.focused ? 0.12 + _pulse.value * 0.14 : 0.06;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        return AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.easeOut,
          padding: const EdgeInsets.all(1.8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.xl),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.tint.withValues(alpha: 0.55 + glow),
                widget.tint.withValues(alpha: 0.15),
                t.accent.withValues(alpha: 0.25),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: widget.tint.withValues(alpha: 0.22 + glow),
                blurRadius: 28 + _pulse.value * 8,
                spreadRadius: -6,
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.xl - 1.8),
              color: t.surface.withValues(alpha: t.isDark ? 0.72 : 0.88),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Amount',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: widget.tint.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: Motion.fast,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: widget.tint.withValues(alpha: 0.65),
                      ),
                      child: Text(currencySymbol(widget.currency)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: widget.controller,
                        focusNode: _focus,
                        autofocus: widget.autofocus,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                        ],
                        cursorColor: widget.tint,
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.5,
                          color: widget.tint,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          height: 1.1,
                        ),
                        decoration: InputDecoration(
                          hintText: '0',
                          hintStyle: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            color: t.mutedForeground.withValues(alpha: 0.28),
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: widget.tint.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(R.pill),
                        border: Border.all(color: widget.tint.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        widget.currency,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: widget.tint,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── More details toggle ─────────────────────────────────────────────────────

class _MoreDetailsToggle extends StatelessWidget {
  const _MoreDetailsToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: Motion.fast,
                curve: Motion.easeOut,
                child: Icon(Icons.expand_more_rounded, size: 20, color: t.primary),
              ),
              const SizedBox(width: 6),
              Text(
                expanded ? 'Fewer details' : 'More details',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: t.primary,
                ),
              ),
              const Spacer(),
              Icon(Icons.auto_awesome_outlined, size: 14, color: t.mutedForeground.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Submit button ─────────────────────────────────────────────────────────────

class _GlowSubmitButton extends StatelessWidget {
  const _GlowSubmitButton({
    required this.label,
    required this.tint,
    required this.loading,
    required this.ready,
    required this.onPressed,
  });

  final String label;
  final Color tint;
  final bool loading;
  final bool ready;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final enabled = onPressed != null;

    Widget button = AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.easeOut,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(R.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: enabled
              ? [
                  tint,
                  Color.lerp(tint, t.accent, 0.45)!,
                ]
              : [
                  t.mutedForeground.withValues(alpha: 0.35),
                  t.mutedForeground.withValues(alpha: 0.25),
                ],
        ),
        boxShadow: enabled && ready
            ? [
                BoxShadow(
                  color: tint.withValues(alpha: 0.45),
                  blurRadius: 24,
                  spreadRadius: -4,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(R.xl),
          child: Center(
            child: loading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: t.primaryForeground,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded, color: t.primaryForeground, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: t.primaryForeground,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );

    if (ready && enabled && !loading) {
      button = Shimmer(child: button);
    }

    return button;
  }
}
