import 'package:flutter/material.dart';

/// Design tokens lifted verbatim from the web app's `globals.css`, so the
/// Android client renders the same palette in both light and dark mode.
@immutable
class SantimTokens extends ThemeExtension<SantimTokens> {
  const SantimTokens({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceElevated,
    required this.foreground,
    required this.mutedForeground,
    required this.border,
    required this.primary,
    required this.primaryForeground,
    required this.accent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.ring,
    required this.glow,
    required this.save,
    required this.saveLift,
    required this.isDark,
  });

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceElevated;
  final Color foreground;
  final Color mutedForeground;
  final Color border;
  final Color primary;
  final Color primaryForeground;
  final Color accent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color ring;
  final Color glow;

  /// Saving plans get their own identity, so the two plan types are told apart
  /// by colour before a single word is read. Cool against the app's emerald,
  /// which stays the language of spending.
  final Color save;

  /// The lit edge of a saving surface - the top of a gradient, the highlight on
  /// a rising fill.
  final Color saveLift;

  final bool isDark;

  /// `--shadow-card`
  List<BoxShadow> get cardShadow => isDark
      ? const [
          BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x26000000), blurRadius: 16, offset: Offset(0, 4)),
        ]
      : const [
          BoxShadow(color: Color(0x0A0C1222), blurRadius: 3, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x0F0C1222), blurRadius: 16, offset: Offset(0, 4)),
        ];

  /// `--shadow-elevated`
  List<BoxShadow> get elevatedShadow => isDark
      ? const [
          BoxShadow(color: Color(0x4D000000), blurRadius: 24, offset: Offset(0, 4)),
          BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1)),
        ]
      : const [
          BoxShadow(color: Color(0x140C1222), blurRadius: 24, offset: Offset(0, 4)),
          BoxShadow(color: Color(0x0A0C1222), blurRadius: 4, offset: Offset(0, 1)),
        ];

  static const light = SantimTokens(
    background: Color(0xFFF4F6F9),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEEF1F6),
    surfaceElevated: Color(0xFFFFFFFF),
    foreground: Color(0xFF0C1222),
    mutedForeground: Color(0xFF5A6478),
    border: Color(0xFFDDE2EC),
    primary: Color(0xFF059669),
    primaryForeground: Color(0xFFFFFFFF),
    accent: Color(0xFF0D9488),
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
    ring: Color(0xFF059669),
    glow: Color(0x26059669),
    save: Color(0xFF3B5BDB),
    saveLift: Color(0xFF748FFC),
    isDark: false,
  );

  static const dark = SantimTokens(
    background: Color(0xFF080B12),
    surface: Color(0xFF0F1419),
    surfaceMuted: Color(0xFF161C26),
    surfaceElevated: Color(0xFF1A2130),
    foreground: Color(0xFFEEF2F8),
    mutedForeground: Color(0xFF8B95A8),
    border: Color(0xFF232B3A),
    primary: Color(0xFF34D399),
    primaryForeground: Color(0xFF052E1F),
    accent: Color(0xFF2DD4BF),
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    ring: Color(0xFF34D399),
    glow: Color(0x1F34D399),
    save: Color(0xFF8AA4FF),
    saveLift: Color(0xFFB4C4FF),
    isDark: true,
  );

  @override
  SantimTokens copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? surfaceElevated,
    Color? foreground,
    Color? mutedForeground,
    Color? border,
    Color? primary,
    Color? primaryForeground,
    Color? accent,
    Color? success,
    Color? warning,
    Color? danger,
    Color? ring,
    Color? glow,
    Color? save,
    Color? saveLift,
    bool? isDark,
  }) {
    return SantimTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      foreground: foreground ?? this.foreground,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      border: border ?? this.border,
      primary: primary ?? this.primary,
      primaryForeground: primaryForeground ?? this.primaryForeground,
      accent: accent ?? this.accent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      ring: ring ?? this.ring,
      glow: glow ?? this.glow,
      save: save ?? this.save,
      saveLift: saveLift ?? this.saveLift,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  SantimTokens lerp(ThemeExtension<SantimTokens>? other, double t) {
    if (other is! SantimTokens) return this;
    return SantimTokens(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      border: Color.lerp(border, other.border, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryForeground: Color.lerp(primaryForeground, other.primaryForeground, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      ring: Color.lerp(ring, other.ring, t)!,
      glow: Color.lerp(glow, other.glow, t)!,
      save: Color.lerp(save, other.save, t)!,
      saveLift: Color.lerp(saveLift, other.saveLift, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

/// `Theme.of(context).extension<SantimTokens>()!` without the ceremony.
extension SantimTokensX on BuildContext {
  SantimTokens get t => Theme.of(this).extension<SantimTokens>()!;
}
