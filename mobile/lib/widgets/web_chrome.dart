import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/finance.dart';
import '../state/auth_store.dart';
import '../state/data_store.dart';
import '../state/notification_store.dart';
import '../screens/notifications_screen.dart';
import '../screens/settings_screen.dart';

Color? parseHexColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  return Color(int.tryParse(h, radix: 16) ?? 0xFF64748B);
}

/// Website-style bottom sheet (matches `Modal` mobile layout).
Future<T?> showSantimSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  double? maxHeightFactor,
}) {
  final theme = Theme.of(context);
  final colors = theme.extension<SantimColors>()!;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) {
      final h = MediaQuery.sizeOf(ctx).height;
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            constraints: BoxConstraints(maxHeight: h * (maxHeightFactor ?? 0.92)),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: colors.border)),
              boxShadow: SantimTheme.cardShadow(theme.brightness),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: Icon(Icons.close_rounded, color: colors.muted),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colors.border),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottom),
                    child: builder(ctx),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.name, this.size = 32, this.radius});

  final String? name;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final n = (name ?? '?').trim();
    final parts = n.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
            ? parts.first.characters.take(2).toString().toUpperCase()
            : '${parts.first.characters.first}${parts.last.characters.first}'.toUpperCase();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius ?? size / 2),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF059669), Color(0xFF0D9488)],
        ),
        boxShadow: [
          BoxShadow(
            color: SantimTheme.primaryLight.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.34,
          height: 1,
        ),
      ),
    );
  }
}

class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = context.select<NotificationStore, int>((s) => s.unread);
    final colors = Theme.of(context).extension<SantimColors>()!;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(santimRoute(const NotificationsScreen())),
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.notifications_none_rounded, size: 18, color: colors.muted),
              if (unread > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: colors.danger,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      unread > 9 ? '9+' : '$unread',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
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

class ProfileMenuButton extends StatelessWidget {
  const ProfileMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.select<AuthStore, AppUser?>((s) => s.user);
    final colors = Theme.of(context).extension<SantimColors>()!;

    return PopupMenuButton<String>(
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.border),
      ),
      onSelected: (value) async {
        switch (value) {
          case 'settings':
            await Navigator.of(context).push(santimRoute(const SettingsScreen()));
          case 'logout':
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Sign out?'),
                content: const Text(
                  'This phone will stop capturing bank messages until you sign in and pair again.',
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(96, 40)),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            );
            if (ok == true && context.mounted) {
              context.read<DataStore>().reset();
              await context.read<AuthStore>().logout();
            }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user?.name ?? 'Account',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                user?.email ?? '',
                style: TextStyle(fontSize: 12, color: colors.muted),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'settings',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.settings_outlined, size: 18),
            title: Text('Settings'),
          ),
        ),
        PopupMenuItem(
          value: 'logout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout_rounded, size: 18, color: colors.danger),
            title: Text('Sign out', style: TextStyle(color: colors.danger)),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 2),
        child: UserAvatar(name: user?.name ?? user?.email, size: 32),
      ),
    );
  }
}

class WebTopActions extends StatelessWidget {
  const WebTopActions({super.key, this.extra});

  final List<Widget>? extra;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...?extra,
        const NotificationBellButton(),
        const SizedBox(width: 8),
        const ProfileMenuButton(),
        const SizedBox(width: 8),
      ],
    );
  }
}

class MonthNavigator extends StatelessWidget {
  const MonthNavigator({super.key, required this.month, required this.onChanged});

  /// `yyyy-MM`
  final String month;
  final ValueChanged<String> onChanged;

  static String currentMonth() {
    final n = DateTime.now();
    return '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}';
  }

  static String shift(String month, int delta) {
    final parts = month.split('-').map(int.parse).toList();
    final d = DateTime(parts[0], parts[1] + delta, 1);
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';
  }

  static (String from, String to) bounds(String month) {
    final parts = month.split('-').map(int.parse).toList();
    final start = DateTime.utc(parts[0], parts[1], 1);
    final end = DateTime.utc(parts[0], parts[1] + 1, 0);
    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return (iso(start), iso(end));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SantimColors>()!;
    final label = DateFormat('MMMM yyyy').format(DateTime.parse('$month-01'));
    final isCurrent = month.compareTo(currentMonth()) >= 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(shift(month, -1)),
          icon: Icon(Icons.chevron_left_rounded, color: colors.muted),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 120),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: isCurrent ? null : () => onChanged(shift(month, 1)),
          icon: Icon(Icons.chevron_right_rounded, color: isCurrent ? colors.border : colors.muted),
        ),
      ],
    );
  }
}

class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: index == i ? colors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: index == i ? theme.colorScheme.onPrimary : colors.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DetailRowTile extends StatelessWidget {
  const DetailRowTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.valueWidget,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? valueWidget;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;

    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: colors.muted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: colors.muted, height: 1)),
                const SizedBox(height: 4),
                valueWidget ??
                    Text(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: valueColor,
                        height: 1.3,
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Website-styled select (rounded border, soft shadow look).
class SantimSelect<T> extends StatelessWidget {
  const SantimSelect({
    super.key,
    required this.label,
    required this.items,
    required this.onChanged,
    this.value,
    this.hint,
  });

  final String label;
  final T? value;
  final String? hint;
  final List<MapEntry<T, String>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SantimColors>()!;
    final valid = items.any((e) => e.key == value);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: valid ? value : null,
          isExpanded: true,
          hint: Text(hint ?? 'Select', style: TextStyle(color: colors.muted, fontSize: 14)),
          borderRadius: BorderRadius.circular(12),
          items: [
            for (final e in items)
              DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

