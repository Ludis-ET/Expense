import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import '../core/utils/format.dart';
import '../data/outbox_store.dart';
import '../state/sync_state.dart';
import 'ui.dart';

/// Compact living status chip for the top bar — offline / syncing / pending / synced.
class SyncStatusPill extends StatefulWidget {
  const SyncStatusPill({super.key});

  @override
  State<SyncStatusPill> createState() => _SyncStatusPillState();
}

class _SyncStatusPillState extends State<SyncStatusPill> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncState>();
    final t = context.t;

    final Color accent;
    final String label;
    final IconData icon;
    final bool animate;

    if (sync.justSynced) {
      accent = t.success;
      label = 'Synced';
      icon = Icons.check_circle_rounded;
      animate = true;
    } else if (!sync.online) {
      accent = const Color(0xFF38BDF8);
      label = sync.pendingCount > 0 ? 'Offline · ${sync.pendingCount}' : 'Offline';
      icon = Icons.cloud_off_rounded;
      animate = true;
    } else if (sync.syncing) {
      accent = t.accent;
      label = 'Syncing';
      icon = Icons.sync_rounded;
      animate = true;
    } else if (sync.errorCount > 0) {
      accent = t.danger;
      label = '${sync.errorCount} failed';
      icon = Icons.error_outline_rounded;
      animate = true;
    } else if (sync.pendingCount > 0) {
      accent = t.warning;
      label = '${sync.pendingCount} queued';
      icon = Icons.cloud_queue_rounded;
      animate = true;
    } else {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final glow = animate ? 0.18 + _pulse.value * 0.22 : 0.12;
        return PressableScale(
          scale: 0.96,
          onTap: () {
            HapticFeedback.selectionClick();
            showSyncSheet(context);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.pill),
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.22 + glow * 0.35),
                  accent.withValues(alpha: 0.08),
                ],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.45 + glow)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.28 + glow * 0.4),
                  blurRadius: 14 + _pulse.value * 8,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (sync.syncing)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: accent,
                    ),
                  )
                else
                  Icon(icon, size: 13, color: accent),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: t.foreground,
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

Future<void> showSyncSheet(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 480),
    pageBuilder: (ctx, _, _) => const Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SyncSheet(),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Motion.spring);
      return Stack(
        fit: StackFit.expand,
        children: [
          FadeTransition(
            opacity: anim,
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12 * anim.value, sigmaY: 12 * anim.value),
                child: Container(color: Colors.black.withValues(alpha: 0.55 * anim.value)),
              ),
            ),
          ),
          SlideTransition(
            position: Tween(begin: const Offset(0, 0.2), end: Offset.zero).animate(curved),
            child: FadeTransition(opacity: curved, child: child),
          ),
        ],
      );
    },
  );
}

class SyncSheet extends StatelessWidget {
  const SyncSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final sync = context.watch<SyncState>();
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + bottom),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.72),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  t.surface.withValues(alpha: t.isDark ? 0.92 : 0.95),
                  t.surfaceMuted.withValues(alpha: t.isDark ? 0.88 : 0.92),
                ],
              ),
              border: Border.all(
                color: (sync.online ? t.primary : const Color(0xFF38BDF8))
                    .withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: (sync.online ? t.primary : const Color(0xFF38BDF8))
                      .withValues(alpha: 0.2),
                  blurRadius: 40,
                  spreadRadius: -10,
                  offset: const Offset(0, -4),
                ),
                ...t.elevatedShadow,
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(R.pill),
                    gradient: LinearGradient(
                      colors: [
                        t.primary.withValues(alpha: 0.4),
                        t.accent.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      _OrbitBadge(online: sync.online, syncing: sync.syncing),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sync.online ? 'Neural sync' : 'Offline mode',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                color: t.foreground,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              sync.online
                                  ? (sync.pendingCount > 0
                                      ? 'Pushing ${sync.pendingCount} queued change${sync.pendingCount == 1 ? '' : 's'}…'
                                      : sync.lastSyncedAt != null
                                          ? 'Last synced ${relativeTime(sync.lastSyncedAt!)}'
                                          : 'Live · everything is up to date')
                                  : 'Changes save on-device and sync when you reconnect',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                color: t.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close_rounded, color: t.mutedForeground),
                      ),
                    ],
                  ),
                ),

                // Status strip
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _StatOrb(
                          label: 'Queued',
                          value: '${sync.pendingCount}',
                          color: t.warning,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatOrb(
                          label: 'Failed',
                          value: '${sync.errorCount}',
                          color: t.danger,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatOrb(
                          label: 'Link',
                          value: sync.online ? 'Live' : 'Off',
                          color: sync.online ? t.success : const Color(0xFF38BDF8),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                if (sync.ops.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                    child: Column(
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 36,
                          color: t.primary.withValues(alpha: 0.7),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'All clear',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: t.foreground,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Muted(
                          'Nothing waiting to sync. Add a transaction offline and it will land here.',
                          size: 12.5,
                        ),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      itemCount: sync.ops.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => FadeInUp.staggered(
                        index: i.clamp(0, 8),
                        child: _OpCard(op: sync.ops[i]),
                      ),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: sync.syncing ? 'Syncing…' : 'Sync now',
                          icon: Icons.bolt_rounded,
                          expand: true,
                          loading: sync.syncing,
                          onPressed: !sync.online || sync.syncing
                              ? null
                              : () => context.read<SyncState>().flush(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbitBadge extends StatefulWidget {
  const _OrbitBadge({required this.online, required this.syncing});
  final bool online;
  final bool syncing;

  @override
  State<_OrbitBadge> createState() => _OrbitBadgeState();
}

class _OrbitBadgeState extends State<_OrbitBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.online ? context.t.primary : const Color(0xFF38BDF8);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [
                color.withValues(alpha: 0.05),
                color.withValues(alpha: 0.55),
                color.withValues(alpha: 0.05),
              ],
              transform: GradientRotation(_c.value * 6.2832),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 18,
                spreadRadius: -4,
              ),
            ],
          ),
          padding: const EdgeInsets.all(3),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.t.surface,
            ),
            child: Icon(
              widget.syncing
                  ? Icons.sync_rounded
                  : widget.online
                      ? Icons.cloud_done_rounded
                      : Icons.cloud_off_rounded,
              color: color,
              size: 22,
            ),
          ),
        );
      },
    );
  }
}

class _StatOrb extends StatelessWidget {
  const _StatOrb({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(R.lg),
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: t.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _OpCard extends StatelessWidget {
  const _OpCard({required this.op});
  final OutboxOp op;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final sync = context.read<SyncState>();
    final (icon, color) = switch (op.entity) {
      OutboxEntity.transaction => (Icons.receipt_long_rounded, t.primary),
      OutboxEntity.account => (Icons.account_balance_wallet_outlined, t.accent),
      OutboxEntity.category => (Icons.label_outline_rounded, t.success),
      OutboxEntity.budget => (Icons.pie_chart_outline_rounded, t.warning),
      OutboxEntity.ledger => (Icons.handshake_outlined, t.accent),
      OutboxEntity.wishlist => (Icons.favorite_border_rounded, t.danger),
    };

    final subtitle = op.detail ??
        op.error ??
        (op.status == OutboxStatus.syncing ? 'Uploading…' : 'Waiting for connection');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(R.lg),
        color: t.surfaceMuted.withValues(alpha: 0.55),
        border: Border.all(
          color: op.status == OutboxStatus.error
              ? t.danger.withValues(alpha: 0.4)
              : t.border.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          IconTile(icon: icon, color: color, size: 38),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  op.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: t.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Muted(subtitle, size: 11.5, maxLines: 2),
                if (op.optimistic != null) ...[
                  const SizedBox(height: 4),
                  Amount(
                    formatMoney(op.optimistic!.amount, currency: op.optimistic!.currency),
                    size: 12.5,
                    color: color,
                  ),
                ],
              ],
            ),
          ),
          if (op.status == OutboxStatus.error) ...[
            IconButton(
              tooltip: 'Retry',
              onPressed: () => sync.retry(op.id),
              icon: Icon(Icons.refresh_rounded, color: t.primary, size: 20),
            ),
            IconButton(
              tooltip: 'Discard',
              onPressed: () => sync.discard(op.id),
              icon: Icon(Icons.close_rounded, color: t.danger, size: 20),
            ),
          ] else if (op.status == OutboxStatus.syncing)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.primary),
            )
          else
            AppBadge(
              op.status.name,
              tone: op.status == OutboxStatus.pending ? BadgeTone.warning : BadgeTone.info,
              dense: true,
            ),
        ],
      ),
    );
  }
}

/// Soft offline banner for screens showing cached / degraded data.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.asOf});

  final DateTime? asOf;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncState>();
    if (sync.online && !sync.justSynced) return const SizedBox.shrink();
    final t = context.t;
    final color = sync.justSynced ? t.success : const Color(0xFF38BDF8);

    return FadeInUp(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(R.lg),
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.16),
              color.withValues(alpha: 0.05),
            ],
          ),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(
              sync.justSynced ? Icons.check_circle_rounded : Icons.sensors_rounded,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                sync.justSynced
                    ? 'Back online — everything just synced'
                    : asOf != null
                        ? 'Offline · showing data from ${relativeTime(asOf!)}'
                        : 'You are offline · edits will sync later',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: t.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
