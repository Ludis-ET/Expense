import 'package:flutter/services.dart';

/// What the native capture layer is currently doing.
class IngestStatus {
  const IngestStatus({
    required this.configured,
    required this.captureEnabled,
    required this.queued,
    required this.senderCount,
    required this.batteryUnrestricted,
    this.installedAt,
    this.lastImportedAt,
  });

  const IngestStatus.unknown()
      : configured = false,
        captureEnabled = false,
        queued = 0,
        senderCount = 0,
        batteryUnrestricted = false,
        installedAt = null,
        lastImportedAt = null;

  /// A device token and API URL have been handed to the native side.
  final bool configured;
  final bool captureEnabled;

  /// Messages captured but not yet acknowledged by the server.
  final int queued;
  final int senderCount;

  /// False means an OEM battery manager may kill the upload worker.
  final bool batteryUnrestricted;

  /// When capture was first switched on. Everything after this arrives live;
  /// anything before it only exists if the user imported a date range.
  final DateTime? installedAt;

  /// Newest message pulled in by an explicit import.
  final DateTime? lastImportedAt;

  bool get healthy => configured && captureEnabled && senderCount > 0;

  static DateTime? _millis(Object? value) {
    final ms = value is int ? value : null;
    return ms == null || ms <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  factory IngestStatus.fromMap(Map<Object?, Object?> map) => IngestStatus(
        configured: map['configured'] as bool? ?? false,
        captureEnabled: map['captureEnabled'] as bool? ?? false,
        queued: map['queued'] as int? ?? 0,
        senderCount: map['senderCount'] as int? ?? 0,
        batteryUnrestricted: map['batteryUnrestricted'] as bool? ?? false,
        installedAt: _millis(map['installedAt']),
        lastImportedAt: _millis(map['lastImportedAt']),
      );
}

/// A sender found in the phone's own SMS inbox.
class InboxSender {
  const InboxSender({
    required this.sender,
    required this.messageCount,
    required this.lastMessageAt,
    required this.samples,
  });

  final String sender;
  final int messageCount;
  final DateTime? lastMessageAt;

  /// A couple of real message bodies, so the user can tell which bank this is.
  final List<String> samples;

  factory InboxSender.fromMap(Map<Object?, Object?> map) {
    final millis = map['lastMessageAt'] as int? ?? 0;
    return InboxSender(
      sender: map['sender'] as String? ?? '',
      messageCount: map['messageCount'] as int? ?? 0,
      lastMessageAt: millis > 0 ? DateTime.fromMillisecondsSinceEpoch(millis) : null,
      samples: ((map['samples'] as List?) ?? const []).map((e) => '$e').toList(),
    );
  }
}

/// Dart's handle on the Kotlin capture layer.
///
/// Nothing here is on the delivery path - the receiver and upload worker run
/// with no Flutter engine attached. This only configures them and reads back
/// state for the UI.
class NativeIngest {
  static const _channel = MethodChannel('com.santim.mobile/ingest');

  /// Hands the native side its credential and the sender allowlist it enforces.
  static Future<void> configure({
    String? deviceToken,
    String? baseUrl,
    bool? captureEnabled,
    List<String>? senders,
  }) async {
    // Null entries are dropped rather than sent: each caller updates only the
    // fields it owns, and the native side keeps whatever it already had.
    await _channel.invokeMethod<bool>('configure', {
      'deviceToken': ?deviceToken,
      'baseUrl': ?baseUrl,
      'captureEnabled': ?captureEnabled,
      'senders': ?senders,
    });
  }

  static Future<IngestStatus> status() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>('getStatus');
    return result == null ? const IngestStatus.unknown() : IngestStatus.fromMap(result);
  }

  static Future<bool> setCaptureEnabled(bool enabled) async =>
      await _channel.invokeMethod<bool>('setCaptureEnabled', {'enabled': enabled}) ?? false;

  /// Requires READ_SMS. Used to build the sender pick-list during setup.
  static Future<List<InboxSender>> listInboxSenders() async {
    final result = await _channel.invokeMethod<List<Object?>>('listInboxSenders');
    return (result ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(InboxSender.fromMap)
        .toList();
  }

  /// Queues historical messages from the approved senders in a date range.
  ///
  /// Safe to re-run over a range already imported: the outbox de-duplicates
  /// locally and the server fingerprints every message, so nothing lands twice.
  static Future<int> backfill({required DateTime from, DateTime? to}) async =>
      await _channel.invokeMethod<int>('backfill', {
        'fromMillis': from.millisecondsSinceEpoch,
        'toMillis': (to ?? DateTime.now()).millisecondsSinceEpoch,
      }) ??
      0;

  /// How many messages a range holds, so the user sees the size before importing.
  static Future<int> countInRange({required DateTime from, DateTime? to}) async =>
      await _channel.invokeMethod<int>('countInRange', {
        'fromMillis': from.millisecondsSinceEpoch,
        'toMillis': (to ?? DateTime.now()).millisecondsSinceEpoch,
      }) ??
      0;

  static Future<void> syncNow() => _channel.invokeMethod<bool>('syncNow');

  /// Returns true if already exempt; otherwise opens the system dialog.
  static Future<bool> requestBatteryExemption() async =>
      await _channel.invokeMethod<bool>('requestBatteryExemption') ?? false;

  /// Unpair: forget the token and drop anything still queued.
  static Future<void> clear() => _channel.invokeMethod<bool>('clear');
}
