import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../state/prefs_state.dart';
import '../../widgets/ui.dart';

/// What a new account sees before the dashboard.
///
/// Without this, signing up landed straight on an empty dashboard: no wallets,
/// no plans, no transactions, and a column of empty states explaining what
/// would eventually go there. Three screens set expectations and hand over with
/// one obvious next action.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = <_Page>[
    _Page(
      art: OnboardingArtKind.wallets,
      title: 'Start with where your money sits',
      body:
          'Add a wallet for cash, one for each bank account, one for mobile '
          'money. Santim keeps every currency separate   totals are never mixed.',
    ),
    _Page(
      art: OnboardingArtKind.plans,
      title: 'Set money aside before you spend it',
      body:
          'A plan is a funded envelope, not a limit. Money you put in a plan '
          'is taken out of your available balance, so what you see is genuinely '
          'yours to spend.',
    ),
    _Page(
      art: OnboardingArtKind.capture,
      title: 'Let your bank messages do the typing',
      body:
          'Santim can read transaction SMS from your bank and turn them into '
          'entries you approve. Nothing is saved without your review, and you '
          'can turn it off at any time.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    Haptics.commit();
    context.read<PrefsState>().completeOnboarding();
  }

  void _next() {
    if (_page == _pages.length - 1) {
      _finish();
      return;
    }
    Haptics.select();
    _controller.nextPage(duration: Motion.enter, curve: Motion.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final last = _page == _pages.length - 1;

    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: S.md,
                  vertical: S.sm,
                ),
                child: TextButton(
                  onPressed: _finish,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    foregroundColor: t.mutedForeground,
                  ),
                  child: const Text('Skip'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) {
                  Haptics.select();
                  setState(() => _page = i);
                },
                itemBuilder: (context, i) => _PageView(page: _pages[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: Motion.fast,
                    curve: Motion.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _page ? t.primary : t.border,
                      borderRadius: BorderRadius.circular(R.pill),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(S.xl, S.xl, S.xl, S.xl),
              child: AppButton(
                label: last ? 'Get started' : 'Next',
                icon: last ? Icons.check_rounded : Icons.arrow_forward_rounded,
                size: BtnSize.lg,
                expand: true,
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Which illustration [OnboardingArt] draws.
enum OnboardingArtKind { wallets, plans, capture }

class _Page {
  const _Page({required this.art, required this.title, required this.body});
  final OnboardingArtKind art;
  final String title;
  final String body;
}

class _PageView extends StatelessWidget {
  const _PageView({required this.page});
  final _Page page;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 190,
            child: FadeInUp(child: OnboardingArt(art: page.art)),
          ),
          const Gap(S.huge),
          FadeInUp(
            delay: const Duration(milliseconds: 80),
            child: Text(
              page.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppType.figure,
                fontWeight: W.bold,
                height: 1.2,
                letterSpacing: -0.5,
                color: t.foreground,
              ),
            ),
          ),
          const Gap(S.md),
          FadeInUp(
            delay: const Duration(milliseconds: 140),
            child: Text(
              page.body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppType.body,
                height: 1.55,
                color: t.mutedForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Drawn rather than shipped as images so the art recolours with the theme and
/// adds nothing to the APK.
class OnboardingArt extends StatelessWidget {
  const OnboardingArt({super.key, required this.art});
  final OnboardingArtKind art;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return CustomPaint(
      size: const Size(double.infinity, 190),
      painter: _ArtPainter(
        art: art,
        primary: t.primary,
        accent: t.accent,
        surface: t.surfaceMuted,
        line: t.border,
        muted: t.mutedForeground,
      ),
    );
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter({
    required this.art,
    required this.primary,
    required this.accent,
    required this.surface,
    required this.line,
    required this.muted,
  });

  final OnboardingArtKind art;
  final Color primary;
  final Color accent;
  final Color surface;
  final Color line;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Soft brand wash behind every illustration.
    canvas.drawCircle(
      Offset(cx, cy),
      86,
      Paint()
        ..shader = RadialGradient(
          colors: [
            primary.withValues(alpha: 0.16),
            primary.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: 86)),
    );

    final fill = Paint()..color = surface;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = line;
    final brand = Paint()..color = primary;

    switch (art) {
      case OnboardingArtKind.wallets:
        // Three stacked cards, fanned.
        for (var i = 2; i >= 0; i--) {
          canvas.save();
          canvas.translate(cx, cy + 10 - i * 20);
          canvas.rotate((i - 1) * 0.07);
          final rect = RRect.fromRectAndRadius(
            const Rect.fromLTWH(-84, -26, 168, 54),
            const Radius.circular(12),
          );
          canvas.drawRRect(rect, i == 0 ? brand : fill);
          canvas.drawRRect(rect, stroke);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(-68, -8, 42, 8),
              const Radius.circular(4),
            ),
            Paint()
              ..color = (i == 0 ? Colors.white : muted).withValues(alpha: 0.55),
          );
          canvas.restore();
        }

      case OnboardingArtKind.plans:
        // Envelopes filling to different levels.
        for (var i = 0; i < 3; i++) {
          final x = cx - 74 + i * 74.0;
          final rect = RRect.fromRectAndRadius(
            Rect.fromLTWH(x - 28, cy - 44, 56, 88),
            const Radius.circular(10),
          );
          canvas.drawRRect(rect, fill);
          canvas.drawRRect(rect, stroke);

          final level = [0.75, 0.45, 0.95][i];
          canvas.save();
          canvas.clipRRect(rect);
          canvas.drawRect(
            Rect.fromLTWH(x - 28, cy + 44 - 88 * level, 56, 88 * level),
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [primary, accent],
              ).createShader(Rect.fromLTWH(x - 28, cy - 44, 56, 88)),
          );
          canvas.restore();
        }

      case OnboardingArtKind.capture:
        // A message bubble turning into a ledger row.
        final bubble = RRect.fromRectAndCorners(
          Rect.fromLTWH(cx - 92, cy - 62, 128, 56),
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomRight: const Radius.circular(14),
          bottomLeft: const Radius.circular(4),
        );
        canvas.drawRRect(bubble, fill);
        canvas.drawRRect(bubble, stroke);
        for (var i = 0; i < 2; i++) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(cx - 78, cy - 46 + i * 16, i == 0 ? 96 : 62, 7),
              const Radius.circular(4),
            ),
            Paint()..color = muted.withValues(alpha: 0.4),
          );
        }

        // Arrow down into the row.
        canvas.drawLine(Offset(cx, cy + 2), Offset(cx, cy + 22), stroke);
        canvas.drawLine(Offset(cx - 6, cy + 15), Offset(cx, cy + 22), stroke);
        canvas.drawLine(Offset(cx + 6, cy + 15), Offset(cx, cy + 22), stroke);

        final row = RRect.fromRectAndRadius(
          Rect.fromLTWH(cx - 46, cy + 32, 138, 40),
          const Radius.circular(12),
        );
        canvas.drawRRect(row, fill);
        canvas.drawRRect(row, stroke);
        canvas.drawCircle(Offset(cx - 26, cy + 52), 12, brand);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - 6, cy + 48, 60, 8),
            const Radius.circular(4),
          ),
          Paint()..color = muted.withValues(alpha: 0.45),
        );
    }
  }

  @override
  bool shouldRepaint(_ArtPainter old) =>
      old.art != art || old.primary != primary;
}
