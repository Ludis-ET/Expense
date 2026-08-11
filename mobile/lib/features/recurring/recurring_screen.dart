import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';

/// Recurring plans — rent, salary, subscriptions. Auto-posting rules write
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
        .fold<double>(0, (s, r) => s + _monthlyEquivalent(r));
    final monthlyIn = active
        .where((r) => r.kind == TxKind.income)
        .fold<double>(0, (s, r) => s + _monthlyEquivalent(r));

    String money(Object? v) => prefs.money(v, currency: data.activeCurrency);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Recurring',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.foreground),
        ),
        actions: [
          IconPill(
            icon: Icons.add,
            tooltip: 'New rule',
            onTap: () async {
              final saved = await showRecurringForm(context);
              if (saved == true && context.mounted) {
                await context.read<DataState>().loadRecurring(force: true);
              }
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: MeshBackground(
        showGrid: false,
        child: RefreshIndicator(
          onRefresh: () => data.loadRecurring(force: true),
          color: t.primary,
          backgroundColor: t.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 40),
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
                      const SizedBox(width: 10),
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
                const SizedBox(height: 16),

                if (active.isEmpty && paused.isEmpty)
                  EmptyState(
                    icon: Icons.repeat,
                    title: 'No recurring plans yet',
                    description: 'Set up rent, salary or a subscription once and '
                        'let it post itself.',
                    action: AppButton(
                      label: 'Add a rule',
                      icon: Icons.add,
                      size: BtnSize.sm,
                      onPressed: () async {
                        final saved = await showRecurringForm(context);
                        if (saved == true && context.mounted) {
                          await context.read<DataState>().loadRecurring(force: true);
                        }
                      },
                    ),
                  ),

                if (active.isNotEmpty) ...[
                  SectionLabel('ACTIVE'),
                  for (var i = 0; i < active.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 11),
                      child: FadeInUp.staggered(
                        index: i,
                        child: _RuleCard(rule: active[i], money: money),
                      ),
                    ),
                ],

                if (paused.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SectionLabel('PAUSED'),
                  for (final r in paused)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 11),
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

  /// Normalises every cadence to a per-month figure so the two totals compare.
  static double _monthlyEquivalent(RecurringRule r) {
    final amount = toNum(r.amount);
    final perPeriod = amount / r.interval;
    return switch (r.frequency) {
      Frequency.daily => perPeriod * 30,
      Frequency.weekly => perPeriod * 52 / 12,
      Frequency.monthly => perPeriod,
      Frequency.yearly => perPeriod / 12,
    };
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
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(child: Muted(label, size: 11.5, maxLines: 1)),
            ],
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Amount(value, size: 19, color: color),
          ),
          const SizedBox(height: 2),
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
    final tint = parseHexColor(r.category?.color) ?? (isIncome ? t.success : t.mutedForeground);
    final due = r.nextRun.difference(DateTime.now()).inDays;

    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => _menu(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(icon: financeIcon(r.category?.icon), color: tint, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.foreground,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        AppBadge(r.cadence, tone: BadgeTone.neutral, dense: true),
                        const SizedBox(width: 6),
                        if (r.autoPost)
                          AppBadge('Auto', tone: BadgeTone.primary, dense: true, icon: Icons.bolt)
                        else
                          AppBadge('Manual', tone: BadgeTone.warning, dense: true),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Amount(
                    '${isIncome ? '+' : '−'}${money(r.amount)}',
                    size: 15,
                    color: isIncome ? t.success : t.foreground,
                  ),
                  const SizedBox(height: 2),
                  Muted(r.account?.name ?? '', size: 10.5, maxLines: 1),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
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
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.active
                        ? 'Next ${formatDate(r.nextRun)} · ${relativeTime(r.nextRun)}'
                        : 'Paused',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: due <= 2 && r.active ? t.warning : t.mutedForeground,
                    ),
                  ),
                ),
                if (r.postedCount > 0) Muted('${r.postedCount} posted', size: 11),
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
        padding: EdgeInsets.only(bottom: 16 + MediaQuery.of(ctx).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              onTap: () => Navigator.pop(ctx, 'run'),
              leading: const Icon(Icons.play_arrow_rounded, size: 21),
              title: const Text('Post it now', style: TextStyle(fontSize: 14.5)),
              subtitle: const Text(
                'Writes the transaction and moves the next run forward.',
                style: TextStyle(fontSize: 11.5),
              ),
            ),
            ListTile(
              onTap: () => Navigator.pop(ctx, 'edit'),
              leading: const Icon(Icons.edit_outlined, size: 20),
              title: const Text('Edit', style: TextStyle(fontSize: 14.5)),
            ),
            ListTile(
              onTap: () => Navigator.pop(ctx, 'toggle'),
              leading: Icon(
                rule.active ? Icons.pause_circle_outline : Icons.play_circle_outline,
                size: 20,
              ),
              title: Text(
                rule.active ? 'Pause' : 'Resume',
                style: const TextStyle(fontSize: 14.5),
              ),
            ),
            ListTile(
              onTap: () => Navigator.pop(ctx, 'delete'),
              leading: Icon(Icons.delete_outline, size: 20, color: ctx.t.danger),
              title: Text(
                'Delete',
                style: TextStyle(fontSize: 14.5, color: ctx.t.danger),
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
          await api.put('/recurring/${rule.id}', body: {'active': !rule.active});
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
Future<bool?> showRecurringForm(BuildContext context, {RecurringRule? existing}) {
  return showAppSheet<bool>(
    context,
    title: existing == null ? 'New recurring rule' : 'Edit rule',
    builder: (ctx) => _RecurringForm(existing: existing),
  );
}

class _RecurringForm extends StatefulWidget {
  const _RecurringForm({this.existing});
  final RecurringRule? existing;

  @override
  State<_RecurringForm> createState() => _RecurringFormState();
}

class _RecurringFormState extends State<_RecurringForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _amount = TextEditingController(
    text: widget.existing == null ? '' : toNum(widget.existing!.amount).toString(),
  );
  late final _interval = TextEditingController(text: '${widget.existing?.interval ?? 1}');
  late final _payee = TextEditingController(text: widget.existing?.payee ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');

  late TxKind _kind = widget.existing?.kind ?? TxKind.expense;
  late Frequency _frequency = widget.existing?.frequency ?? Frequency.monthly;
  late String? _accountId = widget.existing?.accountId;
  late String? _categoryId = widget.existing?.categoryId;
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
      final fallback = accounts.where((a) => a.isDefault).firstOrNull ?? accounts.firstOrNull;
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
      'nextRun': _nextRun.toUtc().toIso8601String(),
      'autoPost': _autoPost,
      if (_frequency == Frequency.monthly) 'dayOfMonth': _nextRun.day,
      if (_payee.text.trim().isNotEmpty) 'payee': _payee.text.trim(),
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      if (_endDate != null) 'endDate': _endDate!.toUtc().toIso8601String(),
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
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).padding.bottom),
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
          const SizedBox(height: 18),
          AppTextField(
            controller: _name,
            label: 'Name',
            placeholder: _kind == TxKind.income ? 'Salary' : 'Rent',
            prefixIcon: Icons.badge_outlined,
            autofocus: !_isEdit,
          ),
          const SizedBox(height: 16),
          AmountField(
            controller: _amount,
            currency: widget.existing?.currency ?? data.activeCurrency,
            tint: _kind == TxKind.income ? t.success : t.danger,
          ),
          const SizedBox(height: 16),
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
              const SizedBox(width: 12),
              Expanded(
                child: PickerField<Frequency>(
                  label: 'Frequency',
                  value: _frequency,
                  options: Frequency.values,
                  labelOf: (f) => f.label,
                  onChanged: (f) => setState(() => _frequency = f ?? _frequency),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DateField(
            label: 'Next run',
            hint: 'The first date it posts. Later runs step forward by the cadence.',
            value: _nextRun,
            onChanged: (d) => setState(() => _nextRun = d ?? _nextRun),
          ),
          const SizedBox(height: 16),
          PickerField<Account>(
            label: 'Account',
            value: accounts.where((a) => a.id == _accountId).firstOrNull,
            options: accounts,
            labelOf: (a) => a.name,
            iconOf: (a) => accountTypeIcon(a.type.wire),
            colorOf: (a) => parseHexColor(a.color) ?? t.mutedForeground,
            onChanged: (a) => setState(() => _accountId = a?.id),
          ),
          const SizedBox(height: 16),
          PickerField<TxCategory>(
            label: 'Category',
            value: categories.where((c) => c.id == _categoryId).firstOrNull,
            options: categories,
            labelOf: (c) => c.name,
            iconOf: (c) => financeIcon(c.icon),
            colorOf: (c) => parseHexColor(c.color) ?? t.mutedForeground,
            onChanged: (c) => setState(() => _categoryId = c?.id),
          ),
          const SizedBox(height: 16),
          DateField(
            label: 'Ends',
            placeholder: 'Runs forever',
            value: _endDate,
            allowClear: true,
            firstDate: _nextRun,
            onChanged: (d) => setState(() => _endDate = d),
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 10),
          AppTextField(
            controller: _payee,
            label: 'Payee',
            placeholder: 'Optional',
            prefixIcon: Icons.storefront_outlined,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _note,
            label: 'Note',
            placeholder: 'Optional',
            maxLines: 2,
            prefixIcon: Icons.notes_outlined,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: TextStyle(fontSize: 13, color: t.danger)),
          ],
          const SizedBox(height: 20),
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
