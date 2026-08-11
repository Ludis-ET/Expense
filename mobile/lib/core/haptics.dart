import 'package:flutter/services.dart';

/// Haptic feedback, expressed as intent rather than as a waveform.
///
/// Before this existed, `HapticFeedback.*` was called directly in 13 of the
/// app's ~50 screens: tab changes and opening the add sheet buzzed, while
/// toggling a switch, committing a budget or failing a form did not. Feedback
/// that fires only sometimes reads as a bug rather than as restraint.
///
/// The policy, applied everywhere:
///
/// * [select]   moving between equivalent options: a tab, a page in a
///   carousel, a segmented control, a picker row.
/// * [toggle]   flipping a switch, opening or closing a section.
/// * [commit]   an action that changed stored data: a transaction saved, a
///   budget funded, a wish bought.
/// * [reject]   the action did not go through: validation failed, the balance
///   guard refused, the PIN was wrong.
abstract final class Haptics {
  /// Moving between equivalent choices.
  static void select() => HapticFeedback.selectionClick();

  /// Flipping something on or off.
  static void toggle() => HapticFeedback.lightImpact();

  /// Data was written.
  static void commit() => HapticFeedback.mediumImpact();

  /// Something was refused. A double tick reads as "no" in a way a single
  /// impact does not.
  static Future<void> reject() async {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.heavyImpact();
  }
}
