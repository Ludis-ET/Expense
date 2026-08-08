import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Website design tokens from `frontend/src/app/globals.css`.
class SantimTheme {
  static const primaryLight = Color(0xFF059669);
  static const primaryDark = Color(0xFF34D399);
  static const accentLight = Color(0xFF0D9488);
  static const accentDark = Color(0xFF2DD4BF);
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);

  // Aliases used across older screens
  static const seed = primaryLight;
  static const income = success;
  static const expense = danger;
  static const mist = Color(0xFFF4F6F9);
  static const ink = Color(0xFF0C1222);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final primary = isLight ? primaryLight : primaryDark;
    final accent = isLight ? accentLight : accentDark;
    final bg = isLight ? const Color(0xFFF4F6F9) : const Color(0xFF080B12);
    final surface = isLight ? Colors.white : const Color(0xFF0F1419);
    final surfaceMuted = isLight ? const Color(0xFFEEF1F6) : const Color(0xFF161C26);
    final fg = isLight ? const Color(0xFF0C1222) : const Color(0xFFEEF2F8);
    final muted = isLight ? const Color(0xFF5A6478) : const Color(0xFF8B95A8);
    final border = isLight ? const Color(0xFFDDE2EC) : const Color(0xFF232B3A);
    final onPrimary = isLight ? Colors.white : const Color(0xFF052E1F);
    final warn = isLight ? warning : const Color(0xFFFBBF24);
    final dang = isLight ? danger : const Color(0xFFF87171);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: accent,
      onSecondary: onPrimary,
      error: dang,
      onError: Colors.white,
      surface: surface,
      onSurface: fg,
      surfaceContainerLowest: bg,
      surfaceContainerLow: surfaceMuted,
      surfaceContainerHighest: surfaceMuted,
      outline: border,
      outlineVariant: border,
      tertiary: warn,
      onTertiary: fg,
    );

    final text = GoogleFonts.interTextTheme(
      ThemeData(brightness: brightness).textTheme,
    ).apply(bodyColor: fg, displayColor: fg);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      textTheme: text.copyWith(
        displaySmall: text.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
        headlineLarge: text.headlineLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6),
        headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
        titleTextStyle: text.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w700),
        iconTheme: IconThemeData(color: fg),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
        shadowColor: isLight ? const Color(0x0A0C1222) : Colors.black26,
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: TextStyle(color: muted, fontWeight: FontWeight.w500),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          backgroundColor: primary,
          foregroundColor: onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          foregroundColor: fg,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      extensions: [
        SantimColors(
          primary: primary,
          accent: accent,
          success: isLight ? success : primaryDark,
          warning: warn,
          danger: dang,
          muted: muted,
          border: border,
          surfaceMuted: surfaceMuted,
        ),
      ],
    );
  }

  static Color amountColor(String kind, ColorScheme scheme) => switch (kind) {
        'INCOME' => scheme.brightness == Brightness.light ? success : primaryDark,
        'EXPENSE' => scheme.error,
        _ => scheme.onSurface.withValues(alpha: 0.55),
      };

  static LinearGradient heroGradient(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: dark
          ? const [Color(0xFF34D399), Color(0xFF059669), Color(0xFF0D9488)]
          : const [Color(0xFF059669), Color(0xFF059669), Color(0xFF0D9488)],
    );
  }

  static List<BoxShadow> cardShadow(Brightness brightness) => [
        BoxShadow(
          color: brightness == Brightness.light
              ? const Color(0x0A0C1222)
              : Colors.black.withValues(alpha: 0.2),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: brightness == Brightness.light
              ? const Color(0x0F0C1222)
              : Colors.black.withValues(alpha: 0.15),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];
}

class SantimColors extends ThemeExtension<SantimColors> {
  const SantimColors({
    required this.primary,
    required this.accent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.muted,
    required this.border,
    required this.surfaceMuted,
  });

  final Color primary;
  final Color accent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color muted;
  final Color border;
  final Color surfaceMuted;

  // Concept-era aliases so older screens compile
  Color get mint => primary;
  Color get cyan => accent;
  Color get coral => danger;
  Color get amber => warning;
  Color get violet => accent;

  @override
  SantimColors copyWith({
    Color? primary,
    Color? accent,
    Color? success,
    Color? warning,
    Color? danger,
    Color? muted,
    Color? border,
    Color? surfaceMuted,
  }) =>
      SantimColors(
        primary: primary ?? this.primary,
        accent: accent ?? this.accent,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        muted: muted ?? this.muted,
        border: border ?? this.border,
        surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      );

  @override
  SantimColors lerp(ThemeExtension<SantimColors>? other, double t) {
    if (other is! SantimColors) return this;
    return SantimColors(
      primary: Color.lerp(primary, other.primary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
    );
  }
}

Route<T> santimRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, animation, __) => page,
    transitionsBuilder: (_, animation, secondary, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// No-op backdrop kept for call sites that wrapped screens in AuroraBackdrop.
class AuroraBackdrop extends StatelessWidget {
  const AuroraBackdrop({super.key, this.child});
  final Widget? child;
  @override
  Widget build(BuildContext context) => child ?? const SizedBox.shrink();
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.radius = 16,
    this.borderColor,
    this.gradient,
    this.strong = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final double radius;
  final Color? borderColor;
  final Gradient? gradient;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: padding,
      onTap: onTap,
      gradient: gradient,
      child: child,
    );
  }
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.badge,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final btn = IconButton(
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: badge != null,
        label: badge,
        child: Icon(icon),
      ),
    );
    if (tooltip == null) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).extension<SantimColors>()!.muted;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
        color: color ?? muted,
      ),
    );
  }
}

/// Website brand mark (rounded green tile + S).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF34D399), Color(0xFF059669), Color(0xFF115E59)],
        ),
        boxShadow: [
          BoxShadow(
            color: SantimTheme.primaryLight.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        'S',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.48,
          height: 1,
        ),
      ),
    );
  }
}

class BrandRow extends StatelessWidget {
  const BrandRow({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrandMark(),
        if (!compact) ...[
          const SizedBox(width: 10),
          Text.rich(
            TextSpan(
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              children: [
                const TextSpan(text: 'San'),
                TextSpan(
                  text: 'tim',
                  style: TextStyle(color: theme.colorScheme.primary),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Website-style card: white/surface, 1px border, 16px radius, soft shadow.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.gradient,
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = theme.extension<SantimColors>()!.border;

    final body = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? theme.colorScheme.surface) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: SantimTheme.cardShadow(theme.brightness),
      ),
      child: child,
    );

    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: body,
      ),
    );
  }
}
