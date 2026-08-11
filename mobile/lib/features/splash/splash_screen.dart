import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/ui.dart';

/// The animated brand splash from `components/splash-screen.tsx`, staged the
/// same way: the ring draws over 1.5s while the mark pops in, the wordmark and
/// tagline rise behind it, and a sweep bar loops underneath. Held for 1.9s,
/// then cross-faded out over 550ms.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onDone, this.label});

  final VoidCallback? onDone;
  final String? label;

  static const hold = Duration(milliseconds: 1900);
  static const fade = Duration(milliseconds: 550);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  /// Keeps spinning after the draw completes — `spin-slow 9s linear infinite`.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..forward();

  @override
  void initState() {
    super.initState();
    _ring.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) _spin.repeat();
    });
    if (widget.onDone != null) {
      Future.delayed(SplashScreen.hold, () {
        if (mounted) widget.onDone!();
      });
    }
  }

  @override
  void dispose() {
    _ring.dispose();
    _spin.dispose();
    _sweep.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.background,
      body: MeshBackground(
        intensity: 1.4,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 176,
                  height: 176,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: Listenable.merge([_ring, _spin]),
                        builder: (context, _) {
                          // strokeDashoffset 302 → 64 over the draw, i.e. the
                          // arc grows to ~79% of the circle.
                          final drawn = Curves.easeInOut.transform(_ring.value) * 0.79;
                          return Transform.rotate(
                            angle: _spin.value * 2 * math.pi,
                            child: CustomPaint(
                              size: const Size(176, 176),
                              painter: RingPainter(
                                progress: drawn,
                                trackColor: t.border.withValues(alpha: 0.6),
                                colors: [t.primary, t.accent],
                                strokeWidth: 6,
                              ),
                            ),
                          );
                        },
                      ),
                      ScaleTransition(
                        scale: Tween(begin: 0.6, end: 1.0).animate(
                          CurvedAnimation(parent: _pop, curve: Motion.spring),
                        ),
                        child: FadeTransition(
                          opacity: _pop,
                          child: PulseGlow(
                            min: 0.75,
                            child: const BrandMark(size: 80),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                FadeInUp(
                  delay: const Duration(milliseconds: 120),
                  child: const BrandWord(fontSize: 30),
                ),
                const SizedBox(height: 6),
                FadeInUp(
                  delay: const Duration(milliseconds: 180),
                  child: Muted(widget.label ?? 'Know where every birr goes', size: 13.5),
                ),
                const SizedBox(height: 32),
                FadeInUp(
                  delay: const Duration(milliseconds: 180),
                  child: SizedBox(
                    width: 160,
                    height: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(R.pill),
                      child: Stack(
                        children: [
                          Positioned.fill(child: ColoredBox(color: t.surfaceMuted)),
                          AnimatedBuilder(
                            animation: _sweep,
                            builder: (context, _) {
                              final v = Curves.easeInOut.transform(_sweep.value);
                              return Align(
                                // translateX(-100% → 320%) across the track.
                                alignment: Alignment(-1 + v * 2.6, 0),
                                child: FractionallySizedBox(
                                  widthFactor: 1 / 3,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(R.pill),
                                      gradient: LinearGradient(colors: [t.primary, t.accent]),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `AppLoader` — the branded full-screen loader used while the session
/// bootstraps behind the splash.
class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.label = 'Loading your workspace…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: t.background,
      body: MeshBackground(
        child: Center(
          child: FadeInUp(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    _SpinArc(color: t.primary, size: 78),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: BorderRadius.circular(R.xl),
                        border: Border.all(color: t.border),
                        boxShadow: t.elevatedShadow,
                      ),
                      child: const BrandMark(size: 44),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  label,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: t.foreground),
                ),
                const SizedBox(height: 16),
                const BouncingDots(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.animate-spin-slow` — a quarter-arc rotating at 1.1s per turn.
class _SpinArc extends StatefulWidget {
  const _SpinArc({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  State<_SpinArc> createState() => _SpinArcState();
}

class _SpinArcState extends State<_SpinArc> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Transform.rotate(
        angle: _c.value * 2 * math.pi,
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: RingPainter(
            progress: 0.24,
            trackColor: Colors.transparent,
            colors: [widget.color.withValues(alpha: 0.9)],
            strokeWidth: 3,
          ),
        ),
      ),
    );
  }
}
