import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/ingest.dart';

/// Android MethodChannel / EventChannel bridge for SMS inbox + live capture.
class SmsBridge {
  SmsBridge._();
  static final SmsBridge instance = SmsBridge._();

  static const _methods = MethodChannel('santim/sms');
  static const _events = EventChannel('santim/sms_events');

  StreamSubscription? _sub;
  final _controller = StreamController<CapturedSms>.broadcast();

  Stream<CapturedSms> get incoming => _controller.stream;

  bool get isAndroidNative => !kIsWeb && Platform.isAndroid;

  Future<bool> requestPermissions() async {
    if (!isAndroidNative) return false;
    final statuses = await [
      Permission.sms,
    ].request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<bool> hasPermissions() async {
    if (!isAndroidNative) return false;
    return Permission.sms.isGranted;
  }

  Future<void> startListening() async {
    if (!isAndroidNative) return;
    await _sub?.cancel();
    _sub = _events.receiveBroadcastStream().listen((event) {
      if (event is! Map) return;
      final map = Map<String, dynamic>.from(event);
      final sender = map['sender']?.toString();
      final body = map['body']?.toString();
      final ms = map['receivedAtMs'];
      if (sender == null || body == null) return;
      final receivedAt = ms is num
          ? DateTime.fromMillisecondsSinceEpoch(ms.toInt())
          : DateTime.now();
      _controller.add(CapturedSms(sender: sender, body: body, receivedAt: receivedAt));
    }, onError: (e) {
      debugPrint('SMS event error: $e');
    });
  }

  Future<void> stopListening() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Messages the manifest receiver captured while no Flutter engine existed.
  ///
  /// The native side queues them durably and clears the queue as it hands them
  /// over, so this is safe to call on every launch and every resume - it
  /// returns an empty list when there is nothing waiting. Call it *before*
  /// falling back to an inbox backfill: these carry the carrier's own
  /// timestamp and survive the user deleting the message.
  Future<List<CapturedSms>> drainPending() async {
    if (!isAndroidNative) return const [];
    try {
      final raw = await _methods.invokeMethod<List<dynamic>>('drainPendingSms');
      return (raw ?? const [])
          .whereType<Map>()
          .map((e) {
            final m = Map<String, dynamic>.from(e);
            return CapturedSms(
              sender: m['sender']?.toString() ?? '',
              body: m['body']?.toString() ?? '',
              receivedAt: DateTime.fromMillisecondsSinceEpoch(
                (m['receivedAtMs'] as num?)?.toInt() ??
                    DateTime.now().millisecondsSinceEpoch,
              ),
            );
          })
          .where((m) => m.sender.isNotEmpty && m.body.isNotEmpty)
          .toList();
    } on PlatformException catch (e) {
      // An older APK without the native half. Backfill still covers it.
      debugPrint('drainPendingSms unavailable: ${e.message}');
      return const [];
    }
  }

  Future<List<CapturedSms>> getInbox({DateTime? min, DateTime? max}) async {
    if (!isAndroidNative) return const [];
    final raw = await _methods.invokeMethod<List<dynamic>>('getInbox', {
      'minMs': (min ?? DateTime.fromMillisecondsSinceEpoch(0)).millisecondsSinceEpoch,
      'maxMs': (max ?? DateTime.now()).millisecondsSinceEpoch,
    });
    return (raw ?? const [])
        .whereType<Map>()
        .map((e) {
          final m = Map<String, dynamic>.from(e);
          return CapturedSms(
            sender: m['sender']?.toString() ?? '',
            body: m['body']?.toString() ?? '',
            receivedAt: DateTime.fromMillisecondsSinceEpoch(
              (m['receivedAtMs'] as num?)?.toInt() ?? 0,
            ),
          );
        })
        .where((m) => m.sender.isNotEmpty && m.body.isNotEmpty)
        .toList();
  }

  Future<int> countInbox({DateTime? min, DateTime? max}) async {
    if (!isAndroidNative) return 0;
    final n = await _methods.invokeMethod<int>('countInbox', {
      'minMs': (min ?? DateTime.fromMillisecondsSinceEpoch(0)).millisecondsSinceEpoch,
      'maxMs': (max ?? DateTime.now()).millisecondsSinceEpoch,
    });
    return n ?? 0;
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!isAndroidNative) return true;
    final v = await _methods.invokeMethod<bool>('isIgnoringBatteryOptimizations');
    return v ?? true;
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!isAndroidNative) return;
    await _methods.invokeMethod('requestIgnoreBatteryOptimizations');
  }

  void dispose() {
    unawaited(stopListening());
    unawaited(_controller.close());
  }
}
