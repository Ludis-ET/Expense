import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';

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
  Transaction? template,
  String? presetKind,
  String? presetBudgetId,
  String? presetAccountId,
}) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (ctx, _, _) => Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: TransactionForm(
              existing: existing,
              template: template,
              presetKind: presetKind,
              presetBudgetId: presetBudgetId,
              presetAccountId: presetAccountId,
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Motion.easeOut);
      return Stack(
        fit: StackFit.expand,
        children: [
          FadeTransition(
            opacity: curved,
            child: GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: Container(
                color: Colors.black.withValues(alpha: 0.48 * animation.value),
              ),
            ),
          ),
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(opacity: curved, child: child),
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
    this.template,
    this.presetKind,
    this.presetBudgetId,
    this.presetAccountId,
  });

  /// Editing this transaction   the save writes back over it.
  final Transaction? existing;

  /// Copying this transaction. Every field is prefilled but the save creates a
  /// new entry, which is what "log again" needs: the coffee you buy five
  /// mornings a week should not start from an empty form.
  final Transaction? template;

  final String? presetKind;
  final String? presetBudgetId;
  final String? presetAccountId;

  /// The transaction whose values seed the fields, whether we are editing it
  /// or copying it.
  Transaction? get seed => existing ?? template;

  @override
  State<TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<TransactionForm> {
  late final _amount = TextEditingController(
    text: widget.seed == null ? '' : toNum(widget.seed!.amount).toString(),
  );
  late final _payee = TextEditingController(text: widget.seed?.payee ?? '');
  late final _note = TextEditingController(text: widget.seed?.note ?? '');
  late final _tags = TextEditingController(
    text: widget.seed?.tags.join(', ') ?? '',
  );

  late TxKind _kind;
  String? _accountId;
  String? _transferAccountId;
  String? _categoryId;
  String? _budgetId;
  String? _budgetSourceAccountId;

  /// Where the shortfall comes from when the plan cannot cover this on its own.
  /// `plan:<id>` for another envelope, `account:<id>` for money in no plan.
  String? _cover;
  late DateTime _date;

  bool _saving = false;
  bool _showMore = false;
  String? _error;
  bool _amountFocused = false;

  bool get _isEdit => widget.existing != null;

  bool get _amountReady {
    final amount = double.tryParse(_amount.text.trim());
    return amount != null && amount > 0;
  }

  @override
  void initState() {
    super.initState();
    final tx = widget.seed;
    _kind = tx?.kind ?? TxKind.parse(widget.presetKind ?? 'EXPENSE');
    _date = widget.existing?.date ?? DateTime.now();
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
              accounts.where((a) => a.isDefault).firstOrNull ??
              accounts.firstOrNull;
          if (fallback != null) _accountId = fallback.id;
        }
        // Preset plan (e.g. Spend from plan detail) should adopt funder + category.
        if (!_isEdit && _budgetId != null) {
          final plan = _plan(data);
          if (plan != null && !plan.isUnplanned) {
            final preferred = _preferredSource(plan);
            final funderId = preferred?.account?.id;
            if (funderId != null) {
              _budgetSourceAccountId ??= funderId;
              // Prefer the plan's wallet over a generic default when opening
              // from plan detail / FAB with a preset.
              if (widget.presetBudgetId != null ||
                  widget.presetAccountId == null) {
                _accountId = funderId;
              }
            }
          }
          if (_categoryId == null) {
            final planCat = plan?.categoryId;
            if (planCat != null) _categoryId = planCat;
          }
        }
      });
    });
  }

  @override
  void dispose() {
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

  /// The payees seen most often in recent activity, for the current kind,
  /// paired with the category they usually carry. Ranked by frequency and
  /// capped at five so the row never wraps.
  List<({String payee, String? categoryId})> _recentPayees(DataState data) {
    final recent =
        data.dashboard.data?.recentTransactions ?? const <Transaction>[];

    final counts = <String, int>{};
    final categoryOf = <String, String?>{};
    for (final tx in recent) {
      if (tx.kind != _kind) continue;
      final payee = tx.payee?.trim();
      if (payee == null || payee.isEmpty) continue;
      counts[payee] = (counts[payee] ?? 0) + 1;
      categoryOf.putIfAbsent(payee, () => tx.categoryId);
    }

    final ranked = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));

    return [
      for (final payee in ranked.take(5))
        (payee: payee, categoryId: categoryOf[payee]),
    ];
  }

  BudgetSpendSource? _plan(DataState data) {
    if (_budgetId == null) return null;
    for (final p in data.spendSources.data ?? const <BudgetSpendSource>[]) {
      if (p.id == _budgetId) return p;
    }
    return null;
  }

  /// Largest funded share, or the only one. Used to default pay + release wallets.
  BudgetSource? _preferredSource(BudgetSpendSource plan) {
    final funded = plan.sources.where((s) => s.account != null).toList();
    if (funded.isEmpty) return null;
    funded.sort((a, b) {
      final aa = double.tryParse(a.available) ?? 0;
      final bb = double.tryParse(b.available) ?? 0;
      return bb.compareTo(aa);
    });
    return funded.first;
  }

  /// Apply plan selection defaults: release wallet + pay wallet from funders.
  void _applyPlanDefaults(BudgetSpendSource? p) {
    _budgetId = p?.id;
    _budgetSourceAccountId = null;
    if (p == null || p.isUnplanned) return;
    final preferred = _preferredSource(p);
    final funderId = preferred?.account?.id;
    if (funderId != null) {
      _budgetSourceAccountId = funderId;
      _accountId = funderId;
    }
    final planCat = p.categoryId;
    if (planCat != null) _categoryId = planCat;
  }

  String? _validate(DataState data) {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0)
      return 'Enter an amount greater than zero.';

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
    // Every expense names the wallet the cash leaves now, plan or no plan - a
    // plan says which envelope it draws down, never where the money came from.
    if (_accountId == null) return 'Pick the wallet this comes out of.';

    // Going past what a plan holds is allowed, but you have to say where the
    // rest comes from. Refusing outright just pushes people into recording it
    // as unplanned, which quietly ruins both numbers.
    if (payingFromPot && amount > plan.remaining && _cover == null) {
      final short = amount - plan.remaining;
      return '${plan.name} is ${formatMoney(short, currency: plan.currency)} short. '
          'Choose where to cover it from.';
    }
    return null;
  }

  /// The cover the server understands, or null when nothing is short.
  Map<String, dynamic>? _coverPayload() {
    final value = _cover;
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    return parts.first == 'plan'
        ? {'from': 'BUDGET', 'budgetId': parts.last}
        : {'from': 'ACCOUNT', 'accountId': parts.last};
  }

  /// How far past the plan this spend goes, or zero when it fits.
  double _shortfall(DataState data) {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    final plan = _plan(data);
    if (plan == null || plan.isUnplanned) return 0;
    final over = amount - plan.remaining;
    return over > 0 ? over : 0;
  }

  Future<void> _save() async {
    final data = context.read<DataState>();
    final problem = _validate(data);
    if (problem != null) {
      setState(() => _error = problem);
      Haptics.reject();
      return;
    }

    Haptics.commit();
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
      'date': wireDate(_date),
      'tags': tags,
      if (_payee.text.trim().isNotEmpty) 'payee': _payee.text.trim(),
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
    };

    if (_isEdit) {
      if (_accountId != null) body['accountId'] = _accountId;
      if (_transferAccountId != null)
        body['transferAccountId'] = _transferAccountId;
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
          // The wallet the cash leaves is always sent. The plan, when there is
          // one, only says which envelope is drawn down; leaving it off means
          // unplanned, which is the single representation of it now - the web
          // and the phone no longer describe the same action differently.
          body['accountId'] = _accountId;
          if (payingFromPot) {
            body['budgetId'] = plan.id;
            if (_budgetSourceAccountId != null) {
              body['budgetSourceAccountId'] = _budgetSourceAccountId;
            }
            final cover = _coverPayload();
            if (cover != null) body['cover'] = cover;
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
          : Ref(
              id: a.id,
              name: a.name,
              icon: a.icon,
              color: a.color,
              currency: a.currency,
              type: a.type.wire,
            );
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
        final result = await sync.updateTransaction(
          existing.id,
          body,
          optimistic,
        );
        if (!mounted) return;
        if (result.queued) {
          toast(context, 'Saved offline   will sync when you are back online');
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
          toast(context, 'Saved offline   will sync when you are back online');
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
    Haptics.select();
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

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: tint.withValues(alpha: 0.28)),
            boxShadow: t.elevatedShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ModalHeader(
                pulse: 0.4,
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
                        const Gap(S.xl),
                      ],

                      FadeInUp.staggered(
                        index: _isEdit ? 0 : 1,
                        child: _HeroAmountField(
                          controller: _amount,
                          currency: data.activeCurrency,
                          tint: tint,
                          focused: _amountFocused,
                          onFocusChange: (f) =>
                              setState(() => _amountFocused = f),
                        ),
                      ),
                      const Gap(S.lg),

                      // The five payees you actually use, so a repeat
                      // entry never starts from an empty field.
                      if (!_isEdit && _kind != TxKind.transfer)
                        _RecentPayees(
                          payees: _recentPayees(data),
                          onPick: (payee, categoryId) {
                            Haptics.select();
                            setState(() {
                              _payee.text = payee;
                              _categoryId ??= categoryId;
                              _showMore = true;
                            });
                          },
                        ),

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
                            if (_kind == TxKind.expense &&
                                plans.isNotEmpty &&
                                !_isEdit)
                              PickerField<BudgetSpendSource>(
                                label: 'Pay from',
                                hint:
                                    'Choosing a plan spends its reserved money instead of your '
                                    'free balance. "Unplanned" is the catch-all for spending that '
                                    'was never budgeted.',
                                value: plan,
                                options: plans,
                                labelOf: (p) => p.isUnplanned
                                    ? '${p.name} (no money set aside)'
                                    : '${p.name} · ${formatMoney(p.balance ?? '0', currency: p.currency)} left',
                                iconOf: (p) => p.isUnplanned
                                    ? Icons.account_balance_wallet_outlined
                                    : financeIcon(p.icon),
                                colorOf: (p) =>
                                    parseHexColor(p.color) ?? t.primary,
                                onChanged: (p) => setState(() {
                                  _cover = null;
                                  _applyPlanDefaults(p);
                                }),
                                allowClear: true,
                                placeholder: 'Straight from an account',
                                sheetTitle: 'Pay from',
                              ),

                            if (payingFromPot && plan.sources.length > 1)
                              PickerField<BudgetSource>(
                                label: 'Free the reservation on',
                                hint:
                                    'This plan was filled from more than one wallet. '
                                    'Pick which one the money actually leaves.',
                                value: plan.sources
                                    .where(
                                      (s) =>
                                          s.account?.id ==
                                          _budgetSourceAccountId,
                                    )
                                    .firstOrNull,
                                options: plan.sources,
                                labelOf: (s) =>
                                    '${s.account?.name ?? 'Unknown'} · ${formatMoney(s.available, currency: plan.currency)}',
                                iconOf: (s) =>
                                    accountTypeIcon(s.account?.type ?? 'OTHER'),
                                onChanged: (s) => setState(() {
                                  _budgetSourceAccountId = s?.account?.id;
                                  // Keep pay wallet in sync when the user has
                                  // not deliberately fronted from another wallet.
                                  if (_accountId == null ||
                                      plan.sources.every(
                                        (x) => x.account?.id != _accountId,
                                      )) {
                                    _accountId = s?.account?.id;
                                  }
                                }),
                                sheetTitle: 'Funding wallet',
                              ),

                            // The plan is short. Cover it rather than refusing.
                            if (payingFromPot && _shortfall(data) > 0)
                              _CoverPicker(
                                plan: plan,
                                shortfall: _shortfall(data),
                                plans: plans,
                                accounts: accounts,
                                value: _cover,
                                onChanged: (v) => setState(() => _cover = v),
                              ),

                            if (_kind != TxKind.transfer)
                              PickerField<TxCategory>(
                                label: 'Category',
                                value: categoryById(_categoryId),
                                options: categories,
                                labelOf: (c) => c.name,
                                iconOf: (c) => financeIcon(c.icon),
                                colorOf: (c) =>
                                    parseHexColor(c.color) ?? t.mutedForeground,
                                onChanged: (c) =>
                                    setState(() => _categoryId = c?.id),
                                placeholder: 'Pick a category',
                                sheetTitle: '${_kind.label} category',
                              ),

                            if (_kind != TxKind.transfer)
                              PickerField<Account>(
                                label: _kind == TxKind.income
                                    ? 'Into account'
                                    : 'Take it out of',
                                hint: payingFromPot
                                    ? 'Cash leaves this wallet. The plan only frees the reservation below (or the single funder).'
                                    : null,
                                value: accountById(_accountId),
                                options: accounts,
                                labelOf: (a) => a.name,
                                subtitleOf: (a) =>
                                    '${formatMoney(a.balance, currency: a.currency)} available',
                                iconOf: (a) => accountTypeIcon(a.type.wire),
                                colorOf: (a) =>
                                    parseHexColor(a.color) ?? t.mutedForeground,
                                onChanged: (a) =>
                                    setState(() => _accountId = a?.id),
                                placeholder: 'Pick an account',
                              ),

                            if (payingFromPot &&
                                _accountId != null &&
                                _budgetSourceAccountId != null &&
                                _accountId != _budgetSourceAccountId)
                              Padding(
                                padding: const EdgeInsets.only(bottom: S.md),
                                child: AppCard(
                                  padding: const EdgeInsets.all(S.md),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        size: 18,
                                        color: t.primary,
                                      ),
                                      const GapX(S.sm),
                                      Expanded(
                                        child: Text(
                                          'Cash leaves ${accountById(_accountId)?.name ?? 'this wallet'}; '
                                          'the plan frees money held in '
                                          '${plan.sources.where((s) => s.account?.id == _budgetSourceAccountId).firstOrNull?.account?.name ?? 'another wallet'}.',
                                          style: TextStyle(
                                            fontSize: AppType.caption,
                                            color: t.mutedForeground,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            if (_kind == TxKind.transfer)
                              PickerField<Account>(
                                label: 'From account',
                                value: accountById(_accountId),
                                options: accounts,
                                labelOf: (a) => a.name,
                                subtitleOf: (a) =>
                                    '${formatMoney(a.balance, currency: a.currency)} available',
                                iconOf: (a) => accountTypeIcon(a.type.wire),
                                colorOf: (a) =>
                                    parseHexColor(a.color) ?? t.mutedForeground,
                                onChanged: (a) =>
                                    setState(() => _accountId = a?.id),
                                placeholder: 'Pick an account',
                              ),

                            if (_kind == TxKind.transfer)
                              PickerField<Account>(
                                label: 'To account',
                                value: accountById(_transferAccountId),
                                options: accounts
                                    .where((a) => a.id != _accountId)
                                    .toList(),
                                labelOf: (a) => a.name,
                                subtitleOf: (a) =>
                                    '${formatMoney(a.balance, currency: a.currency)} available',
                                iconOf: (a) => accountTypeIcon(a.type.wire),
                                colorOf: (a) =>
                                    parseHexColor(a.color) ?? t.mutedForeground,
                                onChanged: (a) =>
                                    setState(() => _transferAccountId = a?.id),
                                placeholder: 'Pick a destination',
                              ),

                            DateField(
                              label: 'Date',
                              value: _date,
                              onChanged: (d) =>
                                  setState(() => _date = d ?? _date),
                            ),
                          ],
                        ),
                      ),

                      const Gap(S.xs),
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const Gap(S.md),
                                    AppTextField(
                                      controller: _payee,
                                      label: 'Payee',
                                      placeholder: _kind == TxKind.income
                                          ? 'Who paid you'
                                          : 'Who you paid',
                                      prefixIcon: Icons.storefront_outlined,
                                    ),
                                    const Gap(S.md),
                                    AppTextField(
                                      controller: _note,
                                      label: 'Note',
                                      placeholder: 'What was it for?',
                                      maxLines: 3,
                                      prefixIcon: Icons.notes_outlined,
                                    ),
                                    const Gap(S.md),
                                    AppTextField(
                                      controller: _tags,
                                      label: 'Tags',
                                      hint:
                                          'Comma-separated. Tags let you slice spending in '
                                          'ways categories cannot   "wedding", "trip", "unnecessary".',
                                      placeholder: 'unnecessary, trip',
                                      prefixIcon: Icons.sell_outlined,
                                      textCapitalization:
                                          TextCapitalization.none,
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),

                      if (_error != null) ...[
                        const Gap(S.md),
                        FadeInUp(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: S.lg,
                              vertical: S.md,
                            ),
                            decoration: BoxDecoration(
                              color: t.danger.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(R.lg),
                              border: Border.all(
                                color: t.danger.withValues(alpha: 0.35),
                              ),
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
                                Icon(
                                  Icons.error_outline_rounded,
                                  size: 18,
                                  color: t.danger,
                                ),
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
                        ),
                      ],

                      const Gap(S.xl),
                      FadeInUp.staggered(
                        index: 8,
                        child: _GlowSubmitButton(
                          label: _isEdit
                              ? 'Save changes'
                              : 'Add ${_kind.label.toLowerCase()}',
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
      padding: const EdgeInsets.fromLTRB(S.xl, S.lg, S.md, S.lg),
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
          const Gap(S.lg),
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
              const GapX(S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: AppType.heading,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: t.foreground,
                      ),
                    ),
                    const Gap(S.xxs),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: AppType.bodySm,
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(R.md),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Kind picker ─────────────────────────────────────────────────────────────

/// Horizontal row of recent-payee chips above the detail fields.
class _RecentPayees extends StatelessWidget {
  const _RecentPayees({required this.payees, required this.onPick});

  final List<({String payee, String? categoryId})> payees;
  final void Function(String payee, String? categoryId) onPick;

  @override
  Widget build(BuildContext context) {
    if (payees.isEmpty) return const SizedBox.shrink();
    final t = context.t;

    return Padding(
      padding: const EdgeInsets.only(bottom: S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Recent'),
          const Gap(S.sm),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: payees.length,
              separatorBuilder: (_, _) => const GapX(S.sm),
              itemBuilder: (context, i) {
                final entry = payees[i];
                return PressableScale(
                  onTap: () => onPick(entry.payee, entry.categoryId),
                  child: Semantics(
                    button: true,
                    label: 'Use payee ${entry.payee}',
                    child: ExcludeSemantics(
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: S.md),
                        decoration: BoxDecoration(
                          color: t.surfaceMuted.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(R.pill),
                          border: Border.all(color: t.border),
                        ),
                        child: Text(
                          entry.payee,
                          style: TextStyle(
                            fontSize: AppType.label,
                            fontWeight: W.medium,
                            color: t.foreground,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

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
                              fontSize: AppType.label,
                              fontWeight: k == value
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: k == value ? active : t.mutedForeground,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  iconOf(k),
                                  size: 18,
                                  color: k == value
                                      ? active
                                      : t.mutedForeground,
                                ),
                                const Gap(S.xxs),
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
    required this.focused,
    required this.onFocusChange,
  });

  final TextEditingController controller;
  final String currency;
  final Color tint;
  final bool focused;
  final ValueChanged<bool> onFocusChange;

  @override
  State<_HeroAmountField> createState() => _HeroAmountFieldState();
}

class _HeroAmountFieldState extends State<_HeroAmountField> {
  late final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    widget.onFocusChange(_focus.hasFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final glow = widget.focused ? 0.2 : 0.06;

    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.easeOut,
      padding: const EdgeInsets.all(S.hair),
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
            blurRadius: widget.focused ? 22 : 16,
            spreadRadius: -6,
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(S.xl, S.lg, S.xl, S.lg),
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
                fontSize: AppType.caption,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: widget.tint.withValues(alpha: 0.85),
              ),
            ),
            const Gap(S.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedDefaultTextStyle(
                  duration: Motion.fast,
                  style: TextStyle(
                    fontSize: AppType.figure,
                    fontWeight: FontWeight.w700,
                    color: widget.tint.withValues(alpha: 0.65),
                  ),
                  child: Text(currencySymbol(widget.currency)),
                ),
                const GapX(S.sm),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    // Never autofocus. The sheet lives inside an AnimatedSwitcher
                    // that remounts this field whenever the kind changes or the
                    // form rebuilds, and each remount re-fired autofocus - so the
                    // keyboard kept shoving itself back up over whatever you were
                    // trying to tap. It opens when you tap the amount, and only
                    // then.
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    // Tapping anywhere else puts it away again.
                    onTapOutside: (_) => _focus.unfocus(),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'),
                      ),
                    ],
                    cursorColor: widget.tint,
                    style: TextStyle(
                      fontSize: AppType.hero,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.5,
                      color: widget.tint,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      height: 1.1,
                    ),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: TextStyle(
                        fontSize: AppType.hero,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: S.md,
                    vertical: S.xs,
                  ),
                  decoration: BoxDecoration(
                    color: widget.tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(R.pill),
                    border: Border.all(
                      color: widget.tint.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    widget.currency,
                    style: TextStyle(
                      fontSize: AppType.caption,
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
          padding: const EdgeInsets.symmetric(
            vertical: S.sm,
            horizontal: S.xxs,
          ),
          child: Row(
            children: [
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: Motion.fast,
                curve: Motion.easeOut,
                child: Icon(
                  Icons.expand_more_rounded,
                  size: 20,
                  color: t.primary,
                ),
              ),
              const GapX(S.xs),
              Text(
                expanded ? 'Fewer details' : 'More details',
                style: TextStyle(
                  fontSize: AppType.bodySm,
                  fontWeight: FontWeight.w600,
                  color: t.primary,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.auto_awesome_outlined,
                size: 14,
                color: t.mutedForeground.withValues(alpha: 0.6),
              ),
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
              ? [tint, Color.lerp(tint, t.accent, 0.45)!]
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
                      Icon(
                        Icons.bolt_rounded,
                        color: t.primaryForeground,
                        size: 20,
                      ),
                      const GapX(S.sm),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: AppType.lead,
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

/// Where the extra comes from when a plan cannot cover a spend.
///
/// Refusing an overspend outright reads as strict but teaches nothing - people
/// record it as unplanned instead, which quietly ruins both numbers. Naming the
/// source is the part actually worth knowing, and it keeps the books balanced:
/// the money is moved into the plan first, and the plan is raised to match.
class _CoverPicker extends StatelessWidget {
  const _CoverPicker({
    required this.plan,
    required this.shortfall,
    required this.plans,
    required this.accounts,
    required this.value,
    required this.onChanged,
  });

  final BudgetSpendSource plan;
  final double shortfall;
  final List<BudgetSpendSource> plans;
  final List<Account> accounts;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    final donorPlans = plans
        .where(
          (p) =>
              !p.isUnplanned &&
              p.id != plan.id &&
              p.currency == plan.currency &&
              p.remaining >= shortfall,
        )
        .toList();
    final donorAccounts = accounts
        .where((a) => a.currency == plan.currency && asNum(a.balance) >= shortfall)
        .toList();

    final options = <_CoverOption>[
      for (final p in donorPlans)
        _CoverOption(
          key: 'plan:${p.id}',
          title: p.name,
          subtitle: '${formatMoney(p.balance ?? '0', currency: p.currency)} held',
          icon: financeIcon(p.icon),
          color: parseHexColor(p.color) ?? t.primary,
        ),
      for (final a in donorAccounts)
        _CoverOption(
          key: 'account:${a.id}',
          title: a.name,
          subtitle: '${formatMoney(a.balance, currency: a.currency)} free',
          icon: accountTypeIcon(a.type.wire),
          color: parseHexColor(a.color) ?? t.mutedForeground,
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(S.md),
      decoration: BoxDecoration(
        color: t.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: t.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: t.warning),
              const GapX(S.sm),
              Expanded(
                child: Text(
                  '${plan.name} is ${formatMoney(shortfall, currency: plan.currency)} short. '
                  'Where should the extra come from?',
                  style: TextStyle(
                    fontSize: AppType.bodySm,
                    height: 1.4,
                    color: t.foreground,
                  ),
                ),
              ),
            ],
          ),
          const Gap(S.sm),
          if (options.isEmpty)
            Text(
              'Nothing has ${formatMoney(shortfall, currency: plan.currency)} spare right now. '
              'Give money back from another plan first, or record this as Unplanned.',
              style: TextStyle(
                fontSize: AppType.caption,
                height: 1.4,
                color: t.mutedForeground,
              ),
            )
          else
            PickerField<_CoverOption>(
              label: 'Cover it from',
              value: options.where((o) => o.key == value).firstOrNull,
              options: options,
              labelOf: (o) => '${o.title} · ${o.subtitle}',
              iconOf: (o) => o.icon,
              colorOf: (o) => o.color,
              onChanged: (o) => onChanged(o?.key),
              allowClear: true,
              placeholder: 'Choose where to cover it from',
              sheetTitle: 'Cover the shortfall',
            ),
          if (value != null) ...[
            const Gap(S.xs),
            Text(
              '${plan.name} will be raised to match. The raise shows in its history, '
              'and undoing this expense undoes it too.',
              style: TextStyle(
                fontSize: AppType.caption,
                height: 1.4,
                color: t.mutedForeground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CoverOption {
  const _CoverOption({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  /// `plan:<id>` or `account:<id>`.
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}
