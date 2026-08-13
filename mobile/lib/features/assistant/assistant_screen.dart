import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/haptics.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../models/common.dart';
import '../../widgets/charts.dart';
import '../../widgets/markdown.dart';
import '../../widgets/ui.dart';
import '../settings/settings_screen.dart';

/// Ask Santim — multi-chat, server-backed, Markdown answers.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _ChatMessage {
  _ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.chart,
    this.provider,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final String id;
  final String role; // user | assistant | error
  final String content;
  final _ChartData? chart;
  final String? provider;
  final DateTime at;

  bool get fromUser => role == 'user';
  bool get failed => role == 'error';
}

class _ChartData {
  const _ChartData({
    required this.type,
    required this.title,
    required this.points,
  });
  final String type;
  final String title;
  final List<(String, double)> points;

  static _ChartData? maybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final data = asList(m['data']);
    if (data.isEmpty) return null;
    return _ChartData(
      type: asStr(m['type'], 'bar'),
      title: asStr(m['title'], ''),
      points: [
        for (final d in data) (asStr(d['label'], ''), asNum(d['value'])),
      ],
    );
  }
}

class _ConversationSummary {
  _ConversationSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.preview,
    this.messageCount = 0,
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final String? preview;
  final int messageCount;
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  String? _conversationId;
  String _title = 'New chat';
  final _messages = <_ChatMessage>[];
  List<_ConversationSummary> _history = const [];

  bool _thinking = false;
  bool _loadingThread = true;
  bool _loadingHistory = false;
  bool? _configured;

  static const _starters = [
    ('Where did most of my money go this month?', Icons.pie_chart_outline_rounded),
    ('Am I saving enough?', Icons.savings_outlined),
    ('Who still owes me money?', Icons.volunteer_activism_outlined),
    ('Which plan is closest to running out?', Icons.warning_amber_rounded),
    ('What can I cut back on?', Icons.content_cut_rounded),
    ('Summarise my Money Tab', Icons.handshake_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_checkStatus(), _loadHistory()]);
    if (!mounted) return;
    if (_history.isNotEmpty) {
      await _openConversation(_history.first.id);
    } else {
      setState(() => _loadingThread = false);
    }
  }

  Future<void> _checkStatus() async {
    try {
      final json = await context.read<ApiClient>().get<Map<String, dynamic>>(
        '/ai/status',
      );
      if (mounted) setState(() => _configured = asBool(json['configured']));
    } catch (_) {
      if (mounted) setState(() => _configured = false);
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final json = await context.read<ApiClient>().get<Map<String, dynamic>>(
        '/ai/conversations',
      );
      if (!mounted) return;
      setState(() {
        _history = [
          for (final item in asList(json['items']))
            _ConversationSummary(
              id: asStr(item['id']),
              title: asStr(item['title'], 'Chat'),
              updatedAt: DateTime.tryParse(asStr(item['updatedAt'])) ??
                  DateTime.now(),
              preview: asStrOrNull(item['preview']),
              messageCount: asInt(item['messageCount']),
            ),
        ];
        _loadingHistory = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _openConversation(String id) async {
    setState(() {
      _loadingThread = true;
      _conversationId = id;
      _messages.clear();
    });
    try {
      final json = await context.read<ApiClient>().get<Map<String, dynamic>>(
        '/ai/conversations/$id',
      );
      if (!mounted) return;
      setState(() {
        _title = asStr(json['title'], 'Chat');
        _messages
          ..clear()
          ..addAll([
            for (final m in asList(json['messages']))
              _ChatMessage(
                id: asStr(m['id']),
                role: asStr(m['role'], 'assistant'),
                content: asStr(m['content']),
                chart: _ChartData.maybe(m['chart']),
                provider: asStrOrNull(m['provider']),
                at: DateTime.tryParse(asStr(m['createdAt'])) ?? DateTime.now(),
              ),
          ]);
        _loadingThread = false;
      });
      _scrollToEnd(jump: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingThread = false);
      toast(
        context,
        e is ApiError ? e.message : 'Could not open that chat.',
      );
    }
  }

  Future<void> _newChat() async {
    Haptics.select();
    setState(() {
      _conversationId = null;
      _title = 'New chat';
      _messages.clear();
      _loadingThread = false;
    });
    _focus.requestFocus();
  }

  Future<void> _deleteConversation(String id) async {
    final ok = await confirm(
      context,
      title: 'Delete this chat?',
      message: 'The whole conversation will be removed from the server.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await context.read<ApiClient>().delete('/ai/conversations/$id');
      if (!mounted) return;
      final wasOpen = _conversationId == id;
      await _loadHistory();
      if (wasOpen) await _newChat();
      Haptics.toggle();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _ask([String? preset]) async {
    final question = (preset ?? _controller.text).trim();
    if (question.length < 2 || _thinking) return;
    final api = context.read<ApiClient>();

    final tempId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _messages.add(
        _ChatMessage(id: tempId, role: 'user', content: question),
      );
      _thinking = true;
      _controller.clear();
    });
    _scrollToEnd();

    try {
      final body = <String, dynamic>{
        'question': question,
        'persist': true,
      };
      if (_conversationId != null) body['conversationId'] = _conversationId;

      final json = await api.post<Map<String, dynamic>>('/ai/ask', body: body);
      if (!mounted) return;

      final conversationId = asStr(json['conversationId'], _conversationId ?? '');
      setState(() {
        _conversationId = conversationId.isEmpty ? _conversationId : conversationId;
        if (_title == 'New chat' && question.isNotEmpty) {
          _title = question.length > 42 ? '${question.substring(0, 41)}…' : question;
        }
        _messages.add(
          _ChatMessage(
            id: asStr(json['messageId'], 'a-$tempId'),
            role: 'assistant',
            content: asStr(json['answer'], 'No answer came back.'),
            chart: _ChartData.maybe(json['chart']),
            provider: asStrOrNull(json['provider']),
          ),
        );
        _thinking = false;
      });
      unawaited(_loadHistory());
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMessage(id: 'err-$tempId', role: 'error', content: e.message),
        );
        _thinking = false;
      });
    }
    _scrollToEnd();
  }

  void _scrollToEnd({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (jump) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(target, duration: Motion.fast, curve: Motion.easeOut);
      }
    });
  }

  Future<void> _showHistory() async {
    Haptics.select();
    await _loadHistory();
    if (!mounted) return;
    await showAppSheet<void>(
      context,
      title: 'Your chats',
      subtitle: 'Synced across your devices',
      builder: (ctx) => _HistorySheet(
        loading: _loadingHistory,
        items: _history,
        activeId: _conversationId,
        onNew: () {
          Navigator.pop(ctx);
          _newChat();
        },
        onOpen: (id) {
          Navigator.pop(ctx);
          _openConversation(id);
        },
        onDelete: (id) async {
          Navigator.pop(ctx);
          await _deleteConversation(id);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final empty = !_loadingThread && _messages.isEmpty;

    return Scaffold(
      backgroundColor: t.background,
      body: MeshBackground(
        child: SafeArea(
          child: Column(
            children: [
              _Header(
                title: _title,
                onHistory: _showHistory,
                onNew: _newChat,
                onClose: () => Navigator.of(context).maybePop(),
              ),
              if (_configured == false)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: _SetupBanner(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ),
              Expanded(
                child: _loadingThread
                    ? const Center(child: PageLoader(rows: 3, hero: false))
                    : empty
                        ? _EmptyState(
                            starters: _starters,
                            onAsk: _ask,
                          )
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
                            itemCount: _messages.length + (_thinking ? 1 : 0),
                            itemBuilder: (context, i) {
                              if (i == _messages.length) {
                                return const _ThinkingBubble();
                              }
                              return _MessageBubble(message: _messages[i]);
                            },
                          ),
              ),
              _Composer(
                controller: _controller,
                focusNode: _focus,
                thinking: _thinking,
                enabled: _configured != false,
                onAsk: _ask,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.onHistory,
    required this.onNew,
    required this.onClose,
  });

  final String title;
  final VoidCallback onHistory;
  final VoidCallback onNew;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
      child: Row(
        children: [
          IconPill(
            icon: Icons.close_rounded,
            background: Colors.transparent,
            onTap: onClose,
          ),
          IconPill(
            icon: Icons.menu_rounded,
            background: Colors.transparent,
            tooltip: 'Chat history',
            onTap: onHistory,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'Ask Santim',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: t.mutedForeground,
                  ),
                ),
                const Gap(2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppType.bodySm,
                    fontWeight: FontWeight.w700,
                    color: t.foreground,
                  ),
                ),
              ],
            ),
          ),
          IconPill(
            icon: Icons.edit_square,
            background: Colors.transparent,
            tooltip: 'New chat',
            onTap: onNew,
          ),
          const GapX(4),
        ],
      ),
    );
  }
}

class _SetupBanner extends StatelessWidget {
  const _SetupBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AppCard(
      padding: const EdgeInsets.all(S.lg),
      color: t.warning.withValues(alpha: 0.08),
      borderColor: t.warning.withValues(alpha: 0.28),
      onTap: onTap,
      child: Row(
        children: [
          Icon(Icons.key_outlined, size: 18, color: t.warning),
          const GapX(S.md),
          Expanded(
            child: Text(
              'Add an AI provider key in Settings to start chatting.',
              style: TextStyle(
                fontSize: AppType.label,
                height: 1.4,
                color: t.foreground,
              ),
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: t.warning),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.starters, required this.onAsk});
  final List<(String, IconData)> starters;
  final void Function(String) onAsk;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  t.primary.withValues(alpha: 0.18),
                  t.accent.withValues(alpha: 0.12),
                ],
              ),
              border: Border.all(color: t.primary.withValues(alpha: 0.25)),
            ),
            child: Icon(Icons.auto_awesome, color: t.primary, size: 28),
          ),
        ),
        const Gap(S.lg),
        Text(
          'Your money, explained',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: t.foreground,
          ),
        ),
        const Gap(S.sm),
        Text(
          'Ask anything about your balances, plans, debts, or habits. Answers stay grounded in your real numbers.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppType.bodySm,
            height: 1.45,
            color: t.mutedForeground,
          ),
        ),
        const Gap(S.xl),
        Text(
          'Try asking',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: t.mutedForeground,
          ),
        ),
        const Gap(S.sm),
        for (final (label, icon) in starters) ...[
          _StarterChip(
            label: label,
            icon: icon,
            onTap: () => onAsk(label),
          ),
          const Gap(S.sm),
        ],
      ],
    );
  }
}

class _StarterChip extends StatelessWidget {
  const _StarterChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.lg),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: t.border.withValues(alpha: 0.85)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: t.primary),
              const GapX(12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: AppType.bodySm,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: t.foreground,
                  ),
                ),
              ),
              Icon(Icons.north_east_rounded, size: 15, color: t.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final user = message.fromUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            user ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!user) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: message.failed
                    ? t.danger.withValues(alpha: 0.12)
                    : t.primary.withValues(alpha: 0.12),
                border: Border.all(
                  color: message.failed
                      ? t.danger.withValues(alpha: 0.3)
                      : t.primary.withValues(alpha: 0.28),
                ),
              ),
              child: Icon(
                message.failed
                    ? Icons.error_outline_rounded
                    : Icons.auto_awesome,
                size: 15,
                color: message.failed ? t.danger : t.primary,
              ),
            ),
            const GapX(10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  user ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.fromLTRB(
                    user ? 14 : 14,
                    12,
                    14,
                    message.chart != null ? 10 : 12,
                  ),
                  decoration: BoxDecoration(
                    color: user
                        ? t.primary
                        : message.failed
                            ? t.danger.withValues(alpha: 0.08)
                            : t.surface,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(user ? 18 : 6),
                      bottomRight: Radius.circular(user ? 6 : 18),
                    ),
                    border: user
                        ? null
                        : Border.all(
                            color: message.failed
                                ? t.danger.withValues(alpha: 0.25)
                                : t.border.withValues(alpha: 0.8),
                          ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: t.isDark ? 0.25 : 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: user
                      ? Text(
                          message.content,
                          style: TextStyle(
                            color: t.primaryForeground,
                            fontSize: AppType.body,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      : message.failed
                          ? Text(
                              message.content,
                              style: TextStyle(
                                color: t.danger,
                                fontSize: AppType.bodySm,
                                height: 1.4,
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                MarkdownBody(message.content, dense: true),
                                if (message.chart != null) ...[
                                  const Gap(S.md),
                                  _ChartCard(chart: message.chart!),
                                ],
                              ],
                            ),
                ),
                if (!user && !message.failed) ...[
                  const Gap(6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.provider != null)
                        Text(
                          message.provider!,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: t.mutedForeground,
                          ),
                        ),
                      if (message.provider != null) const GapX(8),
                      _MiniAction(
                        icon: Icons.copy_rounded,
                        label: 'Copy',
                        onTap: () async {
                          await Clipboard.setData(
                            ClipboardData(text: message.content),
                          );
                          Haptics.select();
                          if (context.mounted) {
                            toast(context, 'Copied');
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (user) const GapX(4),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: t.mutedForeground),
            const GapX(4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: t.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.chart});
  final _ChartData chart;

  static const _swatches = [
    Color(0xFF059669),
    Color(0xFF0EA5E9),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFF14B8A6),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.surfaceMuted.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (chart.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                chart.title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: t.foreground,
                ),
              ),
            ),
          if (chart.type == 'donut')
            Center(
              child: DonutChart(
                size: 150,
                data: [
                  for (var i = 0; i < chart.points.length; i++)
                    Slice(
                      label: chart.points[i].$1,
                      value: chart.points[i].$2,
                      color: _swatches[i % _swatches.length],
                    ),
                ],
              ),
            )
          else
            RankedBars(
              format: (v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1),
              data: [
                for (final p in chart.points)
                  BarDatum(label: p.$1, value: p.$2),
              ],
            ),
        ],
      ),
    );
  }
}

class _ThinkingBubble extends StatefulWidget {
  const _ThinkingBubble();

  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.primary.withValues(alpha: 0.12),
            ),
            child: Icon(Icons.auto_awesome, size: 15, color: t.primary),
          ),
          const GapX(10),
          FadeTransition(
            opacity: Tween(begin: 0.45, end: 1.0).animate(_pulse),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: t.border.withValues(alpha: 0.8)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const GapX(5),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: t.primary.withValues(alpha: 0.55 + i * 0.1),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  const GapX(10),
                  Text(
                    'Thinking…',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: t.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.thinking,
    required this.enabled,
    required this.onAsk,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool thinking;
  final bool enabled;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: Motion.fast,
      padding: EdgeInsets.only(bottom: bottom > 0 ? 0 : 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: t.surface.withValues(alpha: 0.92),
          border: Border(
            top: BorderSide(color: t.border.withValues(alpha: 0.7)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  decoration: BoxDecoration(
                    color: t.background,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: t.border),
                  ),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: enabled && !thinking,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onAsk(),
                    style: TextStyle(
                      fontSize: AppType.body,
                      color: t.foreground,
                      height: 1.35,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Ask about your money…',
                      hintStyle: TextStyle(color: t.mutedForeground),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    ),
                  ),
                ),
              ),
              const GapX(8),
              GestureDetector(
                onTap: enabled && !thinking ? onAsk : null,
                child: AnimatedContainer(
                  duration: Motion.fast,
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: thinking || !enabled
                        ? t.surfaceMuted
                        : t.primary,
                  ),
                  child: thinking
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: t.mutedForeground,
                          ),
                        )
                      : Icon(
                          Icons.arrow_upward_rounded,
                          color: enabled
                              ? t.primaryForeground
                              : t.mutedForeground,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistorySheet extends StatelessWidget {
  const _HistorySheet({
    required this.loading,
    required this.items,
    required this.activeId,
    required this.onNew,
    required this.onOpen,
    required this.onDelete,
  });

  final bool loading;
  final List<_ConversationSummary> items;
  final String? activeId;
  final VoidCallback onNew;
  final void Function(String id) onOpen;
  final void Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'New chat',
            icon: Icons.edit_square,
            onPressed: onNew,
          ),
          const Gap(S.md),
          if (loading && items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: PageLoader(rows: 3, hero: false),
            )
          else if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: EmptyState(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'No chats yet',
                description: 'Start a conversation and it will show up here.',
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, _) => const Gap(S.sm),
                itemBuilder: (context, i) {
                  final c = items[i];
                  final active = c.id == activeId;
                  return AppCard(
                    padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                    color: active
                        ? t.primary.withValues(alpha: 0.08)
                        : t.surface,
                    borderColor: active
                        ? t.primary.withValues(alpha: 0.35)
                        : t.border,
                    onTap: () => onOpen(c.id),
                    child: Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 18,
                          color: active ? t.primary : t.mutedForeground,
                        ),
                        const GapX(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: AppType.bodySm,
                                  fontWeight: FontWeight.w700,
                                  color: t.foreground,
                                ),
                              ),
                              const Gap(3),
                              Text(
                                c.preview?.isNotEmpty == true
                                    ? c.preview!
                                    : relativeTime(c.updatedAt),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: t.mutedForeground,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: t.mutedForeground,
                          ),
                          onPressed: () => onDelete(c.id),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
