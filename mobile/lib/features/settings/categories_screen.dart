import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../state/sync_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';

/// `CategoryManager` — the labels that make analytics mean anything.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  TxKind _kind = TxKind.expense;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DataState>().loadCategories(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final data = context.watch<DataState>();
    final all = data.categories.data ?? const <TxCategory>[];
    final wanted = _kind == TxKind.income ? 'INCOME' : 'EXPENSE';
    final active = all.where((c) => c.kind == wanted && !c.archived).toList();
    final archived = all.where((c) => c.kind == wanted && c.archived).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Categories',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.foreground),
        ),
        actions: [
          IconPill(
            icon: Icons.add,
            tooltip: 'New category',
            onTap: () => _edit(context, kind: _kind),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: MeshBackground(
        showGrid: false,
        child: RefreshIndicator(
          onRefresh: () => data.loadCategories(force: true),
          color: t.primary,
          backgroundColor: t.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 40),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SegmentedTabs<TxKind>(
                value: _kind,
                options: const [TxKind.expense, TxKind.income],
                labelOf: (k) => '${k.label} categories',
                colorOf: (k) => k == TxKind.income ? t.success : t.danger,
                onChanged: (k) => setState(() => _kind = k),
              ),
              const SizedBox(height: 16),
              if (!data.categories.hasData)
                const PageLoader(rows: 6, hero: false)
              else ...[
                for (var i = 0; i < active.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: FadeInUp.staggered(
                      index: i.clamp(0, 10),
                      child: _Row(
                        category: active[i],
                        onTap: () => _edit(context, existing: active[i]),
                      ),
                    ),
                  ),
                if (archived.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SectionLabel('ARCHIVED'),
                  for (final c in archived)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Opacity(
                        opacity: 0.6,
                        child: _Row(
                          category: c,
                          onTap: () => _edit(context, existing: c),
                        ),
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

  Future<void> _edit(BuildContext context, {TxCategory? existing, TxKind? kind}) async {
    final saved = await showAppSheet<bool>(
      context,
      title: existing == null ? 'New category' : 'Edit category',
      builder: (ctx) => _CategoryForm(existing: existing, kind: kind ?? _kind),
    );
    if (saved == true && context.mounted) {
      await context.read<DataState>().loadCategories(force: true);
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.category, required this.onTap});

  final TxCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      onTap: onTap,
      child: Row(
        children: [
          IconTile(
            icon: financeIcon(category.icon),
            color: parseHexColor(category.color),
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.foreground,
                  ),
                ),
                if (category.transactionCount != null) ...[
                  const SizedBox(height: 2),
                  Muted(
                    '${category.transactionCount} transaction'
                    '${category.transactionCount == 1 ? '' : 's'}',
                    size: 11,
                  ),
                ],
              ],
            ),
          ),
          if (category.isDefault) AppBadge('Built-in', dense: true),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, size: 18, color: t.mutedForeground),
        ],
      ),
    );
  }
}

class _CategoryForm extends StatefulWidget {
  const _CategoryForm({this.existing, required this.kind});

  final TxCategory? existing;
  final TxKind kind;

  @override
  State<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<_CategoryForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _icon = widget.existing?.icon ?? 'shopping-bag';
  late String _color = widget.existing?.color ?? '#10b981';
  late bool _archived = widget.existing?.archived ?? false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the category a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'name': _name.text.trim(),
      'kind': widget.kind == TxKind.income ? 'INCOME' : 'EXPENSE',
      'icon': _icon,
      'color': _color,
      if (_isEdit) 'archived': _archived,
    };
    try {
      final sync = context.read<SyncState>();
      final result = await sync.saveCategory(
        body: body,
        id: _isEdit ? widget.existing!.id : null,
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
    final tint = parseHexColor(_color) ?? t.primary;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: IconTile(icon: financeIcon(_icon), color: tint, size: 56, radius: R.lg),
          ),
          const SizedBox(height: 20),
          AppTextField(
            controller: _name,
            label: 'Name',
            placeholder: widget.kind == TxKind.income ? 'Salary' : 'Groceries',
            prefixIcon: Icons.label_outline,
            autofocus: !_isEdit,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 18),
          ColorPickerRow(
            value: _color,
            colors: financeColors,
            onChanged: (c) => setState(() => _color = c),
          ),
          const SizedBox(height: 18),
          IconPickerGrid(
            value: _icon,
            names: iconNames,
            iconOf: financeIcon,
            tint: tint,
            onChanged: (i) => setState(() => _icon = i),
          ),
          if (_isEdit && !widget.existing!.isDefault)
            SwitchRow(
              title: 'Archived',
              subtitle: 'Hidden from pickers, history is kept.',
              icon: Icons.inventory_2_outlined,
              value: _archived,
              onChanged: (v) => setState(() => _archived = v),
            ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: TextStyle(fontSize: 13, color: t.danger)),
          ],
          const SizedBox(height: 20),
          AppButton(
            label: _isEdit ? 'Save changes' : 'Create category',
            icon: Icons.check,
            size: BtnSize.lg,
            expand: true,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
          if (_isEdit && !widget.existing!.isDefault) ...[
            const SizedBox(height: 10),
            AppButton(
              label: 'Delete',
              icon: Icons.delete_outline,
              variant: BtnVariant.ghost,
              expand: true,
              onPressed: () async {
                final ok = await confirm(
                  context,
                  title: 'Delete ${widget.existing!.name}?',
                  message: 'Categories with transactions cannot be deleted — '
                      'archive them instead.',
                );
                if (!ok || !context.mounted) return;
                try {
                  await context
                      .read<ApiClient>()
                      .delete('/categories/${widget.existing!.id}');
                  if (context.mounted) Navigator.pop(context, true);
                } on ApiError catch (e) {
                  if (context.mounted) toast(context, e.message, error: true);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}
