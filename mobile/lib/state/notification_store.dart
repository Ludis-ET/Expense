import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/notification.dart';
import '../offline/local_db.dart';

class NotificationStore extends ChangeNotifier {
  NotificationStore({required this.api, required this.db});

  final ApiClient api;
  final LocalDb db;

  List<AppNotification> items = const [];
  int unread = 0;
  bool loading = false;
  String? error;
  Timer? _poll;

  Future<void> start() async {
    await hydrateFromCache();
    await refresh();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => refresh(silent: true));
  }

  Future<void> hydrateFromCache() async {
    final cached = await db.get('notifications');
    if (cached?.data is Map<String, dynamic>) {
      final map = cached!.data as Map<String, dynamic>;
      items = ((map['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AppNotification.fromJson)
          .toList();
      unread = (map['unread'] as num?)?.toInt() ?? items.where((n) => !n.readFlag).length;
      notifyListeners();
    }
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      loading = true;
      notifyListeners();
    }
    try {
      final data = await api.get('/notifications') as Map<String, dynamic>;
      items = ((data['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AppNotification.fromJson)
          .toList();
      unread = (data['unread'] as num?)?.toInt() ?? items.where((n) => !n.readFlag).length;
      await db.put('notifications', data);
      error = null;
    } on NetworkException {
      // Keep cache.
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> markRead(String id) async {
    final before = items;
    items = [
      for (final n in items) n.id == id ? n.copyWith(readFlag: true) : n,
    ];
    unread = items.where((n) => !n.readFlag).length;
    notifyListeners();
    try {
      await api.post('/notifications/$id/read');
    } catch (_) {
      items = before;
      unread = items.where((n) => !n.readFlag).length;
      notifyListeners();
    }
  }

  Future<void> markAllRead() async {
    final before = items;
    final beforeUnread = unread;
    items = [for (final n in items) n.copyWith(readFlag: true)];
    unread = 0;
    notifyListeners();
    try {
      await api.post('/notifications/read-all');
    } catch (_) {
      items = before;
      unread = beforeUnread;
      notifyListeners();
    }
  }

  void reset() {
    _poll?.cancel();
    _poll = null;
    items = const [];
    unread = 0;
    error = null;
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
