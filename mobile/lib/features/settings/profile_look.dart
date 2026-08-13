import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/haptics.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../models/models.dart';
import '../../state/auth_state.dart';
import '../../widgets/ui.dart';

/// The profile header: banner, picture, name.
class ProfileHeaderCard extends StatelessWidget {
  const ProfileHeaderCard({
    super.key,
    required this.user,
    required this.onEditProfile,
    required this.onEditLook,
  });

  final User? user;
  final VoidCallback onEditProfile;
  final VoidCallback onEditLook;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final name = user?.name ?? '';

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            ProfileBanner(
              bannerId: user?.bannerId,
              seed: name,
              height: 118,
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(S.sm),
                  child: _GlassButton(
                    icon: Icons.palette_outlined,
                    label: 'Change look',
                    onTap: onEditLook,
                  ),
                ),
              ),
            ),
            // Overlapping the banner's lower edge is what makes it read as a
            // profile rather than a picture with a header above it.
            Positioned(
              left: S.lg,
              bottom: -30,
              child: GestureDetector(
                onTap: onEditLook,
                child: ProfileAvatar(
                  avatarId: user?.avatarId,
                  name: name.isEmpty ? '?' : name,
                  size: 76,
                  ring: t.surface,
                ),
              ),
            ),
          ],
        ),
        const Gap(38),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.heading,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      color: t.foreground,
                    ),
                  ),
                  Muted(user?.email ?? '', size: 12.5, maxLines: 1),
                ],
              ),
            ),
            IconButton(
              onPressed: onEditProfile,
              icon: Icon(Icons.edit_outlined, size: 18, color: t.mutedForeground),
              tooltip: 'Edit profile',
            ),
          ],
        ),
      ],
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(R.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white),
              const GapX(S.xs),
              Text(
                label,
                style: const TextStyle(
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pick a picture and a banner.
///
/// Both choices preview live at the top of the sheet, because the point of
/// choosing a face is seeing it on your own banner rather than in a grid cell.
Future<void> showProfileLookPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ProfileLookSheet(),
  );
}

class _ProfileLookSheet extends StatefulWidget {
  const _ProfileLookSheet();

  @override
  State<_ProfileLookSheet> createState() => _ProfileLookSheetState();
}

class _ProfileLookSheetState extends State<_ProfileLookSheet> {
  String? _avatarId;
  String? _bannerId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthState>().user;
    _avatarId = user?.avatarId;
    _bannerId = user?.bannerId;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    Haptics.commit();
    try {
      await context.read<AuthState>().updateProfile({
        'avatarId': _avatarId,
        'bannerId': _bannerId,
      });
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      Haptics.reject();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiError ? e.message : 'Could not save that.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final name = context.watch<AuthState>().user?.name ?? '';

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(R.xl)),
        ),
        child: Column(
          children: [
            const Gap(S.sm),
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: t.border,
                  borderRadius: BorderRadius.circular(R.pill),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(S.lg, S.lg, S.lg, S.lg),
                children: [
                  // Live preview. Choosing a face only means something on the
                  // banner it will actually sit on.
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ProfileBanner(
                        bannerId: _bannerId,
                        seed: name,
                        height: 104,
                      ),
                      Positioned(
                        left: S.lg,
                        bottom: -26,
                        child: ProfileAvatar(
                          avatarId: _avatarId,
                          name: name.isEmpty ? '?' : name,
                          size: 68,
                          ring: t.surface,
                        ),
                      ),
                    ],
                  ),
                  const Gap(40),

                  SectionLabel('PICTURE'),
                  const Gap(S.sm),
                  GridView.count(
                    crossAxisCount: 6,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: S.sm,
                    crossAxisSpacing: S.sm,
                    children: [
                      for (final preset in avatarPresets)
                        _Choice(
                          selected: _avatarId == preset.id,
                          onTap: () {
                            Haptics.select();
                            setState(() => _avatarId = preset.id);
                          },
                          child: ProfileAvatar(
                            avatarId: preset.id,
                            name: name,
                            size: 44,
                          ),
                        ),
                    ],
                  ),

                  const Gap(S.lg),
                  SectionLabel('BANNER'),
                  const Gap(S.sm),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: S.sm,
                    crossAxisSpacing: S.sm,
                    childAspectRatio: 2.1,
                    children: [
                      for (final preset in bannerPresets)
                        _Choice(
                          selected: _bannerId == preset.id,
                          radius: R.md,
                          onTap: () {
                            Haptics.select();
                            setState(() => _bannerId = preset.id);
                          },
                          child: ProfileBanner(
                            bannerId: preset.id,
                            height: 60,
                            borderRadius: BorderRadius.circular(R.md),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(S.lg, S.sm, S.lg, S.md),
                child: AppButton(
                  label: 'Save',
                  loading: _saving,
                  onPressed: _save,
                  expand: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A selectable tile. The ring is the whole affordance - a checkmark over a face
/// would cover the thing being chosen.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.child,
    required this.selected,
    required this.onTap,
    this.radius = 999,
  });

  final Widget child;
  final bool selected;
  final VoidCallback onTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        curve: Motion.easeOut,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: selected ? t.primary : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: Center(child: child),
      ),
    );
  }
}
