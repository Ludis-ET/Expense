import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Posts OS tray notifications for server alerts and SMS review.
///
/// Push (FCM) is not used — the phone already has the API session when the
/// app is open/resumed, and bank SMS is captured natively while closed. This
/// layer turns those events into real system notifications.
class LocalNotifications {
  LocalNotifications._();
  static final LocalNotifications instance = LocalNotifications._();

  static const _askedKey = 'santim.notif.asked';
  static const _watermarkKey = 'santim.notif.lastMs';
  static const alertsChannelId = 'santim_alerts';
  static const smsChannelId = 'santim_sms';

  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<Uri>.broadcast();

  bool _ready = false;
  Uri? _launchPayload;

  Stream<Uri> get taps => _taps.stream;

  Future<void> init() async {
    if (_ready || kIsWeb || !Platform.isAndroid) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: (response) {
        final uri = _parsePayload(response.payload);
        if (uri != null) _taps.add(uri);
      },
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      _launchPayload = _parsePayload(launch!.notificationResponse?.payload);
    }

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        alertsChannelId,
        'Santim alerts',
        description: 'Budget, recurring, and tab reminders',
        importance: Importance.high,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        smsChannelId,
        'Bank messages',
        description: 'When a bank SMS needs review in Santim',
        importance: Importance.high,
      ),
    );

    _ready = true;
  }

  /// Returns a cold-start tap payload once, then clears it.
  Uri? consumeLaunchPayload() {
    final uri = _launchPayload;
    _launchPayload = null;
    return uri;
  }

  Future<bool> ensurePermission(SharedPreferences prefs) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    await init();

    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final already = await android?.areNotificationsEnabled() ?? true;
    if (already) {
      await prefs.setBool(_askedKey, true);
      return true;
    }

    if (prefs.getBool(_askedKey) == true) return false;
    await prefs.setBool(_askedKey, true);
    return await android?.requestNotificationsPermission() ?? false;
  }

  /// Posts tray alerts for unread API notifications newer than the watermark.
  ///
  /// The first successful sync only seeds the watermark so an upgrade does not
  /// flood the tray with historical unread items.
  Future<void> syncServerNotifications(List<AppNotification> items) async {
    if (!_ready || kIsWeb || !Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_watermarkKey) ?? 0;

    if (lastMs == 0) {
      var newest = DateTime.now().millisecondsSinceEpoch;
      for (final n in items) {
        final ms = n.createdAt.millisecondsSinceEpoch;
        if (ms > newest) newest = ms;
      }
      await prefs.setInt(_watermarkKey, newest);
      return;
    }

    final fresh = items
        .where(
          (n) =>
              !n.readFlag && n.createdAt.millisecondsSinceEpoch > lastMs,
        )
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    if (fresh.isEmpty) return;

    var maxMs = lastMs;
    for (final n in fresh) {
      await _showServer(n);
      final ms = n.createdAt.millisecondsSinceEpoch;
      if (ms > maxMs) maxMs = ms;
    }
    await prefs.setInt(_watermarkKey, maxMs);
  }

  Future<void> cancelServer(String id) async {
    if (!_ready) return;
    await _plugin.cancel(id: _stableId('server:$id'));
  }

  Future<void> _showServer(AppNotification n) async {
    final payload = Uri(
      scheme: 'santim',
      host: 'notification',
      queryParameters: {
        'id': n.id,
        if (n.link != null && n.link!.isNotEmpty) 'link': n.link!,
        if (n.type.isNotEmpty) 'type': n.type,
      },
    ).toString();

    await _plugin.show(
      id: _stableId('server:${n.id}'),
      title: _titleFor(n),
      body: n.message,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          alertsChannelId,
          'Santim alerts',
          channelDescription: 'Budget, recurring, and tab reminders',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(n.message),
          category: AndroidNotificationCategory.reminder,
        ),
      ),
      payload: payload,
    );
  }

  static String _titleFor(AppNotification n) {
    final t = n.type.toLowerCase();
    if (t.contains('wish')) return 'Wishlist';
    if (t.contains('budget')) return 'Budget alert';
    if (t.contains('recurring')) return 'Recurring';
    if (t.contains('tab') || t.contains('ledger')) return 'Tab reminder';
    return 'Santim';
  }

  static int _stableId(String key) => key.hashCode & 0x7fffffff;

  static Uri? _parsePayload(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return Uri.tryParse(raw);
  }
}
