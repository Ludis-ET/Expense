import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../state/auth_state.dart';
import '../../state/prefs_state.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';

/// Login and register in one screen. The web app splits them across two routes
/// behind a shared `AuthShell`; on a phone a single switchable card avoids a
/// full page transition for what is a two-field difference.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _register = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_register && _name.text.trim().length < 2) return 'Tell us your name.';
    final email = _email.text.trim();
    if (!email.contains('@') || !email.contains('.'))
      return 'Enter a valid email address.';
    if (_password.text.length < 8)
      return 'Password must be at least 8 characters.';
    return null;
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = context.read<AuthState>();
    try {
      if (_register) {
        await auth.register(_name.text, _email.text, _password.text);
      } else {
        await auth.login(_email.text, _password.text);
      }
      // The shell swaps to the app on the auth notification; nothing to do here.
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final prefs = context.watch<PrefsState>();

    return Scaffold(
      backgroundColor: t.background,
      resizeToAvoidBottomInset: true,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: t.isDark
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
              ),
        child: MeshBackground(
          intensity: 1.2,
          child: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  right: 8,
                  top: 6,
                  child: IconPill(
                    icon: Theme.of(context).brightness == Brightness.dark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    onTap: () {
                      final brightness = Theme.of(context).brightness;
                      // Always flip the *effective* look so System+dark OS still
                      // responds on the first tap.
                      prefs.setThemeMode(
                        brightness == Brightness.dark
                            ? ThemeMode.light
                            : ThemeMode.dark,
                      );
                    },
                  ),
                ),
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 56, 20, 32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FadeInUp(
                            child: Row(
                              children: [
                                const BrandMark(size: 44),
                                const GapX(S.md),
                                const BrandWord(fontSize: AppType.figure),
                              ],
                            ),
                          ),
                          const Gap(S.xxl),
                          FadeInUp(
                            delay: const Duration(milliseconds: 60),
                            child: _Hero(register: _register),
                          ),
                          const Gap(S.xl),
                          FadeInUp(
                            delay: const Duration(milliseconds: 120),
                            child: GlassCard(
                              padding: const EdgeInsets.all(S.xl),
                              radius: R.xl,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    _register
                                        ? 'Create your account'
                                        : 'Welcome back',
                                    style: TextStyle(
                                      fontSize: AppType.heading,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.5,
                                      color: t.foreground,
                                    ),
                                  ),
                                  const Gap(S.xxs),
                                  Muted(
                                    _register
                                        ? 'Start tracking every birr today.'
                                        : 'Sign in to your money.',
                                    size: 13.5,
                                  ),
                                  const Gap(S.xl),
                                  AnimatedSize(
                                    duration: Motion.fast,
                                    curve: Motion.easeOut,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (_register) ...[
                                          AppTextField(
                                            controller: _name,
                                            label: 'Name',
                                            placeholder: 'Abebe Bekele',
                                            prefixIcon: Icons.person_outline,
                                            textCapitalization:
                                                TextCapitalization.words,
                                            textInputAction:
                                                TextInputAction.next,
                                          ),
                                          const Gap(S.md),
                                        ],
                                        AppTextField(
                                          controller: _email,
                                          label: 'Email',
                                          placeholder: 'you@example.com',
                                          prefixIcon: Icons.alternate_email,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          textCapitalization:
                                              TextCapitalization.none,
                                          textInputAction: TextInputAction.next,
                                        ),
                                        const Gap(S.md),
                                        AppTextField(
                                          controller: _password,
                                          label: 'Password',
                                          placeholder: '••••••••',
                                          prefixIcon: Icons.lock_outline,
                                          obscure: _obscure,
                                          textCapitalization:
                                              TextCapitalization.none,
                                          textInputAction: TextInputAction.done,
                                          onSubmitted: (_) => _submit(),
                                          suffix: IconButton(
                                            icon: Icon(
                                              _obscure
                                                  ? Icons.visibility_outlined
                                                  : Icons
                                                        .visibility_off_outlined,
                                              size: 18,
                                              color: t.mutedForeground,
                                            ),
                                            onPressed: () => setState(
                                              () => _obscure = !_obscure,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_error != null) ...[
                                    const Gap(S.md),
                                    _ErrorBanner(message: _error!),
                                  ],
                                  const Gap(S.xl),
                                  AppButton(
                                    label: _register
                                        ? 'Create account'
                                        : 'Sign in',
                                    icon: Icons.arrow_forward,
                                    size: BtnSize.lg,
                                    expand: true,
                                    loading: _loading,
                                    onPressed: _loading ? null : _submit,
                                  ),
                                  const Gap(S.lg),
                                  Center(
                                    child: GestureDetector(
                                      onTap: () => setState(() {
                                        _register = !_register;
                                        _error = null;
                                      }),
                                      behavior: HitTestBehavior.opaque,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: S.xxs,
                                        ),
                                        child: RichText(
                                          text: TextSpan(
                                            style: TextStyle(
                                              fontSize: AppType.bodySm,
                                              color: t.mutedForeground,
                                            ),
                                            children: [
                                              TextSpan(
                                                text: _register
                                                    ? 'Already have an account? '
                                                    : "Don't have an account? ",
                                              ),
                                              TextSpan(
                                                text: _register
                                                    ? 'Sign in'
                                                    : 'Create one',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: t.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Gap(S.xl),
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

/// The gradient panel that stands in for the web app's left brand column.
class _Hero extends StatelessWidget {
  const _Hero({required this.register});
  final bool register;

  @override
  Widget build(BuildContext context) {
    return GradientHero(
      padding: const EdgeInsets.all(S.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Know where every birr goes.',
            style: TextStyle(
              fontSize: AppType.heading,
              height: 1.3,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
          const Gap(S.sm),
          Text(
            'Track income and spending, set budgets, save towards goals, '
            'and get insights   all private to you.',
            style: TextStyle(
              fontSize: AppType.bodySm,
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          const Gap(S.lg),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _HeroChip(
                icon: Icons.savings_outlined,
                label: 'Budget envelopes',
              ),
              _HeroChip(icon: Icons.insights_outlined, label: 'Analytics'),
              _HeroChip(icon: Icons.lock_outline, label: 'Private'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GlassChip(
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.xs),
      radius: R.sm,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white.withValues(alpha: 0.9)),
          const GapX(S.xxs),
          Text(
            label,
            style: const TextStyle(
              fontSize: AppType.caption,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return FadeInUp(
      offset: 4,
      duration: Motion.fast,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.md),
        decoration: BoxDecoration(
          color: t.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: t.danger.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: t.danger),
            const GapX(S.sm),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: AppType.bodySm,
                  height: 1.4,
                  color: t.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
