import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';

bool _skipMotion(BuildContext context) => MediaQuery.disableAnimationsOf(context);

/// Fast rise-in for list sections. Skips when Reduce motion is on.
class FadeInUp extends StatefulWidget {
  const FadeInUp({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 6,
    this.duration = Motion.enter,
  });

  FadeInUp.staggered({
    super.key,
    required this.child,
    required int index,
    this.offset = 6,
    this.duration = Motion.enter,
  }) : delay = Duration(milliseconds: 24 * index.clamp(0, 8));

  final Widget child;
  final Duration delay;
  final double offset;
  final Duration duration;

  @override
  State<FadeInUp> createState() => _FadeInUpState();
}

class _FadeInUpState extends State<FadeInUp> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Animation<double>? _curve;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_skipMotion(context)) {
      _c?.dispose();
      _c = null;
      _curve = null;
      return;
    }
    if (_c != null) return;
    _c = AnimationController(vsync: this, duration: widget.duration);
    _curve = CurvedAnimation(parent: _c!, curve: Motion.easeOut);
    if (widget.delay == Duration.zero) {
      _c!.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c?.forward();
      });
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = _curve;
    if (curve == null || _skipMotion(context)) return widget.child;
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// `.stagger-children` — wraps a column's children so each rises after the one above.
class StaggerColumn extends StatelessWidget {
  const StaggerColumn({
    super.key,
    required this.children,
    this.spacing = 16,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    this.startIndex = 0,
  });

  final List<Widget> children;
  final double spacing;
  final CrossAxisAlignment crossAxisAlignment;
  final int startIndex;

  @override
  Widget build(BuildContext context) {
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) out.add(SizedBox(height: spacing));
      out.add(FadeInUp.staggered(index: startIndex + i, child: children[i]));
    }
    return Column(crossAxisAlignment: crossAxisAlignment, children: out);
  }
}

/// `@keyframes shimmer` — highlight sweeping left to right across a placeholder.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_skipMotion(context)) {
      _c?.dispose();
      _c = null;
      return;
    }
    _c ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = _c;
    if (c == null || _skipMotion(context)) return widget.child;
    return AnimatedBuilder(
      animation: c,
      builder: (context, child) {
        final v = Curves.easeInOut.transform(c.value);
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(-1.6 + 3.2 * v, -0.35),
            end: Alignment(-0.6 + 3.2 * v, 0.35),
            colors: [
              Colors.transparent,
              Colors.white.withValues(alpha: t.isDark ? 0.06 : 0.85),
              Colors.transparent,
            ],
          ).createShader(bounds),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A shimmering placeholder block.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = R.md, this.margin});

  final double height;
  final double? width;
  final double radius;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Shimmer(
      child: Container(
        height: height,
        width: width,
        margin: margin,
        decoration: BoxDecoration(
          color: t.surfaceMuted,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// `@keyframes bounce-dot` — the three-dot "thinking" indicator.
class BouncingDots extends StatefulWidget {
  const BouncingDots({super.key, this.color, this.size = 6});
  final Color? color;
  final double size;

  @override
  State<BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<BouncingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_skipMotion(context)) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return Padding(
            padding: EdgeInsets.only(right: i == 2 ? 0 : widget.size * 0.66),
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: widget.color ?? context.t.primary,
                shape: BoxShape.circle,
              ),
            ),
          );
        }),
      );
    }
    final color = widget.color ?? context.t.primary;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final phase = (_c.value - i * 0.16) % 1.0;
          final lift = phase < 0.4 ? math.sin(phase / 0.4 * math.pi) : 0.0;
          return Padding(
            padding: EdgeInsets.only(right: i == 2 ? 0 : widget.size * 0.66),
            child: Transform.translate(
              offset: Offset(0, -4 * lift),
              child: Opacity(
                opacity: 0.4 + 0.6 * lift,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Soft opacity breathe — disabled under Reduce motion.
class PulseGlow extends StatefulWidget {
  const PulseGlow({super.key, required this.child, this.min = 0.6});
  final Widget child;
  final double min;

  @override
  State<PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<PulseGlow> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_skipMotion(context)) {
      _c?.dispose();
      _c = null;
      return;
    }
    _c ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null || _skipMotion(context)) return widget.child;
    return FadeTransition(
      opacity: Tween(
        begin: widget.min,
        end: 1.0,
      ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

/// Counts a number up on first paint.
class AnimatedNumber extends StatefulWidget {
  const AnimatedNumber({
    super.key,
    required this.value,
    required this.builder,
    this.duration = const Duration(milliseconds: 480),
  });

  final double value;
  final Widget Function(BuildContext context, double value) builder;
  final Duration duration;

  @override
  State<AnimatedNumber> createState() => _AnimatedNumberState();
}

class _AnimatedNumberState extends State<AnimatedNumber> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late Animation<double> _anim = _tween(0, widget.value);

  Animation<double> _tween(double from, double to) =>
      Tween(begin: from, end: to).animate(CurvedAnimation(parent: _c, curve: Motion.easeOut));

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_skipMotion(context) && _c.value != 1) {
      _c.value = 1;
    }
  }

  @override
  void didUpdateWidget(AnimatedNumber old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      if (_skipMotion(context)) {
        _anim = _tween(widget.value, widget.value);
        _c.value = 1;
        return;
      }
      _anim = _tween(_anim.value, widget.value);
      _c
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (context, _) => widget.builder(context, _anim.value),
  );
}

/// Scales down slightly while held.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.minTapTarget,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  /// Grows the *hit area* to at least this many logical pixels in both axes
  /// without changing the drawn size. Use 48 to meet Android's minimum on a
  /// control that is deliberately drawn smaller.
  final double? minTapTarget;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null || widget.onLongPress != null;
    final min = widget.minTapTarget;

    Widget visual = AnimatedScale(
      scale: _down ? widget.scale : 1,
      duration: _skipMotion(context) ? Duration.zero : const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      child: widget.child,
    );

    // `Center` hands the visual loose constraints, so the minimum below grows
    // only the transparent hit area around it — the drawn control keeps its
    // own size.
    if (min != null) {
      visual = Center(widthFactor: 1, heightFactor: 1, child: visual);
    }

    Widget result = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: interactive ? (_) => setState(() => _down = true) : null,
      onTapUp: interactive ? (_) => setState(() => _down = false) : null,
      onTapCancel: interactive ? () => setState(() => _down = false) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: visual,
    );

    if (min != null) {
      result = ConstrainedBox(
        constraints: BoxConstraints(minWidth: min, minHeight: min),
        child: result,
      );
    }

    return result;
  }
}

/// `@keyframes lock-shake` — horizontal shake on a wrong PIN.
class ShakeX extends StatefulWidget {
  const ShakeX({super.key, required this.child, required this.trigger});
  final Widget child;

  /// Increment to fire the shake.
  final int trigger;

  @override
  State<ShakeX> createState() => _ShakeXState();
}

class _ShakeXState extends State<ShakeX> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );

  @override
  void didUpdateWidget(ShakeX old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final dx = math.sin(_c.value * math.pi * 4) * 6 * (1 - _c.value);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}

/// `@keyframes sync-pop` — overshoot scale-in for the "just synced" tick.
class PopIn extends StatefulWidget {
  const PopIn({super.key, required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  State<PopIn> createState() => _PopInState();
}

class _PopInState extends State<PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_skipMotion(context)) return widget.child;
    final anim = CurvedAnimation(parent: _c, curve: Motion.spring);
    return ScaleTransition(
      scale: Tween(begin: 0.4, end: 1.0).animate(anim),
      child: FadeTransition(opacity: _c, child: widget.child),
    );
  }
}
