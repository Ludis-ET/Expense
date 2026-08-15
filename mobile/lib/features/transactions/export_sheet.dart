import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../models/models.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';

/// Getting your history out of Santim.
///
/// Takes the same filters the list is using, so "export what I am looking at"
/// means exactly that - the range picker here is the only thing it adds. The
/// server streams the file; this saves it and hands it to the share sheet.
Future<void> showExportSheet(
  BuildContext context, {
  required Map<String, dynamic> filters,
}) {
  return showAppSheet<void>(
    context,
    title: 'Export',
    subtitle: 'A copy of your transactions, as a file you keep.',
    builder: (ctx) => _ExportSheet(filters: filters),
  );
}

/// The spans worth offering. "Everything" is last because it is the slowest and
/// the least often what someone means.
enum _Span { thisMonth, last3, thisYear, everything, custom }

extension on _Span {
  String get label => switch (this) {
    _Span.thisMonth => 'This month',
    _Span.last3 => 'Last 3 months',
    _Span.thisYear => 'This year',
    _Span.everything => 'Everything',
    _Span.custom => 'Custom',
  };

  /// Inclusive bounds, or nulls for an unbounded span.
  (DateTime?, DateTime?) range(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      _Span.thisMonth => (DateTime(now.year, now.month), today),
      _Span.last3 => (DateTime(now.year, now.month - 2), today),
      _Span.thisYear => (DateTime(now.year), today),
      _Span.everything => (null, null),
      _Span.custom => (null, null),
    };
  }
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.filters});
  final Map<String, dynamic> filters;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  _Span _span = _Span.thisMonth;
  String _format = 'csv';
  DateTime? _from;
  DateTime? _to;

  bool _counting = true;
  bool _running = false;
  int? _count;
  int? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _preview());
  }

  Map<String, dynamic> get _query {
    final (from, to) = _span == _Span.custom
        ? (_from, _to)
        : _span.range(DateTime.now());
    return {
      // The list's own filters first, so what is on screen is what comes out.
      ...widget.filters,
      if (from != null) 'from': wireDate(from),
      if (to != null) 'to': wireDate(to),
      'format': _format,
    };
  }

  Future<void> _preview() async {
    setState(() {
      _counting = true;
      _error = null;
    });
    try {
      final json = await context.read<ApiClient>().get<Map<String, dynamic>>(
        '/transactions/export/preview',
        query: _query,
      );
      if (!mounted) return;
      setState(() {
        _count = asInt(json['count']);
        _bytes = asInt(json['approxBytes']);
        _counting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _counting = false);
    }
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final api = context.read<ApiClient>();
      final body = await api.getRaw('/transactions/export', query: _query);

      final dir = await getTemporaryDirectory();
      final name = 'santim-${DateTime.now().toIso8601String().substring(0, 10)}.$_format';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(body);

      if (!mounted) return;
      setState(() => _running = false);

      // Share rather than silently saving: the file is the point, and the user
      // decides where it lands - Drive, Telegram, their own email.
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: _format == 'csv' ? 'text/csv' : 'application/json')],
          subject: 'Santim transactions',
        ),
      );
      if (result.status == ShareResultStatus.dismissed && mounted) {
        // Dismissing the share sheet should not lose the file.
        await OpenFilex.open(file.path);
      }
      if (mounted) Navigator.pop(context);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = 'Could not write the file. $e';
      });
    }
  }

  String get _sizeHint {
    if (_counting) return 'Counting…';
    final n = _count ?? 0;
    if (n == 0) return 'Nothing matches these filters';
    final kb = ((_bytes ?? 0) / 1024).round();
    final size = kb >= 1024 ? '${(kb / 1024).toStringAsFixed(1)} MB' : '$kb KB';
    return '$n transaction${n == 1 ? '' : 's'} · about $size';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final nothing = !_counting && (_count ?? 0) == 0;

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
          SectionLabel('RANGE'),
          const Gap(S.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _Span.values)
                _Chip(
                  label: s.label,
                  selected: _span == s,
                  onTap: () {
                    setState(() => _span = s);
                    if (s != _Span.custom || (_from != null && _to != null)) {
                      _preview();
                    }
                  },
                ),
            ],
          ),

          if (_span == _Span.custom) ...[
            const Gap(S.lg),
            Row(
              children: [
                Expanded(
                  child: DateField(
                    label: 'From',
                    value: _from,
                    onChanged: (d) {
                      setState(() => _from = d);
                      if (_to != null) _preview();
                    },
                  ),
                ),
                const GapX(S.md),
                Expanded(
                  child: DateField(
                    label: 'To',
                    value: _to,
                    onChanged: (d) {
                      setState(() => _to = d);
                      if (_from != null) _preview();
                    },
                  ),
                ),
              ],
            ),
          ],

          const Gap(S.xl),
          SectionLabel('FORMAT'),
          const Gap(S.sm),
          SegmentedTabs<String>(
            value: _format,
            options: const ['csv', 'json'],
            labelOf: (f) => f == 'csv' ? 'CSV · spreadsheet' : 'JSON · complete',
            iconOf: (f) =>
                f == 'csv' ? Icons.table_chart_outlined : Icons.data_object,
            onChanged: (f) => setState(() => _format = f),
          ),

          const Gap(S.lg),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: S.md,
              vertical: S.md,
            ),
            decoration: BoxDecoration(
              color: t.surfaceMuted.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Row(
              children: [
                Icon(
                  nothing ? Icons.filter_alt_off_outlined : Icons.description_outlined,
                  size: 16,
                  color: nothing ? t.warning : t.mutedForeground,
                ),
                const GapX(S.sm),
                Expanded(
                  child: Text(
                    _sizeHint,
                    style: TextStyle(
                      fontSize: AppType.bodySm,
                      color: t.foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_error != null) ...[
            const Gap(S.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: S.md,
                vertical: S.md,
              ),
              decoration: BoxDecoration(
                color: t.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: t.danger.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: t.danger),
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
          ],

          const Gap(S.xl),
          AppButton(
            label: 'Export',
            icon: Icons.ios_share_rounded,
            size: BtnSize.lg,
            expand: true,
            loading: _running,
            onPressed: _running || nothing ? null : _run,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: selected ? t.primary.withValues(alpha: 0.14) : t.surfaceMuted,
      borderRadius: BorderRadius.circular(R.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.pill),
            border: Border.all(
              color: selected ? t.primary.withValues(alpha: 0.5) : t.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppType.bodySm,
              fontWeight: selected ? W.semibold : W.regular,
              color: selected ? t.primary : t.foreground,
            ),
          ),
        ),
      ),
    );
  }
}
