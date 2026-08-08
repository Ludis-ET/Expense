import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Branded launch animation shown while the session and local cache boot.
///
/// Native [LaunchTheme] covers the gap before Flutter paints; this takes over
/// for the half-second of auth + sqflite hydrate so the first real screen
/// never flashes empty.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _mark;
  late final AnimationController _pulse;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  late final Animation<double> _ring;

  @override
  void initState() {
    super.initState();

    _mark = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();

    _scale = CurvedAnimation(parent: _mark, curve: Curves.easeOutBack);
    _fade = CurvedAnimation(parent: _mark, curve: const Interval(0.15, 1, curve: Curves.easeOut));
    _ring = CurvedAnimation(parent: _pulse, curve: Curves.easeInOut);

    _mark.forward();
  }

  @override
  void dispose() {
    _mark.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1220) : const Color(0xFFF4F6F9),
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.35),
                  radius: 1.1,
                  colors: [
                    SantimTheme.seed.withValues(alpha: isDark ? 0.28 : 0.18),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _ring,
                      builder: (context, child) {
                        final t = _ring.value;
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Transform.scale(
                              scale: 1 + (t * 0.35),
                              child: Opacity(
                                opacity: (1 - t).clamp(0.0, 1.0),
                                child: Container(
                                  width: 108,
                                  height: 108,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: SantimTheme.seed.withValues(alpha: 0.35),
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            child!,
                          ],
                        );
                      },
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF10B981), Color(0xFF0D9488)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: SantimTheme.seed.withValues(alpha: 0.35),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: _MarkLetter(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Santim',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your money, offline too',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: SantimTheme.seed.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 36 + MediaQuery.paddingOf(context).bottom,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final sway = math.sin(_pulse.value * math.pi * 2) * 4;
                return Transform.translate(
                  offset: Offset(sway, 0),
                  child: Icon(
                    Icons.sync_alt_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkLetter extends StatelessWidget {
  const _MarkLetter();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'S',
      style: TextStyle(
        color: Colors.white,
        fontSize: 40,
        fontWeight: FontWeight.w800,
        height: 1,
        letterSpacing: -1,
      ),
    );
  }
}
