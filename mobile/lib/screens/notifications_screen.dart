import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/formatting.dart';
import '../core/theme.dart';
import '../models/notification.dart';
import '../state/notification_store.dart';
import '../widgets/common.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotificationStore>();
    final colors = Theme.of(context).extension<SantimColors>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (store.unread > 0)
            TextButton.icon(
              onPressed: store.markAllRead,
              icon: Icon(Icons.done_all_rounded, size: 16, color: colors.primary),
              label: Text('Mark all read', style: TextStyle(color: colors.primary, fontSize: 13)),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: store.refresh,
        child: store.loading && store.items.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(20),
                children: const [
                  ShimmerBlock(height: 72),
                  SizedBox(height: 10),
                  ShimmerBlock(height: 72),
                  SizedBox(height: 10),
                  ShimmerBlock(height: 72),
                ],
              )
            : store.items.isEmpty
                ? ListView(
                    children: const [
                      EmptyState(
                        icon: Icons.notifications_none_rounded,
                        title: "You're all caught up",
                        message: 'Budget alerts, plan rolls and reminders will land here.',
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      SoftCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var i = 0; i < store.items.length; i++) ...[
                              if (i > 0) Divider(height: 1, color: colors.border),
                              _NotificationTile(n: store.items[i]),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n});

  final AppNotification n;

  (IconData, Color, Color) _meta(String type, SantimColors colors) => switch (type) {
        'wishlist_funded' => (Icons.auto_awesome, const Color(0xFF7C3AED), const Color(0x1F7C3AED)),
        'wishlist_bought' => (Icons.shopping_bag_outlined, const Color(0xFFE11D48), const Color(0x1FE11D48)),
        'budget_alert' => (Icons.warning_amber_rounded, colors.warning, colors.warning.withValues(alpha: 0.12)),
        'budget_closed' => (Icons.flag_outlined, const Color(0xFF64748B), const Color(0x1F64748B)),
        'budget_cycle_rolled' => (Icons.star_rounded, colors.success, colors.success.withValues(alpha: 0.12)),
        'recurring_due' => (Icons.event_repeat_rounded, const Color(0xFF0284C7), const Color(0x1F0284C7)),
        _ => (Icons.notifications_rounded, colors.primary, colors.primary.withValues(alpha: 0.1)),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;
    final (icon, color, bg) = _meta(n.type, colors);
    final store = context.read<NotificationStore>();

    return Material(
      color: n.readFlag ? Colors.transparent : colors.primary.withValues(alpha: 0.05),
      child: InkWell(
        onTap: () async {
          if (!n.readFlag) await store.markRead(n.id);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: n.readFlag ? FontWeight.w500 : FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Dates.relative(n.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (!n.readFlag)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6, left: 8),
                  decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
