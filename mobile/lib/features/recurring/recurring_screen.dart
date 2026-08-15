import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/layout.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../core/utils/monthly_outlook.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';
import '../outlook/monthly_outlook_screen.dart';

/// Recurring plans   rent, salary, subscriptions. Auto-posting rules write
/// themselves into your ledger when they come due; the rest wait for a tap.
class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final data = context.watch<DataState>();
    final prefs = context.watch<PrefsState>();

    final rules = (data.recurring.data ?? const <RecurringRule>[])
        .where((r) => r.currency == data.activeCurrency)
        .toList();
    final active = rules.where((r) => r.active).toList()
      ..sort((a, b) => a.nextRun.compareTo(b.nextRun));
    final paused = rules.where((r) => !r.active).toList();

    final monthlyOut = active
        .where((r) => r.kind == TxKind.expense)
        .fold<double>(
          0,
          (s, r) =>
              s +
              monthlyEquivalentAmount(toNum(r.amount), r.frequency, r.interval),
        );
    final monthlyIn = active
        .where((r) => r.kind == TxKind.income)
        .fold<double>(
          0,
          (s, r) =>
              s +
              monthlyEquivalentAmount(toNum(r.amount), r.frequency, r.interval),
        );

    String money(Object? v) => prefs.money(v, currency: data.activeCurrency);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Recurring',
          style: TextStyle(
            fontSize: AppType.lead,
            fontWeight: FontWeight.w700,
            color: t.foreground,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: S.sm),
            child: Center(
              child: HeaderAction(
                icon: Icons.add_rounded,
                label: 'New rule',
                onTap: () async {
                  final saved = await showRecurringForm(context);
                  if (saved == true && context.mounted) {
                    await context.read<DataState>().loadRecurring(force: true);
                  }
                },
              ),
            ),
          ),
        ],
      ),
      body: MeshBackground(
        showGrid: false,
        child: RefreshIndicator(
          onRefresh: () => data.loadRecurring(force: true),
          color: t.primary,
          backgroundColor: t.surface,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              14,
              4,
              14,
              ShellLayout.bottomClearance(context),
            ),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (!data.recurring.hasData) ...[
                if (data.recurring.hasError)
                  ErrorState(
                    message: data.recurring.errorMessage,
                    onRetry: () => data.loadRecurring(force: true),
                  )
                else
                  const PageLoader(rows: 4),
              ] else ...[
                FadeInUp(
                  child: Row(
                    children: [
                      Expanded(
                        child: _Stat(
                          label: 'Committed out',
                          value: money(monthlyOut),
                          hint: 'per month',
                          color: t.danger,
                          icon: Icons.north_east_rounded,
                        ),
                      ),
                      const GapX(S.sm),
                      Expanded(
                        child: _Stat(
                          label: 'Expected in',
                          value: money(monthlyIn),
                          hint: 'per month',
                          color: t.success,
                          icon: Icons.south_west_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(S.sm),
                AppButton(
                  label: 'Open monthly outlook',
                  icon: Icons.insights_rounded,
                  expand: true,
                  variant: BtnVariant.outline,
                  size: BtnSize.sm,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MonthlyOutlookScreen(),
                    ),
                  ),
                ),
                const Gap(S.lg),

                if (active.isEmpty && paused.isEmpty)
                  EmptyState(
                    icon: Icons.repeat,
                    art: EmptyArt.calendar,
                    title: 'No recurring plans yet',
                    description:
                        'Set up rent, salary or a subscription once and '
                        'let it post itself.',
                    action: AppButton(
                      label: 'Add a rule',
                      icon: Icons.add,
                      size: BtnSize.sm,
                      onPressed: () async {
                        final saved = await showRecurringForm(context);
                        if (saved == true && context.mounted) {
                          await context.read<DataState>().loadRecurring(
                            force: true,
                          );
                        }
                      },
                    ),
                  ),

                if (active.isNotEmpty) ...[
                  SectionLabel('ACTIVE'),
                  for (var i = 0; i < active.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: S.md),
                      child: FadeInUp.staggered(
                        index: i,
                        child: _RuleCard(rule: active[i], money: money),
                      ),
                    ),
                ],

                if (paused.isNotEmpty) ...[
                  const Gap(S.sm),
                  SectionLabel('PAUSED'),
                  for (final r in paused)
                    Padding(
                      padding: const EdgeInsets.only(bottom: S.md),
                      child: Opacity(
                        opacity: 0.6,
                        child: _RuleCard(rule: r, money: money),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.hint,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final String hint;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const GapX(S.xs),
              Expanded(child: Muted(label, size: 11.5, maxLines: 1)),
            ],
          ),
          const Gap(S.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Amount(value, size: 19, color: color),
          ),
          const Gap(S.hair),
          Muted(hint, size: 10.5),
        ],
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.rule, required this.money});

  final RecurringRule rule;
  final String Function(Object?) money;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final r = rule;
    final isIncome = r.kind == TxKind.income;
    final tint =
        parseHexColor(r.category?.color) ??
        (isIncome ? t.success : t.mutedForeground);
    final due = r.nextRun.difference(DateTime.now()).inDays;

    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      onTap: () => _menu(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(
                icon: financeIcon(r.category?.icon),
                color: tint,
                size: 42,
              ),
              const GapX(S.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppType.body,
                        fontWeight: FontWeight.w700,
                        color: t.foreground,
                      ),
                    ),
                    const Gap(S.xxs),
                    Row(
                      children: [
                        AppBadge(
                          r.cadence,
                          tone: BadgeTone.neutral,
                          dense: true,
                        ),
                        const GapX(S.xs),
                        if (r.autoPost)
                          AppBadge(
                            'Auto',
                            tone: BadgeTone.primary,
                            dense: true,
                            icon: Icons.bolt,
                          )
                        else
                          AppBadge(
                            'Manual',
                            tone: BadgeTone.warning,
                            dense: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const GapX(S.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Amount(
                    '${isIncome ? '+' : '−'}${money(r.amount)}',
                    size: 15,
                    color: isIncome ? t.success : t.foreground,
                  ),
                  const Gap(S.hair),
                  Muted(r.account?.name ?? '', size: 10.5, maxLines: 1),
                ],
              ),
            ],
          ),
          const Gap(S.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: S.md,
              vertical: S.sm,
            ),
            decoration: BoxDecoration(
              color: due <= 2 && r.active
                  ? t.warning.withValues(alpha: 0.1)
                  : t.surfaceMuted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(R.sm + 2),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.event_outlined,
                  size: 14,
                  color: due <= 2 && r.active ? t.warning : t.mutedForeground,
                ),
                const GapX(S.sm),
                Expanded(
                  child: Text(
                    r.active
                        ? 'Next ${formatDate(r.nextRun)} · ${relativeTime(r.nextRun)}'
                        : 'Paused',
                    style: TextStyle(
                      fontSize: AppType.caption,
                      color: due <= 2 && r.active
                          ? t.warning
                          : t.mutedForeground,
                    ),
                  ),
                ),
                if (r.postedCount > 0)
                  Muted('${r.postedCount} posted', size: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _menu(BuildContext context) async {
    final api = context.read<ApiClient>();
    final data = context.read<DataState>();

    final action = await showAppSheet<String>(
      context,
      title: rule.name,
      subtitle: rule.cadence,
      scrollable: false,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: 16 + MediaQuery.of(ctx).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              onTap: () => Navigator.pop(ctx, 'run'),
              leading: const Icon(Icons.play_arrow_rounded, size: 21),
              title: const Text(
                'Post it now',
                style: TextStyle(fontSize: AppType.body),
              ),
              subtitle: const Text(
                'Writes the transaction and moves the next run forward.',
                style: TextStyle(fontSize: AppType.caption),
              ),
            ),
            ListTile(
              onTap: () => Navigator.pop(ctx, 'edit'),
              leading: const Icon(Icons.edit_outlined, size: 20),
              title: const Text(
                'Edit',
                style: TextStyle(fontSize: AppType.body),
              ),
            ),
            ListTile(
              onTap: () => Navigator.pop(ctx, 'toggle'),
              leading: Icon(
                rule.active
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
                size: 20,
              ),
              title: Text(
                rule.active ? 'Pause' : 'Resume',
                style: const TextStyle(fontSize: AppType.body),
              ),
            ),
            ListTile(
              onTap: () => Navigator.pop(ctx, 'delete'),
              leading: Icon(
                Icons.delete_outline,
                size: 20,
                color: ctx.t.danger,
              ),
              title: Text(
                'Delete',
                style: TextStyle(fontSize: AppType.body, color: ctx.t.danger),
              ),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    try {
      switch (action) {
        case 'run':
          await api.post('/recurring/${rule.id}/run-now');
          await data.loadRecurring(force: true);
          await data.refreshAfterWrite();
          if (context.mounted) toast(context, 'Posted');
        case 'edit':
          final saved = await showRecurringForm(context, existing: rule);
          if (saved == true) await data.loadRecurring(force: true);
        case 'toggle':
          await api.put(
            '/recurring/${rule.id}',
            body: {'active': !rule.active},
          );
          await data.loadRecurring(force: true);
        case 'delete':
          if (!context.mounted) return;
          final ok = await confirm(
            context,
            title: 'Delete ${rule.name}?',
            message: 'Transactions it already posted stay in your history.',
          );
          if (!ok) return;
          await api.delete('/recurring/${rule.id}');
          await data.loadRecurring(force: true);
      }
    } on ApiError catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }
}

/// Add or edit a recurring rule.
/// Seed values for a brand-new rule   used by the outlook when turning a
/// detected repeating payee into a real rule, so the user only confirms.
class RecurringPrefill {
  const RecurringPrefill({
    required this.name,
    required this.amount,
    required this.kind,
    this.frequency = Frequency.monthly,
    this.payee,
    this.categoryId,
  });

  final String name;
  final double amount;
  final TxKind kind;
  final Frequency frequency;
  final String? payee;
  final String? categoryId;
}

Future<bool?> showRecurringForm(
  BuildContext context, {
  RecurringRule? existing,
  RecurringPrefill? prefill,
}) {
  return showAppSheet<bool>(
    context,
    title: existing == null ? 'New recurring rule' : 'Edit rule',
    builder: (ctx) => _RecurringForm(existing: existing, prefill: prefill),
  );
}

class _RecurringForm extends StatefulWidget {
  const _RecurringForm({this.existing, this.prefill});
  final RecurringRule? existing;
  final RecurringPrefill? prefill;

  @override
  State<_RecurringForm> createState() => _RecurringFormState();
}

class _RecurringFormState extends State<_RecurringForm> {
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
  late DateTime _nextRun = widget.existing?.nextRun ?? DateTime.now();
  late DateTime? _endDate = widget.existing?.endDate;
  late bool _autoPost = widget.existing?.autoPost ?? true;
  late bool _active = widget.existing?.active ?? true;

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final data = context.read<DataState>();
      await Future.wait([data.loadAccounts(), data.loadCategories()]);
      if (!mounted || _accountId != null) return;
      final accounts = data.scopedAccounts;
      final fallback =
          accounts.where((a) => a.isDefault).firstOrNull ??
          accounts.firstOrNull;
      setState(() => _accountId = fallback?.id);
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
            label: 'Account',
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
