// Depth, used to say something.
//
// Two plan types with opposite physics: a spending envelope is a container
// being emptied, a saving pot is one being filled. Rendering both as the same
// flat progress bar throws that away - so the shared vocabulary here is a
// *well*, a recessed volume with something in it, and the two types differ in
// which way the contents move.
//
// Flutter has no inset box-shadow, so the recess is painted rather than
// declared. Everything below takes its colour from `tokens.dart`; nothing here
// invents one.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';

/// Which way the contents of a [InsetWell] move.
enum WellAxis {
  /// Spending: the fill retreats leftward as money goes.
  horizontal,

  /// Saving: the fill rises from the bottom as money arrives.
  vertical,
}

/// A recessed track with a fill inside it.
///
/// The recess is two gradients and a light bottom edge: a dark top lip where a
/// real cavity would be shadowed, and a bright bottom lip where it would catch
/// light. Subtle on purpose - at these sizes a heavier treatment reads as a
/// bevel rather than a depth.
class InsetWell extends StatelessWidget {
  const InsetWell({
    super.key,
    required this.value,
    required this.fill,
    this.axis = WellAxis.horizontal,
    this.height = 26,
    this.radius = R.md,
    this.ticks = 0,
    this.strata = const [],
    this.target,
    this.targetLabel,
    this.animate = true,
  });

  /// 0..1. Clamped, so an overshot saving goal fills rather than overflows.
  final double value;

  /// The fill's colour. Its lit edge is derived, not passed.
  final Color fill;

  final WellAxis axis;
  final double height;
  final double radius;

  /// Faint dividers across the track. Used by spending to give the drain a
  /// pace - a week each - to be judged against.
  final int ticks;

  /// Fractions (0..1) inside the fill where a contribution landed. Each leaves
  /// a visible line, so the pot carries its own history.
  final List<double> strata;

  /// 0..1. A dashed line the fill is rising toward.
  final double? target;
  final String? targetLabel;

  final bool animate;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final br = BorderRadius.circular(radius);

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: br,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The cavity.
            DecoratedBox(
              decoration: BoxDecoration(
                color: t.surfaceMuted,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: t.isDark ? 0.30 : 0.08),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.42],
                ),
              ),
            ),

            // The contents.
            _Fill(
              value: v,
              axis: axis,
              fill: fill,
              radius: radius,
              strata: strata,
              animate: animate,
            ),

            if (ticks > 1) _Ticks(count: ticks, dark: t.isDark),

            if (target != null)
              _TargetLine(
                at: target!.clamp(0.0, 1.0),
                label: targetLabel,
                color: t.save,
              ),

            // The lit bottom lip, over everything, so the cavity reads as a
            // cavity even where the fill reaches the edge.
            IgnorePointer(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: t.isDark ? 0.06 : 0.55),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fill extends StatelessWidget {
  const _Fill({
    required this.value,
    required this.axis,
    required this.fill,
    required this.radius,
    required this.strata,
    required this.animate,
  });

  final double value;
  final WellAxis axis;
  final Color fill;
  final double radius;
  final List<double> strata;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final horizontal = axis == WellAxis.horizontal;

    // Emptying settles; filling springs. Opposite curves for opposite physics.
    final curve = horizontal ? Motion.easeOut : Motion.spring;

    final body = LayoutBuilder(
      builder: (context, c) {
        final w = horizontal ? c.maxWidth * value : c.maxWidth;
        final h = horizontal ? c.maxHeight : c.maxHeight * value;
        return Align(
          alignment: horizontal ? Alignment.centerLeft : Alignment.bottomCenter,
          child: SizedBox(
            width: w.isFinite ? w : 0,
            height: h.isFinite ? h : 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.lerp(fill, Colors.white, 0.22)!,
                    fill,
                  ],
                ),
                boxShadow: [
                  // The fill's own edge, so it sits *in* the well rather than on it.
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 5,
                    offset: horizontal ? const Offset(2, 0) : const Offset(0, -2),
                  ),
                ],
              ),
              child: strata.isEmpty
                  ? null
                  : CustomPaint(painter: _StrataPainter(strata: strata)),
            ),
          ),
        );
      },
    );

    if (!animate) return body;
    return AnimatedSize(
      duration: Motion.enter,
      curve: curve,
      child: body,
    );
  }
}

/// One hairline per contribution, inside the fill.
class _StrataPainter extends CustomPainter {
  const _StrataPainter({required this.strata});

  final List<double> strata;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 1;
    for (final f in strata) {
      if (f <= 0 || f >= 1) continue;
      final y = size.height * (1 - f);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_StrataPainter old) => !_sameList(old.strata, strata);

  static bool _sameList(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.0001) return false;
    }
    return true;
  }
}

class _Ticks extends StatelessWidget {
  const _Ticks({required this.count, required this.dark});

  final int count;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: i == count - 1
                      ? null
                      : Border(
                          right: BorderSide(
                            color: Colors.black.withValues(alpha: dark ? 0.22 : 0.055),
                          ),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TargetLine extends StatelessWidget {
  const _TargetLine({required this.at, required this.label, required this.color});

  final double at;
  final String? label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: (c.maxHeight * at) - 1,
              child: CustomPaint(
                size: Size(c.maxWidth, 2),
                painter: _DashedLinePainter(color: color.withValues(alpha: 0.75)),
              ),
            ),
            if (label != null)
              Positioned(
                right: 7,
                // Below the line, inside the well: the well clips, so a label
                // above the top edge would simply vanish.
                bottom: math.max(2, (c.maxHeight * at) - 14),
                child: Text(
                  label!,
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 0.5,
                    fontWeight: W.semibold,
                    color: t.mutedForeground,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    const dash = 4.0;
    const gap = 3.0;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(math.min(x + dash, size.width), size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}

/// Tilts toward the touch while held.
///
/// The existing [PressableScale] shrinks; this rotates in three dimensions, so
/// a card that is *about* depth responds like an object rather than a button.
/// Reduced-motion is honoured: the tilt is skipped entirely and only the press
/// scale remains, because a vestibular trigger is not worth a flourish.
class PressableTilt extends StatefulWidget {
  const PressableTilt({
    super.key,
    required this.child,
    this.onTap,
    this.maxTilt = 0.035,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// Radians at the far corner. Small - past about 0.05 it stops reading as a
  /// physical response and starts reading as a gimmick.
  final double maxTilt;

  @override
  State<PressableTilt> createState() => _PressableTiltState();
}

class _PressableTiltState extends State<PressableTilt> {
  Offset? _local;
  Size? _size;
  bool _down = false;

  bool get _reduced => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _set(Offset? local, Size? size, bool down) {
    if (!mounted) return;
    setState(() {
      _local = local;
      _size = size;
      _down = down;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tiltable = !_reduced && _down && _local != null && _size != null;

    var m = Matrix4.identity();
    if (tiltable) {
      final s = _size!;
      // Where the finger is, as -1..1 from the centre.
      final dx = ((_local!.dx / s.width) * 2 - 1).clamp(-1.0, 1.0);
      final dy = ((_local!.dy / s.height) * 2 - 1).clamp(-1.0, 1.0);
      m = Matrix4.identity()
        // Perspective. Without this the rotations are a flat shear.
        ..setEntry(3, 2, 0.0012)
        ..rotateX(-dy * widget.maxTilt)
        ..rotateY(dx * widget.maxTilt)
        ..scaleByDouble(0.985, 0.985, 1, 1);
    } else if (_down) {
      m = Matrix4.identity()..scaleByDouble(0.985, 0.985, 1, 1);
    }

    return Listener(
      onPointerDown: (e) => _set(e.localPosition, context.size, true),
      onPointerMove: (e) {
        if (_down) _set(e.localPosition, context.size, true);
      },
      onPointerUp: (_) => _set(null, null, false),
      onPointerCancel: (_) => _set(null, null, false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.easeOut,
          transform: m,
          transformAlignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}
