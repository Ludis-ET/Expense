import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/ui.dart';

/// Brand splash: short mark pop + wordmark, then hand off to the app.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onDone, this.label});

  final VoidCallback? onDone;
  final String? label;

  static const hold = Duration(milliseconds: 1100);
  static const fade = Duration(milliseconds: 280);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();

  @override
  void initState() {
    super.initState();
    FlutterNativeSplash.remove();
    if (widget.onDone != null) {
      Future.delayed(SplashScreen.hold, () {
        if (mounted) widget.onDone!();
      });
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: t.background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: t.background,
        body: MeshBackground(
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale: Tween(
                      begin: 0.72,
                      end: 1.0,
                    ).animate(CurvedAnimation(parent: _pop, curve: Motion.easeOut)),
                    child: FadeTransition(opacity: _pop, child: const BrandMark(size: 84)),
                  ),
                  const Gap(S.xxl),
                  FadeTransition(
                    opacity: _pop,
                    child: const BrandWord(fontSize: AppType.display),
                  ),
                  const Gap(S.sm),
                  FadeTransition(
                    opacity: _pop,
                    child: Muted(widget.label ?? 'Know where every birr goes', size: 14),
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

/// Branded full-screen loader used while the session bootstraps.
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: t.primary,
                      backgroundColor: t.border.withValues(alpha: 0.5),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(S.sm),
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(R.xl),
                      border: Border.all(color: t.border),
                    ),
                    child: const BrandMark(size: 40),
                  ),
                ],
              ),
              const Gap(S.xxl),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppType.bodySm,
                  fontWeight: FontWeight.w500,
                  color: t.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
