import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/layout.dart';
import '../../models/models.dart';
import '../../widgets/ui.dart';

/// The learning hub. Suggestions at the top are data-driven — they read your
/// own figures — and the guides underneath are static explainers.
class GuidesScreen extends StatefulWidget {
  const GuidesScreen({super.key});

  @override
  State<GuidesScreen> createState() => _GuidesScreenState();
}

class _GuidesScreenState extends State<GuidesScreen> {
  GuidesOverview? _data;
  bool _loading = true;
  Object? _error;
  String? _category;

  static const _categories = <String, String>{
    'getting-started': 'Getting started',
    'saving': 'Saving',
    'spending': 'Spending',
    'debt': 'Debt',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = context.read<ApiClient>();
      final results = await Future.wait([
        api.get<Map<String, dynamic>>('/guides'),
        api.get<Map<String, dynamic>>('/guides/for-you'),
      ]);
      if (!mounted) return;
      final base = GuidesOverview.fromJson(results[0] as Map<String, dynamic>);
      final forYou = results[1] as Map<String, dynamic>?;
      final personalised = forYou == null
          ? const <GuideSuggestion>[]
          : mapList(forYou['suggestions'], GuideSuggestion.fromJson);
      setState(() {
        _data = GuidesOverview(
          guides: base.guides,
          // `/guides/for-you` is the personalised list; fall back to whatever
          // the overview carried if it comes back empty.
          suggestions: personalised.isEmpty ? base.suggestions : personalised,
        );
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final data = _data;
    final guides = data == null
        ? const <Guide>[]
        : _category == null
            ? data.guides
            : data.guides.where((g) => g.category == _category).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          'Guides',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.foreground),
        ),
      ),
      body: MeshBackground(
        showGrid: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: t.primary,
          backgroundColor: t.surface,
          child: ListView(
            padding: EdgeInsets.fromLTRB(14, 4, 14, ShellLayout.bottomClearance(context)),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (_loading && data == null)
                const PageLoader(rows: 4)
              else if (_error != null && data == null)
                ErrorState(
                  message: _error is ApiError
                      ? (_error as ApiError).message
                      : 'Could not load the guides.',
                  onRetry: _load,
                )
              else if (data != null) ...[
                if (data.suggestions.isNotEmpty) ...[
                  SectionLabel('FOR YOU'),
                  for (var i = 0; i < data.suggestions.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 11),
                      child: FadeInUp.staggered(
                        index: i,
                        child: _SuggestionCard(
                          suggestion: data.suggestions[i],
                          guides: data.guides,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                ],

                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _Chip(
                        label: 'All',
                        active: _category == null,
                        onTap: () => setState(() => _category = null),
                      ),
                      for (final entry in _categories.entries) ...[
                        const SizedBox(width: 8),
                        _Chip(
                          label: entry.value,
                          active: _category == entry.key,
                          onTap: () => setState(() => _category = entry.key),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (guides.isEmpty)
                  const EmptyState(title: 'Nothing here yet', compact: true)
                else
                  for (var i = 0; i < guides.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 11),
                      child: FadeInUp.staggered(
                        index: i,
                        child: _GuideCard(guide: guides[i]),
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: active ? t.primary.withValues(alpha: 0.12) : t.surface,
          borderRadius: BorderRadius.circular(R.pill),
          border: Border.all(color: active ? t.primary.withValues(alpha: 0.35) : t.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? t.primary : t.foreground,
          ),
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.suggestion, required this.guides});

  final GuideSuggestion suggestion;
  final List<Guide> guides;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final (tone, icon) = switch (suggestion.tone) {
      'success' => (t.success, Icons.check_circle_outline),
      'warning' => (t.warning, Icons.warning_amber_rounded),
      _ => (t.primary, Icons.lightbulb_outline),
    };

    final linked = suggestion.guideId == null
        ? null
        : guides.where((g) => g.id == suggestion.guideId).firstOrNull;

    return GlassCard(
      padding: const EdgeInsets.all(15),
      tint: tone,
      opacity: 0.09,
      borderColor: tone.withValues(alpha: 0.25),
      onTap: linked == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => GuideReader(guide: linked)),
              ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: icon, color: tone, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.foreground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  suggestion.body,
                  style: TextStyle(fontSize: 12.5, height: 1.5, color: t.mutedForeground),
                ),
                if (linked != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        suggestion.cta ?? 'Read the guide',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: tone,
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 15, color: tone),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.guide});
  final Guide guide;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GuideReader(guide: guide)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: t.surfaceMuted.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(R.md),
            ),
            alignment: Alignment.center,
            child: Text(guide.emoji, style: const TextStyle(fontSize: 21)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  guide.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: t.foreground,
                  ),
                ),
                const SizedBox(height: 3),
                Muted(guide.tagline, size: 12, maxLines: 2, height: 1.35),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.schedule, size: 11, color: t.mutedForeground),
                    const SizedBox(width: 4),
                    Muted('${guide.readMins} min read', size: 10.5),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: t.mutedForeground),
        ],
      ),
    );
  }
}

/// A guide, rendered as a readable article.
class GuideReader extends StatelessWidget {
  const GuideReader({super.key, required this.guide});
  final Guide guide;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          guide.emoji,
          style: const TextStyle(fontSize: 20),
        ),
      ),
      body: MeshBackground(
        showGrid: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 48),
          children: [
            FadeInUp(
              child: Text(
                guide.title,
                style: TextStyle(
                  fontSize: 25,
                  height: 1.25,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.6,
                  color: t.foreground,
                ),
              ),
            ),
            const SizedBox(height: 8),
            FadeInUp(
              delay: const Duration(milliseconds: 50),
              child: Text(
                guide.tagline,
                style: TextStyle(fontSize: 14.5, height: 1.5, color: t.mutedForeground),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                AppBadge(
                  guide.category.replaceAll('-', ' '),
                  tone: BadgeTone.primary,
                ),
                const SizedBox(width: 8),
                Muted('${guide.readMins} min read', size: 11.5),
              ],
            ),
            const SizedBox(height: 24),
            for (var i = 0; i < guide.sections.length; i++)
              FadeInUp.staggered(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guide.sections[i].heading,
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: t.foreground,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _Markdown(text: guide.sections[i].body),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Just enough Markdown for guide copy: paragraphs, bullets, and **bold**.
class _Markdown extends StatelessWidget {
  const _Markdown({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final blocks = text.split('\n').where((l) => l.trim().isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: line.trimLeft().startsWith('- ') || line.trimLeft().startsWith('* ')
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 7, right: 10),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: t.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      Expanded(child: _rich(context, line.trimLeft().substring(2))),
                    ],
                  )
                : _rich(context, line),
          ),
      ],
    );
  }

  Widget _rich(BuildContext context, String line) {
    final t = context.t;
    final spans = <TextSpan>[];
    // Split on **bold** runs, keeping the delimiters out of the output.
    final pattern = RegExp(r'\*\*(.+?)\*\*');
    var index = 0;
    for (final match in pattern.allMatches(line)) {
      if (match.start > index) {
        spans.add(TextSpan(text: line.substring(index, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ));
      index = match.end;
    }
    if (index < line.length) spans.add(TextSpan(text: line.substring(index)));

    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 14, height: 1.65, color: t.mutedForeground),
        children: spans.isEmpty ? [TextSpan(text: line)] : spans,
      ),
    );
  }
}
