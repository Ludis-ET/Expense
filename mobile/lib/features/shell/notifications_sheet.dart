import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../models/models.dart';
import '../../state/data_state.dart';
import '../../widgets/ui.dart';
import 'app_shell.dart';
import 'notification_links.dart';

/// `NotificationsMenu` as a bottom sheet — budget alerts, tab reminders and
/// recurring postings, newest first.
///
/// Navigation runs *after* the sheet closes, using the [AppShell] that opened
/// it. The sheet itself is not under [AppShell] in the tree, so tapping cannot
/// call `AppShell.of(sheetContext)`.
Future<void> showNotificationsSheet(BuildContext context) async {
  final data = context.read<DataState>();
  final shell = AppShell.of(context);
  data.loadNotifications(force: true);

  final selected = await showAppSheet<AppNotification>(
    context,
    title: 'Notifications',
    builder: (ctx) => const _NotificationsList(),
  );

  if (selected == null || !shell.mounted) return;
  // Let the sheet finish dismissing before pushing a tab route.
  await Future<void>.delayed(const Duration(milliseconds: 50));
  if (!shell.mounted) return;
  await openNotificationDestination(shell, selected);
}

class _NotificationsList extends StatelessWidget {
  const _NotificationsList();

  void _open(BuildContext context, AppNotification n) {
    final data = context.read<DataState>();
    if (!n.readFlag) {
      data.markNotificationRead(n.id);
    }
    // Return the notification to [showNotificationsSheet], which navigates
    // with a live AppShell after this route is gone.
    Navigator.of(context).pop(n);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final data = context.watch<DataState>();
    final items = data.notifications.data ?? const <AppNotification>[];
    final bottom = MediaQuery.of(context).padding.bottom;

    if (data.notifications.loading && items.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + bottom),
        child: Column(
          children: [
            for (var i = 0; i < 4; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: S.md),
                child: Skeleton(height: 62, radius: R.md),
              ),
          ],
        ),
      );
    }

    if (items.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 28 + bottom),
        child: const EmptyState(
          icon: Icons.notifications_none_rounded,
          title: 'You are all caught up',
          description: 'Budget alerts and tab reminders will land here.',
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (data.unreadCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Muted('${data.unreadCount} unread'),
                const Spacer(),
                AppButton(
                  label: 'Mark all read',
                  size: BtnSize.sm,
                  variant: BtnVariant.ghost,
                  icon: Icons.done_all,
                  onPressed: data.markAllNotificationsRead,
                ),
              ],
            ),
          ),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(12, 0, 12, 24 + bottom),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Gap(S.sm),
            itemBuilder: (context, i) {
              final n = items[i];
              return FadeInUp.staggered(
                index: i.clamp(0, 8),
                offset: 6,
                child: AppCard(
                  padding: const EdgeInsets.all(S.md),
                  color: n.readFlag
                      ? t.surface
                      : t.primary.withValues(alpha: 0.06),
                  borderColor: n.readFlag
                      ? t.border
                      : t.primary.withValues(alpha: 0.25),
                  onTap: () => _open(context, n),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconTile(
                        icon: _iconFor(n.type),
                        color: _toneFor(context, n.type),
                        size: 34,
                      ),
                      const GapX(S.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              n.message,
                              style: TextStyle(
                                fontSize: AppType.bodySm,
                                height: 1.4,
                                fontWeight: n.readFlag
                                    ? FontWeight.w400
                                    : FontWeight.w600,
                                color: t.foreground,
                              ),
                            ),
                            const Gap(S.xxs),
                            Row(
                              children: [
                                Muted(relativeTime(n.createdAt), size: 11),
                                const GapX(S.sm),
                                Text(
                                  _destinationLabel(n),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: t.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (!n.readFlag)
                        Container(
                          margin: const EdgeInsets.only(top: S.xs, left: S.xs),
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: t.primary,
                            shape: BoxShape.circle,
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.only(left: S.xs, top: 2),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: t.mutedForeground,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static String _destinationLabel(AppNotification n) {
    final link = (n.link ?? '').toLowerCase();
    final type = n.type.toLowerCase();
    if (link.contains('wishlist') || type.contains('wish')) {
      return 'Open wishlist';
    }
    if (link.contains('/budgets/') ||
        (type.contains('budget') && link.contains('budgets'))) {
      return 'Open plan';
    }
    if (type.contains('budget')) return 'Open plans';
    if (link.contains('recurring') || type.contains('recurring')) {
      return 'Open recurring';
    }
    if (link.contains('/tab') ||
        type.contains('tab') ||
        type.contains('ledger')) {
      return 'Open Money Tab';
    }
    return 'Open';
  }

  static IconData _iconFor(String type) {
    final t = type.toLowerCase();
    if (t.contains('budget')) return Icons.savings_outlined;
    if (t.contains('recurring')) return Icons.repeat;
    if (t.contains('ledger') || t.contains('tab')) {
      return Icons.volunteer_activism_outlined;
    }
    if (t.contains('household')) return Icons.group_outlined;
    if (t.contains('wish')) return Icons.favorite_border;
    return Icons.notifications_none_rounded;
  }

  static Color _toneFor(BuildContext context, String type) {
    final t = context.t;
    final k = type.toLowerCase();
    if (k.contains('overdue') || k.contains('drained')) return t.danger;
    if (k.contains('low') || k.contains('due')) return t.warning;
    return t.primary;
  }
}
