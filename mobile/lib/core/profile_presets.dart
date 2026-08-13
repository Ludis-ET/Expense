/// Profile pictures and banners.
///
/// Santim does not take photo uploads - no camera roll permission, no image
/// hosting, nothing personal leaving the phone. Instead every account gets one
/// of twelve drawn faces and one of ten banners, assigned at signup and
/// changeable any time. Ids match the backend catalog in `profile-presets.ts`
/// and the web one in `profile-presets.tsx`, so the same account looks the same
/// on every surface.
///
/// The art is painted rather than shipped as assets: a dozen faces as PNGs
/// would be a megabyte of APK for something a few gradients and circles say
/// just as well, at any size, in any theme.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Keep in sync with the backend catalog.
const avatarIds = <String>[
  'ember',
  'lagoon',
  'meadow',
  'dusk',
  'citrus',
  'blush',
  'slate',
  'cocoa',
  'ocean',
  'sunrise',
  'mint',
  'berry',
];

const bannerIds = <String>[
  'aurora',
  'terrace',
  'monsoon',
  'savanna',
  'glacier',
  'dusk-wave',
  'citrus-mist',
  'rainforest',
  'coral-reef',
  'night-market',
];

class AvatarPreset {
  const AvatarPreset({
    required this.id,
    required this.label,
    required this.background,
    required this.skin,
    required this.hair,
    required this.accent,
  });

  final String id;
  final String label;

  /// Two or three stops, painted top-left to bottom-right.
  final List<Color> background;
  final Color skin;
  final Color hair;

  /// A small mark in the corner, so the twelve are told apart at 32px.
  final Color accent;
}

const _avatars = <AvatarPreset>[
  AvatarPreset(
    id: 'ember',
    label: 'Ember',
    background: [Color(0xFFFB923C), Color(0xFFEF4444), Color(0xFF9F1239)],
    skin: Color(0xFFFECACA),
    hair: Color(0xFF7F1D1D),
    accent: Color(0xFFFBBF24),
  ),
  AvatarPreset(
    id: 'lagoon',
    label: 'Lagoon',
    background: [Color(0xFF22D3EE), Color(0xFF0EA5E9), Color(0xFF0369A1)],
    skin: Color(0xFFBAE6FD),
    hair: Color(0xFF0C4A6E),
    accent: Color(0xFFE0F2FE),
  ),
  AvatarPreset(
    id: 'meadow',
    label: 'Meadow',
    background: [Color(0xFF86EFAC), Color(0xFF22C55E), Color(0xFF15803D)],
    skin: Color(0xFFDCFCE7),
    hair: Color(0xFF14532D),
    accent: Color(0xFFFDE047),
  ),
  AvatarPreset(
    id: 'dusk',
    label: 'Dusk',
    background: [Color(0xFFA5B4FC), Color(0xFF6366F1), Color(0xFF312E81)],
    skin: Color(0xFFE0E7FF),
    hair: Color(0xFF1E1B4B),
    accent: Color(0xFFF8FAFC),
  ),
  AvatarPreset(
    id: 'citrus',
    label: 'Citrus',
    background: [Color(0xFFFDE047), Color(0xFFF59E0B), Color(0xFFD97706)],
    skin: Color(0xFFFEF3C7),
    hair: Color(0xFF78350F),
    accent: Color(0xFF65A30D),
  ),
  AvatarPreset(
    id: 'blush',
    label: 'Blush',
    background: [Color(0xFFFDA4AF), Color(0xFFF43F5E), Color(0xFFBE123C)],
    skin: Color(0xFFFFE4E6),
    hair: Color(0xFF881337),
    accent: Color(0xFFFB7185),
  ),
  AvatarPreset(
    id: 'slate',
    label: 'Slate',
    background: [Color(0xFF94A3B8), Color(0xFF475569), Color(0xFF0F172A)],
    skin: Color(0xFFE2E8F0),
    hair: Color(0xFF020617),
    accent: Color(0xFF38BDF8),
  ),
  AvatarPreset(
    id: 'cocoa',
    label: 'Cocoa',
    background: [Color(0xFFD6A57A), Color(0xFFA16207), Color(0xFF713F12)],
    skin: Color(0xFFF5D0A9),
    hair: Color(0xFF451A03),
    accent: Color(0xFFFDE68A),
  ),
  AvatarPreset(
    id: 'ocean',
    label: 'Ocean',
    background: [Color(0xFF67E8F9), Color(0xFF0891B2), Color(0xFF164E63)],
    skin: Color(0xFFCFFAFE),
    hair: Color(0xFF083344),
    accent: Color(0xFF99F6E4),
  ),
  AvatarPreset(
    id: 'sunrise',
    label: 'Sunrise',
    background: [Color(0xFFFECDD3), Color(0xFFFB7185), Color(0xFFF97316)],
    skin: Color(0xFFFFF1F2),
    hair: Color(0xFF9A3412),
    accent: Color(0xFFFFEDD5),
  ),
  AvatarPreset(
    id: 'mint',
    label: 'Mint',
    background: [Color(0xFFA7F3D0), Color(0xFF34D399), Color(0xFF0F766E)],
    skin: Color(0xFFECFDF5),
    hair: Color(0xFF064E3B),
    accent: Color(0xFFBBF7D0),
  ),
  AvatarPreset(
    id: 'berry',
    label: 'Berry',
    background: [Color(0xFFD8B4FE), Color(0xFFA855F7), Color(0xFF6B21A8)],
    skin: Color(0xFFF3E8FF),
    hair: Color(0xFF3B0764),
    accent: Color(0xFFF0ABFC),
  ),
];

class BannerPreset {
  const BannerPreset({
    required this.id,
    required this.label,
    required this.colors,
    required this.glow,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });

  final String id;
  final String label;
  final List<Color> colors;

  /// The soft light that stops a flat gradient looking like a placeholder.
  final Color glow;
  final Alignment begin;
  final Alignment end;
}

const _banners = <BannerPreset>[
  BannerPreset(
    id: 'aurora',
    label: 'Aurora',
    colors: [Color(0xFF064E3B), Color(0xFF0F766E), Color(0xFF1E3A8A)],
    glow: Color(0xFF34D399),
  ),
  BannerPreset(
    id: 'terrace',
    label: 'Terrace',
    colors: [Color(0xFFFEF3C7), Color(0xFFFDBA74), Color(0xFF9A3412)],
    glow: Color(0xFFFDE68A),
    begin: Alignment.topCenter,
    end: Alignment.bottomRight,
  ),
  BannerPreset(
    id: 'monsoon',
    label: 'Monsoon',
    colors: [Color(0xFF0C4A6E), Color(0xFF075985), Color(0xFF164E63)],
    glow: Color(0xFF7DD3FC),
  ),
  BannerPreset(
    id: 'savanna',
    label: 'Savanna',
    colors: [Color(0xFFFDE68A), Color(0xFFF59E0B), Color(0xFF78350F)],
    glow: Color(0xFFFEF3C7),
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  ),
  BannerPreset(
    id: 'glacier',
    label: 'Glacier',
    colors: [Color(0xFFE0F2FE), Color(0xFF7DD3FC), Color(0xFF0284C7)],
    glow: Color(0xFFFFFFFF),
  ),
  BannerPreset(
    id: 'dusk-wave',
    label: 'Dusk wave',
    colors: [Color(0xFF312E81), Color(0xFF6D28D9), Color(0xFFDB2777)],
    glow: Color(0xFFFB7185),
  ),
  BannerPreset(
    id: 'citrus-mist',
    label: 'Citrus mist',
    colors: [Color(0xFF65A30D), Color(0xFF16A34A), Color(0xFF0F766E)],
    glow: Color(0xFFFEF08A),
  ),
  BannerPreset(
    id: 'rainforest',
    label: 'Rainforest',
    colors: [Color(0xFF14532D), Color(0xFF166534), Color(0xFF115E59)],
    glow: Color(0xFF4ADE80),
  ),
  BannerPreset(
    id: 'coral-reef',
    label: 'Coral reef',
    colors: [Color(0xFF7C2D12), Color(0xFFEA580C), Color(0xFF0E7490)],
    glow: Color(0xFFFDBA74),
  ),
  BannerPreset(
    id: 'night-market',
    label: 'Night market',
    colors: [Color(0xFF1E1B4B), Color(0xFF4C1D95), Color(0xFF0F172A)],
    glow: Color(0xFFFBBF24),
  ),
];

List<AvatarPreset> get avatarPresets => _avatars;
List<BannerPreset> get bannerPresets => _banners;

/// The preset for an id, falling back to a stable one derived from the name so
/// an account created before the catalog existed still looks deliberate.
AvatarPreset avatarPreset(String? id, {String seed = ''}) {
  for (final a in _avatars) {
    if (a.id == id) return a;
  }
  final index = (seed.isEmpty ? 0 : seed.hashCode.abs()) % _avatars.length;
  return _avatars[index];
}

BannerPreset bannerPreset(String? id, {String seed = ''}) {
  for (final b in _banners) {
    if (b.id == id) return b;
  }
  final index = (seed.isEmpty ? 0 : seed.hashCode.abs()) % _banners.length;
  return _banners[index];
}

// ---------------------------------------------------------------------------
// Painting
// ---------------------------------------------------------------------------

/// A drawn face. Simple by design: at 28px in a list row the only things that
/// survive are the silhouette and the colour, so that is what carries identity.
class _FacePainter extends CustomPainter {
  const _FacePainter(this.preset);

  final AvatarPreset preset;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;

    // Hair, as a dome sitting behind the face.
    final hair = Paint()..color = preset.hair;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, h * 0.52), radius: w * 0.30),
      math.pi,
      math.pi,
      true,
      hair,
    );

    // Face.
    canvas.drawCircle(
      Offset(cx, h * 0.55),
      w * 0.26,
      Paint()..color = preset.skin,
    );

    // Fringe, overlapping the top of the face so the two read as one head.
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: Offset(cx, h * 0.55), radius: w * 0.26)),
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, h * 0.44), radius: w * 0.27),
      math.pi,
      math.pi,
      true,
      hair,
    );
    canvas.restore();

    // Eyes and a faint smile.
    final ink = Paint()..color = const Color(0xFF1E293B);
    canvas.drawCircle(Offset(cx - w * 0.09, h * 0.55), w * 0.028, ink);
    canvas.drawCircle(Offset(cx + w * 0.09, h * 0.55), w * 0.028, ink);
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, h * 0.60), width: w * 0.18, height: w * 0.12),
      0.15,
      math.pi - 0.3,
      false,
      Paint()
        ..color = const Color(0xFF1E293B).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.022
        ..strokeCap = StrokeCap.round,
    );

    // The corner mark that tells the twelve apart in a grid.
    canvas.drawCircle(
      Offset(w * 0.78, h * 0.26),
      w * 0.075,
      Paint()..color = preset.accent.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_FacePainter old) => old.preset.id != preset.id;
}

/// The account's profile picture.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.avatarId,
    required this.name,
    this.size = 40,
    this.ring,
  });

  final String? avatarId;
  final String name;
  final double size;

  /// A border, for the overlap where the avatar sits on the banner.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final preset = avatarPreset(avatarId, seed: name);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: preset.background,
        ),
        border: ring == null ? null : Border.all(color: ring!, width: size * 0.06),
        boxShadow: [
          BoxShadow(
            color: preset.background.last.withValues(alpha: 0.35),
            blurRadius: size * 0.22,
            offset: Offset(0, size * 0.06),
          ),
        ],
      ),
      child: ClipOval(
        child: CustomPaint(painter: _FacePainter(preset), size: Size.square(size)),
      ),
    );
  }
}

/// The banner behind the profile header.
class ProfileBanner extends StatelessWidget {
  const ProfileBanner({
    super.key,
    required this.bannerId,
    this.seed = '',
    this.height = 132,
    this.borderRadius,
    this.child,
  });

  final String? bannerId;
  final String seed;
  final double height;
  final BorderRadius? borderRadius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final preset = bannerPreset(bannerId, seed: seed);
    final radius = borderRadius ?? BorderRadius.circular(20);

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: preset.begin,
                  end: preset.end,
                  colors: preset.colors,
                ),
              ),
            ),
            // One soft light source, off-centre. A flat gradient looks unfinished;
            // this is what makes it read as a scene.
            Positioned(
              left: -height * 0.35,
              top: -height * 0.55,
              child: Container(
                width: height * 1.6,
                height: height * 1.6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      preset.glow.withValues(alpha: 0.42),
                      preset.glow.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -height * 0.3,
              bottom: -height * 0.6,
              child: Container(
                width: height * 1.3,
                height: height * 1.3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.16),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // Darkened at the foot so whatever sits on top stays readable.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.28),
                  ],
                ),
              ),
            ),
            ?child,
          ],
        ),
      ),
    );
  }
}
