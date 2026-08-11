import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';

/// Frosted-looking card without live [BackdropFilter] (too costly on mid-range
/// GPUs). Uses an opaque/semi-opaque gradient so scrolls stay smooth.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = R.card,
    this.blur = 0,
    this.opacity = 0.94,
    this.tint,
    this.borderColor,
    this.onTap,
    this.margin,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  /// Kept for API compatibility; blur is intentionally unused for performance.
  final double blur;
  final double opacity;

  /// Optional colour wash — used to signal state (danger, warning, primary).
  final Color? tint;
  final Color? borderColor;
  final VoidCallback? onTap;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final base = tint ?? t.surface;
    final br = BorderRadius.circular(radius);

    Widget pane = ClipRRect(
      borderRadius: br,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: br,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              base.withValues(alpha: opacity),
              base.withValues(alpha: opacity * (t.isDark ? 0.9 : 0.98)),
            ],
          ),
          border: Border.all(
            color: borderColor ??
                (t.isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.white.withValues(alpha: 0.65)),
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: radius * 2,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: t.isDark ? 0.05 : 0.28),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );

    if (onTap != null) {
      pane = Stack(
        children: [
          pane,
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: br,
                onTap: onTap,
                splashColor: t.primary.withValues(alpha: 0.08),
                highlightColor: t.primary.withValues(alpha: 0.04),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: elevated ? t.elevatedShadow : t.cardShadow,
      ),
      child: pane,
    );
  }
}

/// Opaque sibling of [GlassCard] — the web app's `.card`. Cheaper to paint, so
/// it is the default for list rows and anything that repeats.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.radius = R.card,
    this.onTap,
    this.color,
    this.borderColor,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final br = BorderRadius.circular(radius);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? (elevated ? t.surfaceElevated : t.surface),
        borderRadius: br,
        border: Border.all(color: borderColor ?? t.border),
        boxShadow: elevated ? t.elevatedShadow : t.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: br,
          splashColor: t.primary.withValues(alpha: 0.07),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Soft brand wash behind screens. Static by default — drifting orbs + blur
/// masks tank FPS on mid-range Android GPUs.
class MeshBackground extends StatefulWidget {
  const MeshBackground({
    super.key,
    required this.child,
    this.showGrid = false,
    this.animate = false,
    this.intensity = 1,
  });

  final Widget child;
  final bool showGrid;
  final bool animate;
  final double intensity;

  @override
  State<MeshBackground> createState() => _MeshBackgroundState();
}

class _MeshBackgroundState extends State<MeshBackground> with TickerProviderStateMixin {
  AnimationController? _a;
  AnimationController? _b;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _a = AnimationController(vsync: this, duration: const Duration(seconds: 7))
        ..repeat(reverse: true);
      _b = AnimationController(vsync: this, duration: const Duration(seconds: 8))
        ..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _a?.dispose();
    _b?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final intensity = widget.intensity * (t.isDark ? 0.85 : 1);
    final mesh = widget.animate && _a != null && _b != null
        ? AnimatedBuilder(
            animation: Listenable.merge([_a!, _b!]),
            builder: (context, _) {
              final ea = Curves.easeInOut.transform(_a!.value);
              final eb = Curves.easeInOut.transform(_b!.value);
              return CustomPaint(
                painter: _MeshPainter(
                  primary: t.primary,
                  accent: t.accent,
                  intensity: intensity,
                  shiftA: Offset(18 * ea, -22 * ea),
                  shiftB: Offset(-20 * eb, 16 * eb),
                  scaleA: 1 + 0.08 * ea,
                  scaleB: 1 + 0.1 * eb,
                ),
              );
            },
          )
        : CustomPaint(
            painter: _MeshPainter(
              primary: t.primary,
              accent: t.accent,
              intensity: intensity,
              shiftA: Offset.zero,
              shiftB: Offset.zero,
              scaleA: 1,
              scaleB: 1,
            ),
          );

    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: t.background)),
        if (widget.showGrid)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _GridPainter(t.border.withValues(alpha: t.isDark ? 0.35 : 0.5)),
              ),
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(child: mesh),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const step = 48.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.color != color;
}

class _MeshPainter extends CustomPainter {
  _MeshPainter({
    required this.primary,
    required this.accent,
    required this.intensity,
    required this.shiftA,
    required this.shiftB,
    required this.scaleA,
    required this.scaleB,
  });

  final Color primary;
  final Color accent;
  final double intensity;
  final Offset shiftA;
  final Offset shiftB;
  final double scaleA;
  final double scaleB;

  @override
  void paint(Canvas canvas, Size size) {
    void orb(Offset center, double radius, Color color, double alpha) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      // Soft radial only — MaskFilter.blur was a full-screen GPU tax every frame.
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: alpha * intensity), color.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }

    orb(
      Offset(size.width * 0.1, 0) + shiftA,
      size.width * 0.75 * scaleA,
      primary,
      0.18,
    );
    orb(
      Offset(size.width * 0.9, size.height * 0.1) + shiftB,
      size.width * 0.55 * scaleB,
      accent,
      0.12,
    );
  }

  @override
  bool shouldRepaint(_MeshPainter old) =>
      old.shiftA != shiftA || old.shiftB != shiftB || old.primary != primary;
}

/// The gradient hero surface (`from-primary via-primary to-accent`) with the
/// two blurred white orbs and the 10%-opacity grid the web hero carries.
class GradientHero extends StatelessWidget {
  const GradientHero({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = R.xl,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: t.primary.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [t.primary, t.primary, t.accent],
              stops: const [0, 0.55, 1],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -64,
                top: -64,
                child: _Blob(size: 192, color: Colors.white.withValues(alpha: 0.10)),
              ),
              Positioned(
                left: -32,
                bottom: -32,
                child: _Blob(size: 128, color: Colors.white.withValues(alpha: 0.06)),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _GridPainter(Colors.white.withValues(alpha: 0.10)),
                  ),
                ),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [BoxShadow(color: color, blurRadius: size / 3, spreadRadius: size / 8)],
        ),
      ),
    );
  }
}

/// Soft translucent pill (no backdrop blur — keeps list/hero scrolls cheap).
class GlassChip extends StatelessWidget {
  const GlassChip({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    this.radius = R.md,
    this.onTap,
    this.borderLeftColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? borderLeftColor;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: br,
      child: Material(
        color: Colors.white.withValues(alpha: 0.18),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: padding,
            decoration: borderLeftColor != null
                ? BoxDecoration(
                    border: Border(left: BorderSide(color: borderLeftColor!, width: 3)),
                  )
                : null,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Circular progress ring drawn by hand — the splash uses it, and so do the
/// budget health dials.
class RingPainter extends CustomPainter {
  RingPainter({
    required this.progress,
    required this.trackColor,
    required this.colors,
    this.strokeWidth = 6,
    this.startAngle = -math.pi / 2,
  });

  final double progress;
  final Color trackColor;
  final List<Color> colors;
  final double strokeWidth;
  final double startAngle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 0.75
        ..color = trackColor,
    );

    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      startAngle,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: colors.length == 1 ? [colors.first, colors.first] : colors,
          startAngle: 0,
          endAngle: 2 * math.pi,
          transform: GradientRotation(startAngle),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.progress != progress || old.colors != colors || old.trackColor != trackColor;
}
