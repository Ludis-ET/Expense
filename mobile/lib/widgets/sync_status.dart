import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../offline/sync_engine.dart';
import '../state/data_store.dart';

/// Compact animated indicator of online / syncing / pending state.
class SyncStatusPill extends StatelessWidget {
  const SyncStatusPill({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncEngine>();
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;

    final (label, color, icon) = switch ((sync.online, sync.isSyncing, sync.pending)) {
      (false, _, _) => ('Offline', colors.amber, Icons.cloud_off_outlined),
      (true, true, _) => ('Syncing…', colors.cyan, Icons.sync),
      (true, false, > 0) => (
          compact ? '${sync.pending}' : 'Outbox · ${sync.pending} pending',
          colors.amber,
          Icons.cloud_upload_outlined,
        ),
      _ => ('All synced', colors.mint, Icons.check_rounded),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sync.isSyncing)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
            )
          else
            Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sticky strip under the app bar when offline or serving cached figures.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncEngine>();
    final fromCache = context.select<DataStore, bool>((d) => d.servingFromCache);

    if (sync.online && !fromCache && !sync.hasPending) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;
    final offline = !sync.online;
    final message = offline
        ? (sync.hasPending
            ? 'You are offline · ${sync.pending} change${sync.pending == 1 ? '' : 's'} waiting to sync'
            : 'You are offline · showing saved data')
        : sync.hasPending
            ? '${sync.pending} change${sync.pending == 1 ? '' : 's'} waiting to sync'
            : 'Showing saved data · pull to refresh';

    return Material(
      color: offline
          ? colors.amber.withValues(alpha: 0.14)
          : colors.cyan.withValues(alpha: 0.1),
      child: InkWell(
        onTap: sync.online ? () => sync.sync() : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(
                offline ? Icons.wifi_off_rounded : Icons.cloud_upload_outlined,
                size: 16,
                color: offline ? colors.amber : colors.cyan,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (sync.online && sync.hasPending)
                Text(
                  'Sync',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colors.cyan,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Settings panel listing queued writes and rejected ones.
class PendingChangesPanel extends StatelessWidget {
  const PendingChangesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncEngine>();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            sync.online ? Icons.cloud_sync_outlined : Icons.cloud_off_outlined,
            color: sync.online ? theme.colorScheme.primary : SantimTheme.warning,
          ),
          title: Text(
            sync.online ? 'Online' : 'Offline',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            [
              if (sync.lastSyncedAt != null) 'Last sync ${_ago(sync.lastSyncedAt!)}',
              if (sync.lastCachedAt != null) 'Cache ${_ago(sync.lastCachedAt!)}',
              if (sync.hasPending) '${sync.pending} waiting',
              if (!sync.hasPending && sync.lastSyncedAt == null) 'Ready when you make a change',
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          trailing: sync.hasPending
              ? FilledButton.tonal(
                  onPressed: sync.isSyncing ? null : () => sync.sync(),
                  child: sync.isSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sync now'),
                )
              : null,
        ),
        if (sync.rejected.isNotEmpty) ...[
          const Divider(height: 20),
          Text(
            'Could not sync',
            style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 6),
          for (final msg in sync.rejected.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('· $msg', style: theme.textTheme.bodySmall),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: sync.clearRejected,
              child: const Text('Dismiss'),
            ),
          ),
        ],
        if (sync.hasPending) ...[
          const Divider(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _confirmDiscard(context, sync),
              child: Text(
                'Discard ${sync.pending} pending change${sync.pending == 1 ? '' : 's'}',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmDiscard(BuildContext context, SyncEngine sync) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard pending changes?'),
        content: Text(
          'This permanently drops ${sync.pending} edit${sync.pending == 1 ? '' : 's'} '
          'that have not reached the server yet.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 40)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (ok == true) await sync.discardPending();
  }

  String _ago(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
