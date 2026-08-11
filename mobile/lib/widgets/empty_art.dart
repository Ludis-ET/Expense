import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import 'ui.dart';

/// Line illustrations for zero-data screens.
///
/// Empty states used to be a muted glyph in a dashed box   the same grey
/// square whether you had no wallets, no plans or no results. These are drawn
/// with [CustomPaint] rather than shipped as assets, so they recolour with the
/// theme, stay sharp at any density, and add nothing to the APK.
class EmptyStateArt extends StatelessWidget {
  const EmptyStateArt({super.key, required this.art, this.height = 96});

  final EmptyArt art;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return SizedBox(
      height: height,
      width: 150,
      child: CustomPaint(
        painter: _EmptyArtPainter(
          art: art,
          primary: t.primary,
          accent: t.accent,
          line: t.border,
          muted: t.mutedForeground,
          surface: t.surface,
        ),
      ),
    );
  }
}

class _EmptyArtPainter extends CustomPainter {
  _EmptyArtPainter({
    required this.art,
    required this.primary,
    required this.accent,
    required this.line,
    required this.muted,
    required this.surface,
  });

  final EmptyArt art;
  final Color primary;
  final Color accent;
  final Color line;
  final Color muted;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = line;
    final fill = Paint()..color = surface;
    final soft = Paint()..color = muted.withValues(alpha: 0.28);
    final brand = Paint()..color = primary.withValues(alpha: 0.9);

    // A faint halo keeps the drawing from floating on the muted panel.
    canvas.drawCircle(
      Offset(cx, cy),
      44,
      Paint()
        ..shader = RadialGradient(
          colors: [
            primary.withValues(alpha: 0.12),
            primary.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: 44)),
    );

    RRect box(double l, double t, double w, double h, [double r = 8]) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(l, t, w, h), Radius.circular(r));

    switch (art) {
      case EmptyArt.none:
        return;

      case EmptyArt.ledger:
        // Three list rows, the last one dimmed   "nothing logged yet".
        for (var i = 0; i < 3; i++) {
          final y = cy - 34 + i * 24.0;
          final rect = box(cx - 52, y, 104, 18, 6);
          canvas.drawRRect(rect, fill);
          canvas.drawRRect(
            rect,
            stroke..color = line.withValues(alpha: 1 - i * 0.3),
          );
          canvas.drawCircle(Offset(cx - 40, y + 9), 5, i == 0 ? brand : soft);
          canvas.drawRRect(
            box(cx - 28, y + 6, i == 0 ? 44 : 32, 6, 3),
            Paint()..color = muted.withValues(alpha: 0.3 - i * 0.08),
          );
        }
        stroke.color = line;

      case EmptyArt.wallet:
        final body = box(cx - 46, cy - 26, 92, 56, 10);
        canvas.drawRRect(body, fill);
        canvas.drawRRect(body, stroke);
        // Card slot and the clasp.
        canvas.drawRRect(box(cx - 46, cy - 12, 92, 10, 2), soft);
        canvas.drawCircle(Offset(cx + 30, cy + 6), 6, brand);
        // A coin arcing in.
        canvas.drawCircle(Offset(cx + 34, cy - 38), 10, fill);
        canvas.drawCircle(Offset(cx + 34, cy - 38), 10, stroke);
        canvas.drawCircle(Offset(cx + 34, cy - 38), 4, brand);

      case EmptyArt.plan:
        // An envelope with a filled band at the bottom.
        final env = box(cx - 44, cy - 30, 88, 62, 10);
        canvas.drawRRect(env, fill);
        canvas.save();
        canvas.clipRRect(env);
        canvas.drawRect(
          Rect.fromLTWH(cx - 44, cy + 6, 88, 26),
          Paint()
            ..shader = LinearGradient(
              colors: [primary, accent],
            ).createShader(Rect.fromLTWH(cx - 44, cy + 6, 88, 26)),
        );
        canvas.restore();
        canvas.drawRRect(env, stroke);
        // Flap.
        final flap = Path()
          ..moveTo(cx - 44, cy - 24)
          ..lineTo(cx, cy + 2)
          ..lineTo(cx + 44, cy - 24);
        canvas.drawPath(flap, stroke);

      case EmptyArt.wish:
        // A tagged gift.
        final gift = box(cx - 34, cy - 18, 68, 48, 8);
        canvas.drawRRect(gift, fill);
        canvas.drawRRect(gift, stroke);
        canvas.drawRect(Rect.fromLTWH(cx - 5, cy - 18, 10, 48), brand);
        canvas.drawRRect(box(cx - 40, cy - 28, 80, 14, 5), fill);
        canvas.drawRRect(box(cx - 40, cy - 28, 80, 14, 5), stroke);
        // Star above.
        final star = Path();
        for (var i = 0; i < 5; i++) {
          final a = -math.pi / 2 + i * 2 * math.pi / 5;
          final p = Offset(
            cx + 30 + 9 * math.cos(a),
            cy - 40 + 9 * math.sin(a),
          );
          i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
          final b = a + math.pi / 5;
          star.lineTo(cx + 30 + 4 * math.cos(b), cy - 40 + 4 * math.sin(b));
        }
        star.close();
        canvas.drawPath(star, brand);

      case EmptyArt.search:
        canvas.drawCircle(Offset(cx - 6, cy - 8), 24, fill);
        canvas.drawCircle(
          Offset(cx - 6, cy - 8),
          24,
          stroke..strokeWidth = 2.4,
        );
        canvas.drawLine(
          Offset(cx + 12, cy + 10),
          Offset(cx + 28, cy + 26),
          stroke,
        );
        stroke.strokeWidth = 1.8;
        canvas.drawRRect(box(cx - 20, cy - 12, 28, 5, 3), soft);
        canvas.drawRRect(box(cx - 20, cy - 2, 18, 5, 3), soft);

      case EmptyArt.calendar:
        final cal = box(cx - 40, cy - 30, 80, 62, 9);
        canvas.drawRRect(cal, fill);
        canvas.drawRRect(cal, stroke);
        canvas.drawRRect(box(cx - 40, cy - 30, 80, 16, 9), brand);
        canvas.drawLine(
          Offset(cx - 24, cy - 38),
          Offset(cx - 24, cy - 26),
          stroke,
        );
        canvas.drawLine(
          Offset(cx + 24, cy - 38),
          Offset(cx + 24, cy - 26),
          stroke,
        );
        for (var r = 0; r < 2; r++) {
          for (var c = 0; c < 4; c++) {
            canvas.drawRRect(
              box(cx - 30 + c * 16.0, cy - 6 + r * 16.0, 10, 10, 3),
              r == 0 && c == 1 ? brand : soft,
            );
          }
        }
    }
  }

  @override
  bool shouldRepaint(_EmptyArtPainter old) =>
      old.art != art || old.primary != primary || old.line != line;
}
