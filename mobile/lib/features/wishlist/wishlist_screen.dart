import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../state/sync_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/sync_ui.dart';
import '../../widgets/ui.dart';
import '../budgets/budget_detail_screen.dart';

/// Wishlist. A want is just the idea of a thing — no cost, no savings — until
/// you turn it into a funded plan.
class WishlistScreen extends StatefulWidget {
  const WishlistScreen({super.key});

  @override
  State<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends State<WishlistScreen> {
  WishlistResponse? _data;
  bool _loading = true;
  Object? _error;
  WishlistStatus? _filter = WishlistStatus.wanting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final json = await context.read<ApiClient>().get<Map<String, dynamic>>('/wishlist');
      if (!mounted) return;
      setState(() {
        _data = WishlistResponse.fromJson(json);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final data = _data;
    final items = data == null
        ? const <WishlistItem>[]
        : _filter == null
            ? data.items
            : data.items.where((w) => w.status == _filter).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Wishlist',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.foreground),
        ),
        actions: [
          IconPill(
            icon: Icons.add,
            tooltip: 'Add a want',
            onTap: () async {
              final saved = await showWishForm(context);
              if (saved == true) _load();
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: MeshBackground(
        showGrid: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: t.primary,
          backgroundColor: t.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 40),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const OfflineBanner(),
              Row(
                children: [
                  Expanded(
                    child: Muted(
                      'A want is just the idea of a thing. Turn one into a plan '
                      'and it starts holding real money.',
                      size: 12,
                      height: 1.45,
                      maxLines: 3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              if (data != null)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _Tab(
                        label: 'Wanting',
                        count: data.wanting,
                        active: _filter == WishlistStatus.wanting,
                        onTap: () => setState(() => _filter = WishlistStatus.wanting),
                      ),
                      const SizedBox(width: 8),
                      _Tab(
                        label: 'Planned',
                        count: data.planned,
                        active: _filter == WishlistStatus.planned,
                        onTap: () => setState(() => _filter = WishlistStatus.planned),
                      ),
                      const SizedBox(width: 8),
                      _Tab(
                        label: 'Bought',
                        count: data.bought,
                        active: _filter == WishlistStatus.bought,
                        onTap: () => setState(() => _filter = WishlistStatus.bought),
                      ),
                      const SizedBox(width: 8),
                      _Tab(
                        label: 'Dropped',
                        count: data.dropped,
                        active: _filter == WishlistStatus.dropped,
                        onTap: () => setState(() => _filter = WishlistStatus.dropped),
                      ),
                      const SizedBox(width: 8),
                      _Tab(
                        label: 'All',
                        count: data.total,
                        active: _filter == null,
                        onTap: () => setState(() => _filter = null),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              if (_loading && data == null)
                const PageLoader(rows: 4, hero: false)
              else if (_error != null && data == null)
                ErrorState(
                  message: _error is ApiError
                      ? (_error as ApiError).message
                      : 'Could not load your wishlist.',
                  onRetry: _load,
                )
              else if (items.isEmpty)
                EmptyState(
                  icon: Icons.favorite_border,
                  title: _filter == null ? 'Nothing on the list yet' : 'Nothing here',
                  description: 'Add the things you want. No price needed — '
                      'you decide the cost when you turn one into a plan.',
                  action: AppButton(
                    label: 'Add a want',
                    icon: Icons.add,
                    size: BtnSize.sm,
                    onPressed: () async {
                      final saved = await showWishForm(context);
                      if (saved == true) _load();
                    },
                  ),
                )
              else
                for (var i = 0; i < items.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 11),
                    child: FadeInUp.staggered(
                      index: i,
                      child: _WishCard(
                        item: items[i],
                        onChanged: _load,
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

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: active ? t.primary.withValues(alpha: 0.12) : t.surface,
          borderRadius: BorderRadius.circular(R.pill),
          border: Border.all(color: active ? t.primary.withValues(alpha: 0.35) : t.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? t.primary : t.foreground,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active ? t.primary : t.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WishCard extends StatelessWidget {
  const _WishCard({required this.item, required this.onChanged});

  final WishlistItem item;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final prefs = context.watch<PrefsState>();
    final plan = item.plan;

    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => _openMenu(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: t.surfaceMuted.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(R.md),
                ),
                alignment: Alignment.center,
                child: Text(item.emoji ?? '✨', style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.foreground,
                        decoration: item.status == WishlistStatus.dropped
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        AppBadge(
                          item.status.label,
                          tone: switch (item.status) {
                            WishlistStatus.planned => BadgeTone.primary,
                            WishlistStatus.bought => BadgeTone.success,
                            WishlistStatus.dropped => BadgeTone.neutral,
                            WishlistStatus.wanting => BadgeTone.info,
                          },
                          dense: true,
                        ),
                        const SizedBox(width: 6),
                        _PriorityDots(priority: item.priority),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.more_horiz, size: 19, color: t.mutedForeground),
            ],
          ),
          if (item.note != null) ...[
            const SizedBox(height: 10),
            Text(
              item.note!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, height: 1.45, color: t.mutedForeground),
            ),
          ],
          if (plan != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: t.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: t.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  IconTile(
                    icon: financeIcon(plan.icon),
                    color: parseHexColor(plan.color) ?? t.primary,
                    size: 30,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: t.foreground,
                          ),
                        ),
                        Muted(
                          '${prefs.money(plan.plannedAmount, currency: plan.currency)} planned',
                          size: 11,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: t.primary),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openMenu(BuildContext context) async {
    final action = await showAppSheet<String>(
      context,
      title: item.name,
      subtitle: item.status.label,
      scrollable: false,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: 16 + MediaQuery.of(ctx).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.plan != null)
              _Action(icon: Icons.savings_outlined, label: 'Open the plan', value: 'plan'),
            if (item.plan == null && item.status != WishlistStatus.bought)
              _Action(
                icon: Icons.add_circle_outline,
                label: 'Turn into a plan',
                value: 'make-plan',
              ),
            if (item.status != WishlistStatus.bought)
              _Action(
                icon: Icons.check_circle_outline,
                label: 'Mark as bought',
                value: 'bought',
              ),
            if (item.link != null)
              _Action(icon: Icons.open_in_new, label: 'Open link', value: 'link'),
            _Action(icon: Icons.edit_outlined, label: 'Edit', value: 'edit'),
            if (item.status != WishlistStatus.dropped)
              _Action(icon: Icons.block, label: 'Drop it', value: 'drop'),
            _Action(
              icon: Icons.delete_outline,
              label: 'Delete',
              value: 'delete',
              danger: true,
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case 'plan':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => BudgetDetailScreen(budgetId: item.plan!.id)),
        );
        onChanged();
      case 'make-plan':
        final made = await showWishPlanSheet(context, item: item);
        if (made == true) {
          onChanged();
          if (context.mounted) await context.read<DataState>().refreshAfterWrite();
        }
      case 'bought':
        try {
          final result = await context.read<SyncState>().wishlistBought(
                item.id,
                name: item.name,
              );
          if (result.queued && context.mounted) {
            toast(context, 'Queued offline — will sync when you are back online');
          }
          onChanged();
        } on ApiError catch (e) {
          if (context.mounted) toast(context, e.message, error: true);
        }
      case 'link':
        final uri = Uri.tryParse(item.link!);
        if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      case 'edit':
        final saved = await showWishForm(context, existing: item);
        if (saved == true) onChanged();
      case 'drop':
        try {
          final result = await context.read<SyncState>().saveWishlist(
                id: item.id,
                name: item.name,
                body: {'status': 'DROPPED'},
              );
          if (result.queued && context.mounted) {
            toast(context, 'Queued offline — will sync when you are back online');
          }
          onChanged();
        } on ApiError catch (e) {
          if (context.mounted) toast(context, e.message, error: true);
        }
      case 'delete':
        final ok = await confirm(
          context,
          title: 'Delete ${item.name}?',
          message: 'The want goes away. Any plan it created stays.',
        );
        if (!ok || !context.mounted) return;
        try {
          final result = await context.read<SyncState>().deleteWishlist(
                item.id,
                name: item.name,
              );
          if (result.queued && context.mounted) {
            toast(context, 'Delete queued — will sync when you are back online');
          }
          onChanged();
        } on ApiError catch (e) {
          if (context.mounted) toast(context, e.message, error: true);
        }
    }
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.value,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ListTile(
      onTap: () => Navigator.pop(context, value),
      leading: Icon(icon, size: 20, color: danger ? t.danger : t.mutedForeground),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w500,
          color: danger ? t.danger : t.foreground,
        ),
      ),
    );
  }
}

class _PriorityDots extends StatelessWidget {
  const _PriorityDots({required this.priority});
  final int priority;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Padding(
            padding: const EdgeInsets.only(right: 2.5),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Priority 1 is the most wanted, so the scale is inverted.
                color: i <= (6 - priority) ? t.warning : t.border,
              ),
            ),
          ),
      ],
    );
  }
}

/// Add or edit a want.
Future<bool?> showWishForm(BuildContext context, {WishlistItem? existing}) {
  return showAppSheet<bool>(
    context,
    title: existing == null ? 'Add a want' : 'Edit want',
    subtitle: 'No price needed. A want is just the idea of a thing.',
    builder: (ctx) => _WishForm(existing: existing),
  );
}

class _WishForm extends StatefulWidget {
  const _WishForm({this.existing});
  final WishlistItem? existing;

  @override
  State<_WishForm> createState() => _WishFormState();
}

class _WishFormState extends State<_WishForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late final _link = TextEditingController(text: widget.existing?.link ?? '');
  late String _emoji = widget.existing?.emoji ?? '✨';
  late double _priority = (widget.existing?.priority ?? 3).toDouble();
  bool _saving = false;
  String? _error;

  static const _emojis = [
    '✨', '📱', '💻', '🚗', '🏠', '👟', '👕', '🎧', '📷', '⌚', '🚲', '✈️',
    '🎮', '📚', '🛋️', '🧳', '💍', '🎸', '🏋️', '🍽️',
  ];

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give it a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'name': _name.text.trim(),
      'priority': _priority.round(),
      'emoji': _emoji,
      'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      'link': _link.text.trim().isEmpty ? null : _link.text.trim(),
    };
    try {
      final result = await context.read<SyncState>().saveWishlist(
            body: body,
            id: widget.existing?.id,
            name: _name.text.trim(),
          );
      if (!mounted) return;
      if (result.queued) {
        toast(context, 'Saved offline — will sync when you are back online');
      }
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
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _name,
            label: 'What do you want?',
            placeholder: 'A new laptop',
            prefixIcon: Icons.favorite_border,
            autofocus: widget.existing == null,
          ),
          const SizedBox(height: 18),
          FieldShell(
            label: 'Emoji',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _emojis)
                  GestureDetector(
                    onTap: () => setState(() => _emoji = e),
                    child: AnimatedContainer(
                      duration: Motion.fast,
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _emoji == e
                            ? t.primary.withValues(alpha: 0.15)
                            : t.surfaceMuted.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(R.sm),
                        border: Border.all(
                          color: _emoji == e ? t.primary : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(e, style: const TextStyle(fontSize: 18)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FieldShell(
            label: 'Priority ${_priority.round()} of 5',
            hint: '1 is the thing you want most.',
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: t.warning,
                inactiveTrackColor: t.surfaceMuted,
                thumbColor: t.warning,
                trackHeight: 4,
              ),
              child: Slider(
                value: _priority,
                min: 1,
                max: 5,
                divisions: 4,
                onChanged: (v) => setState(() => _priority = v),
              ),
            ),
          ),
          const SizedBox(height: 8),
          AppTextField(
            controller: _note,
            label: 'Note',
            placeholder: 'Why do you want it?',
            maxLines: 2,
            prefixIcon: Icons.notes_outlined,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _link,
            label: 'Link',
            placeholder: 'https://…',
            prefixIcon: Icons.link,
            keyboardType: TextInputType.url,
            textCapitalization: TextCapitalization.none,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: TextStyle(fontSize: 13, color: t.danger)),
          ],
          const SizedBox(height: 20),
          AppButton(
            label: widget.existing == null ? 'Add to wishlist' : 'Save changes',
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

/// Turn a want into a funded plan. This is the point where a price appears.
Future<bool?> showWishPlanSheet(BuildContext context, {required WishlistItem item}) {
  return showAppSheet<bool>(
    context,
    title: 'Turn "${item.name}" into a plan',
    subtitle: 'From here it holds real money you fill from a wallet.',
    builder: (ctx) => _WishPlanSheet(item: item),
  );
}

class _WishPlanSheet extends StatefulWidget {
  const _WishPlanSheet({required this.item});
  final WishlistItem item;

  @override
  State<_WishPlanSheet> createState() => _WishPlanSheetState();
}

class _WishPlanSheetState extends State<_WishPlanSheet> {
  final _amount = TextEditingController();
  late final _name = TextEditingController(text: widget.item.name);
  BudgetKind _kind = BudgetKind.oneTime;
  RecurrenceUnit? _unit = RecurrenceUnit.month;
  DateTime _startsAt = DateTime.now();
  DateTime? _endDate;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Set how much this will cost.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await context.read<SyncState>().wishlistPlan(
            id: widget.item.id,
            name: _name.text.trim(),
            body: {
              'name': _name.text.trim(),
              'plannedAmount': amount,
              'currency': context.read<DataState>().activeCurrency,
              'kind': _kind.wire,
              'startsAt': _startsAt.toUtc().toIso8601String(),
              'endDate': _endDate?.toUtc().toIso8601String(),
              if (_kind == BudgetKind.recurring) 'recurrenceUnit': _unit!.wire,
            },
          );
      if (!mounted) return;
      if (result.queued) {
        toast(context, 'Saved offline — will sync when you are back online');
      }
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

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AmountField(
            controller: _amount,
            currency: data.activeCurrency,
            label: 'What will it cost?',
            tint: t.primary,
            autofocus: true,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _name,
            label: 'Plan name',
            prefixIcon: Icons.badge_outlined,
          ),
          const SizedBox(height: 16),
          SegmentedTabs<BudgetKind>(
            value: _kind,
            options: const [BudgetKind.oneTime, BudgetKind.recurring],
            labelOf: (k) => k.label,
            iconOf: (k) => k == BudgetKind.oneTime ? Icons.flag_outlined : Icons.autorenew,
            onChanged: (k) => setState(() => _kind = k),
          ),
          if (_kind == BudgetKind.recurring) ...[
            const SizedBox(height: 16),
            PickerField<RecurrenceUnit>(
              label: 'Repeats every',
              value: _unit,
              options: RecurrenceUnit.values,
              labelOf: (u) => u.label,
              onChanged: (u) => setState(() => _unit = u ?? _unit),
            ),
          ],
          const SizedBox(height: 16),
          DateField(
            label: 'Starts',
            value: _startsAt,
            onChanged: (d) => setState(() => _startsAt = d ?? _startsAt),
          ),
          const SizedBox(height: 16),
          DateField(
            label: 'Target date',
            placeholder: 'No deadline',
            value: _endDate,
            allowClear: true,
            firstDate: _startsAt,
            onChanged: (d) => setState(() => _endDate = d),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: TextStyle(fontSize: 13, color: t.danger)),
          ],
          const SizedBox(height: 20),
          AppButton(
            label: 'Create the plan',
            icon: Icons.savings_outlined,
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
