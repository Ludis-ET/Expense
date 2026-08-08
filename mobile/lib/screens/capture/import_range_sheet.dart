import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatting.dart';
import '../../state/capture_store.dart';
import '../../widgets/common.dart';

/// Choose how far back to import.
///
/// Live capture only sees messages that arrive after setup, so everything
/// before that moment needs an explicit import. Re-importing an overlapping
/// range is safe — the outbox de-duplicates on the phone and the server
/// fingerprints every message — which is why the presets can overlap freely.
class ImportRangeSheet extends StatefulWidget {
  const ImportRangeSheet({super.key});

  @override
  State<ImportRangeSheet> createState() => _ImportRangeSheetState();
}

class _ImportRangeSheetState extends State<ImportRangeSheet> {
  late DateTime _from;
  DateTime _to = DateTime.now();

  int? _matchCount;
  bool _counting = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _from = DateTime.now().subtract(const Duration(days: 90));
    WidgetsBinding.instance.addPostFrameCallback((_) => _recount());
  }

  Future<void> _recount() async {
    setState(() => _counting = true);
    try {
      final count = await context.read<CaptureStore>().countInRange(from: _from, to: _to);
      if (mounted) setState(() => _matchCount = count);
    } catch (_) {
      if (mounted) setState(() => _matchCount = null);
    } finally {
      if (mounted) setState(() => _counting = false);
    }
  }

  void _preset(Duration span) {
    setState(() {
      _to = DateTime.now();
      _from = DateTime.now().subtract(span);
    });
    _recount();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked == null) return;

    setState(() {
      _from = picked.start;
      // Include the whole end day, not just its first instant.
      _to = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
    });
    _recount();
  }

  Future<void> _import() async {
    setState(() => _importing = true);
    try {
      final queued = await context.read<CaptureStore>().backfill(from: _from, to: _to);
      if (!mounted) return;
      Navigator.pop(context);
      showOk(
        context,
        queued == 0
            ? 'No messages from your banks in that range'
            : 'Importing $queued message${queued == 1 ? '' : 's'} — they will appear shortly',
      );
    } catch (_) {
      if (mounted) showError(context, 'Could not read the SMS inbox');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capture = context.watch<CaptureStore>();
    final installedAt = capture.native.installedAt;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Import past messages',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              installedAt == null
                  ? 'Messages that arrive from now on are captured automatically. This brings in older ones.'
                  : 'Anything since ${Dates.day(installedAt)} is already captured automatically. '
                      'This brings in what came before.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Preset(label: 'Last 30 days', onTap: () => _preset(const Duration(days: 30))),
                _Preset(label: '3 months', onTap: () => _preset(const Duration(days: 90))),
                _Preset(label: '6 months', onTap: () => _preset(const Duration(days: 182))),
                _Preset(label: '1 year', onTap: () => _preset(const Duration(days: 365))),
                _Preset(label: 'Everything', onTap: () => _preset(const Duration(days: 3650))),
              ],
            ),

            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _pickRange,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.date_range_outlined, size: 19),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Range', style: theme.textTheme.labelSmall),
                          Text(
                            '${Dates.day(_from)} → ${Dates.day(_to)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.edit_calendar_outlined, size: 19),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  if (_counting)
                    const SizedBox(
                      height: 15,
                      width: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(Icons.sms_outlined, size: 17, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _counting
                          ? 'Counting…'
                          : _matchCount == null
                              ? 'Could not read the SMS inbox'
                              : '$_matchCount message${_matchCount == 1 ? '' : 's'} from your banks in this range',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),
            FilledButton(
              onPressed: _importing || (_matchCount ?? 0) == 0 ? null : _import,
              child: _importing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Text('Import'),
            ),
            const SizedBox(height: 6),
            Text(
              'Importing the same range twice is harmless — duplicates are dropped.',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Preset extends StatelessWidget {
  const _Preset({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(label: Text(label), onPressed: onTap);
}
