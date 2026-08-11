import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import '../core/utils/format.dart';
import 'motion.dart';

export 'glass.dart';
export 'motion.dart';

// ---------------------------------------------------------------------------
// Brand
// ---------------------------------------------------------------------------

/// The Santim mark: a rounded gradient tile with a stylised "S" cut from a
/// coin. Drawn rather than shipped as an asset so it recolours with the theme.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40, this.radius});

  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius ?? size * 0.28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.primary, t.accent],
        ),
        boxShadow: [
          BoxShadow(
            color: t.primary.withValues(alpha: 0.35),
            blurRadius: size * 0.35,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      child: Center(
        child: Text(
          'S',
          style: TextStyle(
            fontSize: size * 0.56,
            height: 1,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// "San**tim**" wordmark — the `tim` half carries the primary colour.
class BrandWord extends StatelessWidget {
  const BrandWord({super.key, this.fontSize = 20});
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
          color: t.foreground,
        ),
        children: [
          const TextSpan(text: 'San'),
          TextSpan(text: 'tim', style: TextStyle(color: t.primary)),
        ],
      ),
    );
  }
}

/// Gradient initials bubble, or the user's chosen avatar art.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, this.size = 36, this.avatarId});

  final String name;
  final double size;
  final String? avatarId;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final seed = (avatarId ?? name).hashCode;
    final hue = (seed % 360).toDouble();
    final colors = avatarId != null
        ? [
            HSLColor.fromAHSL(1, hue, 0.62, 0.55).toColor(),
            HSLColor.fromAHSL(1, (hue + 42) % 360, 0.6, 0.45).toColor(),
          ]
        : [t.primary, t.accent];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        boxShadow: [
          BoxShadow(color: colors.first.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initials(name),
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

enum BtnVariant { primary, secondary, outline, ghost, danger }

enum BtnSize { sm, md, lg }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = BtnVariant.primary,
    this.size = BtnSize.md,
    this.icon,
    this.loading = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final BtnVariant variant;
  final BtnSize size;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final enabled = onPressed != null && !loading;

    final (bg, fg, border) = switch (variant) {
      BtnVariant.primary => (t.primary, t.primaryForeground, null),
      BtnVariant.secondary => (t.surfaceMuted, t.foreground, null),
      BtnVariant.outline => (t.surface, t.foreground, t.border),
      BtnVariant.ghost => (Colors.transparent, t.foreground, null),
      BtnVariant.danger => (t.danger, Colors.white, null),
    };

    final (height, hPad, fontSize) = switch (size) {
      BtnSize.sm => (34.0, 12.0, 13.0),
      BtnSize.md => (44.0, 18.0, 14.0),
      BtnSize.lg => (52.0, 24.0, 15.5),
    };

    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (icon != null)
          Icon(icon, size: fontSize + 3, color: fg),
        if (loading || icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: fg),
          ),
        ),
      ],
    );

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: PressableScale(
        scale: 0.98,
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                onPressed!();
              }
            : null,
        child: Container(
          height: height,
          width: expand ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: hPad),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(R.md),
            border: border != null ? Border.all(color: border) : null,
            boxShadow: variant == BtnVariant.primary && enabled
                ? [
                    BoxShadow(
                      color: t.primary.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Circular icon button used in headers and card corners.
class IconPill extends StatelessWidget {
  const IconPill({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.badge,
    this.color,
    this.background,
    this.size = 38,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final int? badge;
  final Color? color;
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    Widget button = Material(
      color: background ?? t.surfaceMuted.withValues(alpha: 0.7),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.48, color: color ?? t.foreground),
        ),
      ),
    );

    if (badge != null && badge! > 0) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              constraints: const BoxConstraints(minWidth: 17),
              decoration: BoxDecoration(
                color: t.danger,
                borderRadius: BorderRadius.circular(R.pill),
                border: Border.all(color: t.background, width: 1.5),
              ),
              child: Text(
                badge! > 99 ? '99+' : '$badge',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 9,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

// ---------------------------------------------------------------------------
// Text & labels
// ---------------------------------------------------------------------------

/// Small uppercase eyebrow used above figures.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: color ?? context.t.mutedForeground,
        ),
      );
}

class Muted extends StatelessWidget {
  const Muted(this.text, {super.key, this.size = 12.5, this.maxLines, this.height});
  final String text;
  final double size;
  final int? maxLines;
  final double? height;

  @override
  Widget build(BuildContext context) => Text(
        text,
        maxLines: maxLines,
        overflow: maxLines != null ? TextOverflow.ellipsis : null,
        style: TextStyle(fontSize: size, height: height, color: context.t.mutedForeground),
      );
}

/// Money figure with tabular digits so columns line up.
class Amount extends StatelessWidget {
  const Amount(
    this.text, {
    super.key,
    this.size = 15,
    this.weight = FontWeight.w700,
    this.color,
  });

  final String text;
  final double size;
  final FontWeight weight;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color ?? context.t.foreground,
          fontFeatures: const [FontFeature.tabularFigures()],
          letterSpacing: -0.3,
        ),
      );
}

enum BadgeTone { neutral, primary, success, warning, danger, info }

class AppBadge extends StatelessWidget {
  const AppBadge(this.label, {super.key, this.tone = BadgeTone.neutral, this.icon, this.dense = false});

  final String label;
  final BadgeTone tone;
  final IconData? icon;
  final bool dense;

  static (Color, Color) colorsFor(BuildContext context, BadgeTone tone) {
    final t = context.t;
    final base = switch (tone) {
      BadgeTone.neutral => t.mutedForeground,
      BadgeTone.primary => t.primary,
      BadgeTone.success => t.success,
      BadgeTone.warning => t.warning,
      BadgeTone.danger => t.danger,
      BadgeTone.info => t.accent,
    };
    return (base.withValues(alpha: t.isDark ? 0.18 : 0.11), base);
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = colorsFor(context, tone);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 2 : 3.5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(R.sm)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: fg), const SizedBox(width: 3)],
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? 10 : 11,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Round icon tile in a category's own colour — the leading element of most
/// list rows in the app.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    this.color,
    this.size = 40,
    this.radius = R.md,
    this.emoji,
  });

  final IconData icon;
  final Color? color;
  final double size;
  final double radius;
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = color ?? t.mutedForeground;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: t.isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: emoji != null
          ? Text(emoji!, style: TextStyle(fontSize: size * 0.46))
          : Icon(icon, size: size * 0.46, color: c),
    );
  }
}

// ---------------------------------------------------------------------------
// Structure
// ---------------------------------------------------------------------------

/// `PageHeader` — title, an optional `(i)` hint, a badge and one action. The
/// description lives behind the icon rather than as subtitle copy.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.description,
    this.action,
    this.badge,
  });

  final String title;
  final String? description;
  final Widget? action;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.6,
                color: context.t.foreground,
              ),
            ),
          ),
          if (description != null) ...[
            const SizedBox(width: 6),
            InfoHint(label: 'About $title', body: description!),
          ],
          if (badge != null) ...[const SizedBox(width: 8), badge!],
          const Spacer(),
          ?action,
        ],
      ),
    );
  }
}

/// `InfoHint` — helper copy lives behind an (i) icon, never inline.
class InfoHint extends StatelessWidget {
  const InfoHint({super.key, required this.label, required this.body, this.size = 16});

  final String label;
  final String body;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => SheetShell(
            title: label,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Text(
                body,
                style: TextStyle(fontSize: 14, height: 1.55, color: t.mutedForeground),
              ),
            ),
          ),
        );
      },
      child: Container(
        width: size + 4,
        height: size + 4,
        decoration: BoxDecoration(
          color: t.surfaceMuted,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(Icons.info_outline, size: size - 4, color: t.mutedForeground),
      ),
    );
  }
}

/// Card header: title on the left, an optional trailing link/action.
class CardTitleRow extends StatelessWidget {
  const CardTitleRow({
    super.key,
    required this.title,
    this.trailing,
    this.icon,
    this.hint,
    this.onTrailingTap,
    this.trailingLabel,
  });

  final String title;
  final Widget? trailing;
  final IconData? icon;
  final String? hint;
  final VoidCallback? onTrailingTap;
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: t.mutedForeground),
          const SizedBox(width: 7),
        ],
        Flexible(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: t.foreground),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 5),
          InfoHint(label: title, body: hint!, size: 14),
        ],
        const Spacer(),
        if (trailing != null)
          trailing!
        else if (trailingLabel != null)
          GestureDetector(
            onTap: onTrailingTap,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Text(
                  trailingLabel!,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.primary),
                ),
                Icon(Icons.chevron_right, size: 15, color: t.primary),
              ],
            ),
          ),
      ],
    );
  }
}

/// `ProgressBar` — gradient fill, 700ms ease-out on value change.
class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    this.tone = BadgeTone.primary,
    this.height = 8,
    this.gradient,
  });

  /// 0–100.
  final double value;
  final BadgeTone tone;
  final double height;
  final List<Color>? gradient;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final colors = gradient ??
        switch (tone) {
          BadgeTone.primary => [t.primary, t.accent],
          BadgeTone.success => [const Color(0xFF10B981), const Color(0xFF14B8A6)],
          BadgeTone.warning => [const Color(0xFFF59E0B), const Color(0xFFF97316)],
          BadgeTone.danger => [const Color(0xFFEF4444), const Color(0xFFF43F5E)],
          BadgeTone.info => [t.accent, t.primary],
          BadgeTone.neutral => [t.mutedForeground, t.mutedForeground],
        };

    return ClipRRect(
      borderRadius: BorderRadius.circular(R.pill),
      child: Container(
        height: height,
        color: t.surfaceMuted,
        child: Align(
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (value / 100).clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 700),
            curve: Motion.easeOut,
            builder: (context, v, _) => FractionallySizedBox(
              widthFactor: v,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(R.pill),
                  gradient: LinearGradient(colors: colors),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `EmptyState` — dashed border, muted icon tile, optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.action,
    this.compact = false,
  });

  final String title;
  final String? description;
  final IconData? icon;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: compact ? 22 : 40),
      decoration: BoxDecoration(
        color: t.surfaceMuted.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: t.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: t.surfaceMuted,
                borderRadius: BorderRadius.circular(R.lg),
              ),
              child: Icon(icon, size: 22, color: t.mutedForeground),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: t.foreground),
          ),
          if (description != null) ...[
            const SizedBox(height: 5),
            Text(
              description!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.45, color: t.mutedForeground),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Inline failure with a retry — used wherever a fetch can fail.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.danger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: t.danger.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(Icons.cloud_off_outlined, size: 26, color: t.danger),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.45, color: t.foreground),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 14),
            AppButton(label: 'Try again', size: BtnSize.sm, variant: BtnVariant.outline, onPressed: onRetry, icon: Icons.refresh),
          ],
        ],
      ),
    );
  }
}

/// Shimmering placeholder layout shown while a page's first payload lands.
class PageLoader extends StatelessWidget {
  const PageLoader({super.key, this.rows = 4, this.hero = true});

  final int rows;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Skeleton(height: 28, width: 170),
        const SizedBox(height: 16),
        if (hero) ...[
          const Skeleton(height: 168, radius: R.xl),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              const Expanded(child: Skeleton(height: 84, radius: R.card)),
            ],
          ],
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Skeleton(height: 62, radius: R.card, margin: EdgeInsets.zero),
          ),
      ],
    );
  }
}

/// Section label between blocks of a scrolling page.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 2),
        child: Row(
          children: [
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: context.t.mutedForeground,
              ),
            ),
            const Spacer(),
            ?trailing,
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Sheets & dialogs
// ---------------------------------------------------------------------------

/// Glass bottom sheet with a grab handle and a title bar — the mobile stand-in
/// for the web app's `Modal`.
class SheetShell extends StatelessWidget {
  const SheetShell({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.action,
    this.scrollable = false,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? action;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final media = MediaQuery.of(context);

    Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Center(
          child: Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: t.border,
              borderRadius: BorderRadius.circular(R.pill),
            ),
          ),
        ),
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title!,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: t.foreground,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Muted(subtitle!),
                      ],
                    ],
                  ),
                ),
                ?action,
                IconPill(
                  icon: Icons.close,
                  size: 32,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        Flexible(child: child),
      ],
    );

    if (scrollable) {
      body = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
        child: body,
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.surface.withValues(alpha: t.isDark ? 0.96 : 0.98),
            border: Border(top: BorderSide(color: t.border)),
          ),
          child: body,
        ),
      ),
    );
  }
}

/// Opens [builder] in a glass sheet sized to its content, keyboard-aware.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
  String? title,
  String? subtitle,
  bool scrollable = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => SheetShell(
      title: title,
      subtitle: subtitle,
      scrollable: scrollable,
      child: builder(ctx),
    ),
  );
}

/// Destructive confirmation — mirrors `ConfirmDialog`.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool danger = true,
}) async {
  final t = context.t;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: t.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.xl)),
      title: Text(
        title,
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.foreground),
      ),
      content: Text(
        message,
        style: TextStyle(fontSize: 14, height: 1.5, color: t.mutedForeground),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: BtnVariant.ghost,
          size: BtnSize.sm,
          onPressed: () => Navigator.pop(ctx, false),
        ),
        AppButton(
          label: confirmLabel,
          variant: danger ? BtnVariant.danger : BtnVariant.primary,
          size: BtnSize.sm,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Toast helper — success and failure share one call site.
void toast(BuildContext context, String message, {bool error = false}) {
  final t = context.t;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle_outline,
              size: 18,
              color: error ? t.danger : t.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: TextStyle(fontSize: 13.5, color: t.foreground)),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      ),
    );
}
