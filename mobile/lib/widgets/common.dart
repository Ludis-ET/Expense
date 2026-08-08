import 'package:flutter/material.dart';

import '../core/theme.dart';

export '../core/theme.dart' show SoftCard, BrandMark, BrandRow, GlassCard, GlassIconButton, Eyebrow, AuroraBackdrop;

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.title, {super.key, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class ShimmerBlock extends StatefulWidget {
  const ShimmerBlock({super.key, this.height = 88, this.radius = 16});

  final double height;
  final double radius;

  @override
  State<ShimmerBlock> createState() => _ShimmerBlockState();
}

class _ShimmerBlockState extends State<ShimmerBlock> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).extension<SantimColors>()!.surfaceMuted;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + _c.value * 2, 0),
              end: Alignment(1 + _c.value * 2, 0),
              colors: [
                muted,
                Theme.of(context).colorScheme.surface,
                muted,
              ],
            ),
          ),
        );
      },
    );
  }
}

class FadeIn extends StatelessWidget {
  const FadeIn({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(offset: Offset(0, (1 - value) * 10), child: child),
      ),
      child: child,
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: colors.primary, size: 26),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.muted),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

enum PillTone { good, warn, bad, neutral }

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.tone = PillTone.neutral});

  final String label;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SantimColors>()!;
    final (bg, fg) = switch (tone) {
      PillTone.good => (colors.success.withValues(alpha: 0.12), colors.success),
      PillTone.warn => (colors.warning.withValues(alpha: 0.14), colors.warning),
      PillTone.bad => (colors.danger.withValues(alpha: 0.12), colors.danger),
      PillTone.neutral => (colors.surfaceMuted, colors.muted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 11)),
    );
  }
}

void showOk(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

void showError(BuildContext context, String message) {
  final danger = Theme.of(context).extension<SantimColors>()?.danger ?? SantimTheme.danger;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: danger),
  );
}

class InfoHint extends StatelessWidget {
  const InfoHint({
    super.key,
    required this.title,
    this.message,
    this.body,
  }) : assert(message != null || body != null);

  final String title;
  final String? message;
  final String? body;

  String get _text => message ?? body ?? '';

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: title,
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(_text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it')),
          ],
        ),
      ),
      icon: const Icon(Icons.info_outline_rounded, size: 20),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.extension<SantimColors>()!.muted;
    return SoftCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title!, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader(this.title, {super.key, this.subtitle, this.actions});

  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.extension<SantimColors>()!.muted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.headlineSmall),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  ),
              ],
            ),
          ),
          ...?actions,
        ],
      ),
    );
  }
}
