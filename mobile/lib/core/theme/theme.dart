import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Radii from `--radius-card: 1rem` and the Tailwind steps the web app uses.
abstract final class R {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 14.0;
  static const card = 16.0;
  static const xl = 20.0;
  static const pill = 999.0;
}

/// Motion curves from `globals.css` — `cubic-bezier(0.22, 1, 0.36, 1)` is the
/// one every entrance animation in the web app rides on.
abstract final class Motion {
  static const easeOut = Cubic(0.22, 1, 0.36, 1);
  static const spring = Cubic(0.34, 1.56, 0.64, 1);
  static const enter = Duration(milliseconds: 260);
  static const fast = Duration(milliseconds: 160);
  static const stagger = Duration(milliseconds: 32);
}

ThemeData buildTheme(SantimTokens t) {
  final base = t.isDark ? ThemeData.dark() : ThemeData.light();
  final scheme = ColorScheme.fromSeed(
    seedColor: t.primary,
    brightness: t.isDark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: t.primary,
    onPrimary: t.primaryForeground,
    secondary: t.accent,
    surface: t.surface,
    onSurface: t.foreground,
    error: t.danger,
    outline: t.border,
  );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: t.background,
    canvasColor: t.surface,
    dividerColor: t.border,
    splashFactory: InkRipple.splashFactory,
    extensions: [t],
    textTheme: base.textTheme.apply(
      bodyColor: t.foreground,
      displayColor: t.foreground,
      fontFamily: 'Roboto',
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: t.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: t.foreground,
      iconTheme: IconThemeData(color: t.foreground, size: 22),
      systemOverlayStyle: t.isDark
          ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
          : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
    ),
    iconTheme: IconThemeData(color: t.mutedForeground, size: 20),
    dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.surfaceElevated,
      contentTextStyle: TextStyle(color: t.foreground, fontSize: 13.5),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.primary,
      linearTrackColor: t.surfaceMuted,
      circularTrackColor: t.surfaceMuted,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: _FadeThroughTransitionBuilder()},
    ),
  );
}

/// Softer than Android's default zoom transition and closer to the web app's
/// `fade-in-up` page entrance.
class _FadeThroughTransitionBuilder extends PageTransitionsBuilder {
  const _FadeThroughTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Motion.easeOut);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0.03, 0), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}
