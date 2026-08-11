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
  static const shared = Cubic(0.4, 0.0, 0.2, 1);
  static const enter = Duration(milliseconds: 260);
  static const fast = Duration(milliseconds: 160);
  static const stagger = Duration(milliseconds: 32);
}

/// The app's type scale. Every size in the UI comes from here — before this
/// existed there were 32 distinct hard-coded sizes (9.5, 10.5, 11.5, 12.5,
/// 13.5, 14.5, 16.5 …), which is why the same list-row title was 13 in one
/// card and 13.5 in the next.
///
/// Steps are deliberately few and never fractional. `snap` maps a legacy
/// numeric size onto the nearest step so older call sites land on the grid
/// even before they are rewritten to use the named roles.
abstract final class AppType {
  /// Badge and chip text — the smallest type the app is allowed to render.
  static const micro = 10.0;

  /// Captions, timestamps, secondary metadata under a value.
  static const caption = 11.0;

  /// Field labels, eyebrow rows, dense table headers.
  static const label = 12.0;

  /// Secondary body copy and list-row subtitles.
  static const bodySm = 13.0;

  /// Default body copy and list-row titles.
  static const body = 14.0;

  /// Card titles and the lead line of a section.
  static const lead = 16.0;

  /// Screen headings and mid-size figures.
  static const heading = 20.0;

  /// Primary figures — a balance inside a card.
  static const figure = 24.0;

  /// Large figures — the amount field, a month total.
  static const display = 32.0;

  /// The dashboard hero balance, and nothing else.
  static const hero = 36.0;

  static const _steps = [
    micro, caption, label, bodySm, body, lead, heading, figure, display, hero,
  ];

  /// Rounds an arbitrary size onto the scale, biasing downward on ties so a
  /// snapped value never overflows a layout that fit the original.
  static double snap(double size) {
    var best = _steps.first;
    var bestGap = (size - best).abs();
    for (final step in _steps.skip(1)) {
      final gap = (size - step).abs();
      if (gap < bestGap || (gap == bestGap && step < best)) {
        best = step;
        bestGap = gap;
      }
    }
    return best;
  }
}

/// Weights, named so call sites stop reaching for raw `FontWeight.wN`.
abstract final class W {
  static const regular = FontWeight.w400;
  static const medium = FontWeight.w500;
  static const semibold = FontWeight.w600;
  static const bold = FontWeight.w700;
  static const heavy = FontWeight.w800;
}

/// The 4pt spacing grid. Before this, 798 `SizedBox` spacers used 19 distinct
/// values (1, 2, 3, 5, 7, 9, 11, 13, 15, 18, 22, 26 …) with no rhythm.
abstract final class S {
  /// Hairline separation — a label sitting directly on its value.
  static const hair = 2.0;
  static const xxs = 4.0;
  static const xs = 6.0;
  static const sm = 8.0;
  static const md = 12.0;

  /// The standard gap between cards and between sections inside a card.
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const huge = 32.0;
}

/// Vertical spacer for Columns — `Gap(S.lg)` instead of `SizedBox(height: 16)`.
/// Sets only the main-axis extent, so it never widens its parent.
class Gap extends StatelessWidget {
  const Gap(this.size, {super.key});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(height: size);
}

/// Horizontal spacer for Rows.
class GapX extends StatelessWidget {
  const GapX(this.size, {super.key});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(width: size);
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
      fontFamily: 'Geist',
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
      contentTextStyle: TextStyle(color: t.foreground, fontSize: AppType.bodySm),
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
