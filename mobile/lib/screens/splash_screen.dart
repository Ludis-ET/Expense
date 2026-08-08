import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _orbit;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _orbit = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
    _scale = CurvedAnimation(parent: _intro, curve: Curves.easeOutBack);
    _fade = CurvedAnimation(parent: _intro, curve: const Interval(0.12, 1, curve: Curves.easeOut));
    _intro.forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    _orbit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.2),
            radius: 1.15,
            colors: [
              SantimTheme.seed.withValues(alpha: dark ? 0.35 : 0.22),
              dark ? const Color(0xFF07110D) : SantimTheme.mist,
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  AnimatedBuilder(
                    animation: _orbit,
                    builder: (context, child) {
                      final t = _orbit.value * math.pi * 2;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.rotate(
                            angle: t,
                            child: Container(
                              width: 128,
                              height: 128,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: SantimTheme.seed.withValues(alpha: 0.22),
                                  width: 1.4,
                                ),
                              ),
                            ),
                          ),
                          Transform.rotate(
                            angle: -t * 0.7,
                            child: Container(
                              width: 156,
                              height: 156,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: SantimTheme.seed.withValues(alpha: 0.1),
                                  width: 1,
                                ),
                              ),
                            ),
                          ),
                          child!,
                        ],
                      );
                    },
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: SantimTheme.seed.withValues(alpha: 0.4),
                            blurRadius: 36,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/branding/app_icon.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          decoration: BoxDecoration(
                            gradient: SantimTheme.heroGradient(theme.brightness),
                          ),
                          child: const Icon(Icons.payments_rounded, color: Colors.white, size: 44),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text('Santim', style: theme.textTheme.displaySmall),
                  const SizedBox(height: 8),
                  Text(
                    'Your money, beautifully tracked',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(flex: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 36),
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: SantimTheme.seed.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
