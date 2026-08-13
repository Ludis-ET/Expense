import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/haptics.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../models/money.dart';
import '../../state/data_state.dart';
import '../../state/sync_state.dart';

/// Opens the recent-movements sheet.
Future<void> showRecentMovements(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _RecentMovementsSheet(),
  );
}

/// Everything that just moved money, with a one-tap take-back.
///
/// Undo *removes* the movement rather than posting a mirror-image entry: a
/// mistake should leave no trace, the way crossing a line out of a paper ledger
/// does. The server re-proves the books afterwards, so an undo that would leave
/// money unaccounted for comes back refused, with the reason - which is exactly
/// what the user needs to know ("that money has already been spent").
class _RecentMovementsSheet extends StatefulWidget {
  const _RecentMovementsSheet();

  @override
  State<_RecentMovementsSheet> createState() => _RecentMovementsSheetState();
}

class _RecentMovementsSheetState extends State<_RecentMovementsSheet> {
  MovementsResponse? _data;
  String? _error;
  bool _loading = true;
  String? _undoing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await context.read<SyncState>().movements(limit: 30);
      if (!mounted) return;
      setState(() {
        _data = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your recent movements.';
        _loading = false;
      });
    }
  }

  Future<void> _undo(Movement movement) async {
    setState(() => _undoing = movement.id);
    Haptics.commit();
    try {
      final message = await context.read<SyncState>().undoMovement(movement.id);
      if (!mounted) return;
      await context.read<DataState>().refreshAfterWrite();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      Haptics.reject();
      // A refusal here is the invariant proof doing its job, and its wording
      // already says what to do instead ("that money has already been spent").
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiError ? e.message : 'Could not undo that.'),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _undoing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final items = _data?.items ?? const <Movement>[];

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(R.xl)),
        ),
        child: Column(
          children: [
            const Gap(S.sm),
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: t.border,
                  borderRadius: BorderRadius.circular(R.pill),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.sm),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, size: 20, color: t.primary),
                  const GapX(S.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Just happened',
                          style: TextStyle(
                            fontSize: AppType.lead,
                            fontWeight: FontWeight.w700,
                            color: t.foreground,
                          ),
                        ),
                        Text(
                          'Undo takes a movement back completely, for '
                          '${_data?.undoWindowHours ?? 48} hours.',
                          style: TextStyle(
                            fontSize: AppType.caption,
                            color: t.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _Message(text: _error!, onRetry: _load)
                  : items.isEmpty
                  ? const _Message(
                      text:
                          'Nothing has moved yet. Your most recent changes show '
                          'up here, ready to undo.',
                    )
                  : ListView.separated(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.xxl),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) => _MovementRow(
                        movement: items[i],
                        busy: _undoing == items[i].id,
                        onUndo: () => _undo(items[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({
    required this.movement,
    required this.busy,
    required this.onUndo,
  });

  final Movement movement;
  final bool busy;
  final VoidCallback onUndo;

  /// Each kind gets its own mark, because the list mixes things that are
  /// genuinely different: money leaving, money arriving, money merely tied up.
  (IconData, Color) _mark(SantimTokens t) => switch (movement.type) {
    MovementType.expense => (Icons.north_east_rounded, t.danger),
    MovementType.income => (Icons.south_west_rounded, t.success),
    MovementType.transfer => (Icons.swap_horiz_rounded, t.accent),
    MovementType.fund => (Icons.lock_outline_rounded, t.primary),
    MovementType.release => (Icons.lock_open_rounded, t.primary),
    MovementType.move => (Icons.multiple_stop_rounded, t.accent),
    MovementType.adjust => (Icons.tune_rounded, t.warning),
  };

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final (icon, color) = _mark(t);
    final negative = movement.value < 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.sm),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const GapX(S.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w600,
                    color: t.foreground,
                  ),
                ),
                Text(
                  [
                    if (movement.subtitle != null) movement.subtitle!,
                    relativeTime(movement.recordedAt),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppType.caption,
                    color: t.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const GapX(S.sm),
          Text(
            formatMoney(movement.amount.replaceFirst('-', ''),
                currency: movement.currency),
            style: TextStyle(
              fontSize: AppType.bodySm,
              fontWeight: FontWeight.w700,
              color: negative ? t.foreground : t.success,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const GapX(S.xs),
          if (movement.undoable)
            busy
                ? const SizedBox(
                    width: 32,
                    height: 32,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    onPressed: onUndo,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Undo',
                    icon: Icon(Icons.undo_rounded, size: 18, color: t.primary),
                  )
          else
            Tooltip(
              message: movement.blockedReason ?? 'Too old to undo',
              child: Icon(
                Icons.lock_clock,
                size: 16,
                color: t.mutedForeground.withValues(alpha: 0.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(S.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppType.bodySm,
                height: 1.5,
                color: t.mutedForeground,
              ),
            ),
            if (onRetry != null) ...[
              const Gap(S.md),
              TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}
