import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bridge to the Android home-screen widget.
///
/// The widget never calls the API. Dart writes what it should say into shared
/// preferences after each dashboard load   the same store the native provider
/// reads   then asks it to repaint. That keeps the widget instant and correct
/// offline, at the cost of it being as fresh as the last time the app ran.
abstract final class HomeWidget {
  static const _channel = MethodChannel('santim/widget');

  static const _remainingKey = 'santim.widget.remaining';
  static const _captionKey = 'santim.widget.caption';
  static const _spentKey = 'santim.widget.spent';

  /// Action the widget's add button asks for on launch.
  static const addAction = 'add';

  /// Pushes today's figures to the widget. Safe to call on every dashboard
  /// load; a device with no widget placed does no work beyond the writes.
  static Future<void> publish({
    required String remaining,
    required String caption,
    required String spent,
  }) async {
    if (!_supported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_remainingKey, remaining);
      await prefs.setString(_captionKey, caption);
      await prefs.setString(_spentKey, spent);
      await _channel.invokeMethod<bool>('refresh');
    } catch (e) {
      // A missing widget, a locked device, an OEM that blocks the broadcast
      // none of it should surface to someone just opening the dashboard.
      debugPrint('home widget refresh skipped: $e');
    }
  }

  /// Returns [addAction] when the app was launched from the widget's add
  /// button. Clears itself, so a later call returns null.
  static Future<String?> consumeLaunchAction() async {
    if (!_supported) return null;
    try {
      return await _channel.invokeMethod<String>('consumeLaunchAction');
    } catch (e) {
      debugPrint('home widget launch action unavailable: $e');
      return null;
    }
  }

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
