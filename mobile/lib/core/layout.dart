import 'package:flutter/widgets.dart';

/// Geometry of the floating bottom chrome in [AppShell]
/// (`fabOverlap` 28 + nav 58 + Ask bar 34 + pad 8).
abstract final class ShellLayout {
  static const double chromeHeight = 128;

  /// Scroll/list bottom padding so content clears the bottom nav + system inset.
  static double bottomClearance(BuildContext context, {double extra = 16}) =>
      chromeHeight + MediaQuery.paddingOf(context).bottom + extra;

  /// For full-screen routes above the shell (root navigator) — system inset only.
  static double pageClearance(BuildContext context, {double extra = 24}) =>
      MediaQuery.paddingOf(context).bottom + extra;
}
