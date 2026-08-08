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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (store.unread > 0)
            TextButton(
              onPressed: store.markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: store.refresh,
        child: store.loading && store.items.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(20),
                children: const [
                  ShimmerBlock(height: 84),
                  SizedBox(height: 12),
                  ShimmerBlock(height: 84),
                  SizedBox(height: 12),
                  ShimmerBlock(height: 84),
                ],
              )
            : store.items.isEmpty
                ? ListView(
                    children: const [
                      EmptyState(
                        icon: Icons.notifications_none_rounded,
                        title: 'You’re all caught up',
                        message: 'Budget alerts, plan rolls and reminders will land here.',
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    itemCount: store.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _NotificationTile(n: store.items[i]),
                  ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n});

  final AppNotification n;

  (IconData, Color) _meta(String type) => switch (type) {
        'budget_alert' => (Icons.warning_amber_rounded, SantimTheme.warning),
        'budget_closed' => (Icons.flag_outlined, Colors.blueGrey),
        'budget_cycle_rolled' => (Icons.auto_awesome, SantimTheme.income),
        'recurring_due' => (Icons.event_repeat, const Color(0xFF0284C7)),
        'wishlist_bought' || 'wishlist_planned' || 'wishlist_funded' => (Icons.shopping_bag_outlined, Colors.pink),
        'tab_due' || 'tab_overdue' || 'tab_settled' => (Icons.handshake_outlined, Colors.indigo),
        _ => (Icons.notifications_rounded, SantimTheme.seed),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = _meta(n.type);
    final store = context.read<NotificationStore>();

    return SoftCard(
      padding: const EdgeInsets.all(14),
      onTap: () async {
        if (!n.readFlag) await store.markRead(n.id);
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: n.readFlag ? FontWeight.w500 : FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  Dates.relative(n.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!n.readFlag)
            Container(
              width: 9,
              height: 9,
              margin: const EdgeInsets.only(top: 6, left: 8),
              decoration: const BoxDecoration(color: SantimTheme.expense, shape: BoxShape.circle),
            ),
        ],
      ),
    );
  }
}
