import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../models/models.dart';
import '../budgets/budget_detail_screen.dart';
import '../ledger/tab_screen.dart';
import '../recurring/recurring_screen.dart';
import '../shell/app_shell.dart';
import '../wishlist/wishlist_screen.dart';

/// Opens the screen a notification points at (web-style paths from the API).
///
/// Known links from the backend:
/// - `/budgets/{id}`
/// - `/budgets?tab=wishlist`
/// - `/recurring`
/// - `/tab` / `/tab?e={entryId}`
Future<void> openNotificationDestination(
  BuildContext context,
  AppNotification n,
) async {
  Haptics.select();
  final shell = AppShell.of(context);
  final target = _resolve(n);

  // Close the notifications sheet first so the pushed route is visible.
  Navigator.of(context).maybePop();
  await Future<void>.delayed(const Duration(milliseconds: 160));
  if (!context.mounted) return;

  switch (target) {
    case _BudgetDetail(:final id):
      shell.goTo(ShellTab.plan);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      if (!context.mounted) return;
      await shell.push(BudgetDetailScreen(budgetId: id));
    case _Wishlist():
      await shell.push(const WishlistScreen());
    case _Plans():
      shell.goTo(ShellTab.plan);
    case _Recurring():
      await shell.push(const RecurringScreen());
    case _Tab(:final entryId):
      await shell.push(TabScreen(focusEntryId: entryId));
    case _Home():
      shell.goTo(ShellTab.home);
  }
}

sealed class _Dest {}

class _BudgetDetail extends _Dest {
  _BudgetDetail(this.id);
  final String id;
}

class _Wishlist extends _Dest {}

class _Plans extends _Dest {}

class _Recurring extends _Dest {}

class _Tab extends _Dest {
  _Tab({this.entryId});
  final String? entryId;
}

class _Home extends _Dest {}

_Dest _resolve(AppNotification n) {
  final fromLink = _fromLink(n.link);
  if (fromLink != null) return fromLink;
  return _fromType(n.type);
}

_Dest? _fromLink(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return null;

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return null;

  final root = segments.first.toLowerCase();
  switch (root) {
    case 'budgets':
      if (segments.length >= 2 && segments[1].isNotEmpty) {
        return _BudgetDetail(segments[1]);
      }
      final tab = uri.queryParameters['tab']?.toLowerCase();
      if (tab == 'wishlist' || tab == 'wishes') return _Wishlist();
      return _Plans();
    case 'wishlist':
    case 'wishes':
      return _Wishlist();
    case 'recurring':
      return _Recurring();
    case 'tab':
    case 'ledger':
      return _Tab(entryId: uri.queryParameters['e'] ?? uri.queryParameters['entry']);
    case 'plan':
    case 'plans':
      return _Plans();
    default:
      return null;
  }
}

_Dest _fromType(String type) {
  final t = type.toLowerCase();
  if (t.contains('wish')) return _Wishlist();
  if (t.contains('budget')) return _Plans();
  if (t.contains('recurring')) return _Recurring();
  if (t.contains('tab') || t.contains('ledger')) return _Tab();
  return _Home();
}
