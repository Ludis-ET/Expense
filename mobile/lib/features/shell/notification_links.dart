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
///
/// Call this with a live [AppShellState] (not a bottom-sheet context). Sheets
/// sit on the root navigator and are not descendants of [AppShell], and their
/// context is unmounted as soon as they close.
Future<void> openNotificationDestination(
  AppShellState shell,
  AppNotification n,
) async {
  Haptics.select();
  if (!shell.mounted) return;

  final target = _resolve(n);
  switch (target) {
    case _BudgetDetail(:final id):
      shell.goTo(ShellTab.plan);
      await _afterTabSettle(shell);
      if (!shell.mounted) return;
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

Future<void> _afterTabSettle(AppShellState shell) async {
  await Future<void>.delayed(const Duration(milliseconds: 50));
  if (!shell.mounted) return;
  await WidgetsBinding.instance.endOfFrame;
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
  var text = raw.trim();
  // Tolerate absolute URLs accidentally stored as links.
  if (text.startsWith('http://') || text.startsWith('https://')) {
    final abs = Uri.tryParse(text);
    if (abs != null) {
      text = abs.hasQuery ? '${abs.path}?${abs.query}' : abs.path;
    }
  }
  if (!text.startsWith('/')) text = '/$text';

  final uri = Uri.tryParse(text);
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
      return _Tab(
        entryId: uri.queryParameters['e'] ?? uri.queryParameters['entry'],
      );
    case 'plan':
    case 'plans':
      return _Plans();
    case 'dashboard':
    case 'home':
      return _Home();
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
