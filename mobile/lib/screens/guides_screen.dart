import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/web_chrome.dart';

class GuidesScreen extends StatefulWidget {
  const GuidesScreen({super.key});

  @override
  State<GuidesScreen> createState() => _GuidesScreenState();
}

class _GuidesScreenState extends State<GuidesScreen> {
  List<Map<String, dynamic>> _guides = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<ApiClient>().get('/guides');
      List items;
      if (data is Map && data['items'] is List) {
        items = data['items'] as List;
      } else if (data is Map && data['guides'] is List) {
        items = data['guides'] as List;
      } else if (data is List) {
        items = data;
      } else {
        items = const [];
      }
      if (!mounted) return;
      setState(() {
        _guides = items.whereType<Map<String, dynamic>>().toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Could not load guides';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<SantimColors>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guides'),
        actions: const [WebTopActions()],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  ShimmerBlock(height: 100),
                  SizedBox(height: 12),
                  ShimmerBlock(height: 100),
                ],
              )
            : _error != null
                ? ListView(
                    children: [
                      EmptyState(icon: Icons.menu_book_outlined, title: 'Guides unavailable', message: _error),
                    ],
                  )
                : _guides.isEmpty
                    ? ListView(
                        children: const [
                          EmptyState(
                            icon: Icons.menu_book_outlined,
                            title: 'No guides yet',
                            message: 'Educational articles will appear here.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                        itemCount: _guides.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final g = _guides[i];
                          return SoftCard(
                            onTap: () => _openGuide(g),
                            child: Row(
                              children: [
                                Text('${g['emoji'] ?? '📖'}', style: const TextStyle(fontSize: 28)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${g['title'] ?? 'Guide'}',
                                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                      ),
                                      if (g['tagline'] != null)
                                        Text(
                                          '${g['tagline']}',
                                          style: theme.textTheme.bodySmall?.copyWith(color: colors.muted),
                                        ),
                                      if (g['readMins'] != null)
                                        Text(
                                          '${g['readMins']} min read',
                                          style: TextStyle(fontSize: 11, color: colors.muted),
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded, color: colors.muted),
                              ],
                            ),
                          );
                        },
                      ),
      ),
    );
  }

  void _openGuide(Map<String, dynamic> g) {
    final sections = ((g['sections'] as List?) ?? const []).whereType<Map<String, dynamic>>().toList();
    showSantimSheet(
      context: context,
      title: '${g['emoji'] ?? ''} ${g['title'] ?? 'Guide'}'.trim(),
      builder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (g['tagline'] != null)
            Text(
              '${g['tagline']}',
              style: TextStyle(color: Theme.of(context).extension<SantimColors>()!.muted),
            ),
          const SizedBox(height: 14),
          if (sections.isEmpty)
            Text('${g['body'] ?? g['content'] ?? 'No content.'}')
          else
            for (final s in sections) ...[
              Text(
                '${s['heading'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text('${s['body'] ?? ''}'),
              const SizedBox(height: 16),
            ],
        ],
      ),
    );
  }
}
