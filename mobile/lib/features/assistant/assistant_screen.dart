import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_client.dart';
import '../../core/haptics.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../models/common.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../widgets/charts.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';
import '../settings/settings_screen.dart';

/// "Ask Santim"   chat about your own figures. Messages persist locally.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _Message {
  _Message.user(this.text)
    : fromUser = true,
      chart = null,
      provider = null,
      failed = false,
      at = DateTime.now();

  _Message.reply(this.text, {this.chart, this.provider})
    : fromUser = false,
      failed = false,
      at = DateTime.now();

  _Message.error(this.text)
    : fromUser = false,
      chart = null,
      provider = null,
      failed = true,
      at = DateTime.now();

  _Message._({
    required this.text,
    required this.fromUser,
    required this.failed,
    required this.at,
    this.chart,
    this.provider,
  });

  final String text;
  final bool fromUser;
  final _Chart? chart;
  final String? provider;
  final bool failed;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'text': text,
    'fromUser': fromUser,
    'failed': failed,
    'provider': provider,
    'at': at.toIso8601String(),
    if (chart != null) 'chart': chart!.toJson(),
  };

  factory _Message.fromJson(Map<String, dynamic> j) => _Message._(
    text: asStr(j['text']),
    fromUser: asBool(j['fromUser']),
    failed: asBool(j['failed']),
    provider: asStrOrNull(j['provider']),
    at: DateTime.tryParse(asStr(j['at'])) ?? DateTime.now(),
    chart: _Chart.maybe(j['chart']),
  );
}

class _Chart {
  const _Chart({required this.type, required this.title, required this.points});
  final String type;
  final String title;
  final List<(String, double)> points;

  Map<String, dynamic> toJson() => {
    'type': type,
    'title': title,
    'data': [
      for (final p in points) {'label': p.$1, 'value': p.$2},
    ],
  };

  static _Chart? maybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final data = asList(m['data']);
    if (data.isEmpty) return null;
    return _Chart(
      type: asStr(m['type'], 'bar'),
      title: asStr(m['title'], ''),
      points: [
        for (final d in data) (asStr(d['label'], ''), asNum(d['value'])),
      ],
    );
  }
}

class _AssistantScreenState extends State<AssistantScreen> {
  static const _storageKey = 'santim_ai_chat_v1';
  static const _maxStored = 60;

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Message>[];

  bool _thinking = false;
  bool _loaded = false;
  bool? _configured;

  static const _starters = [
    'Where did most of my money go this month?',
    'Am I saving enough?',
    'Who still owes me money?',
    'Which budget plan is closest to running out?',
    'What can I cut back on?',
  ];

  @override
  void initState() {
    super.initState();
    _restore();
    _checkStatus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) {
          _messages
            ..clear()
            ..addAll([
              for (final item in list)
                if (item is Map)
                  _Message.fromJson(Map<String, dynamic>.from(item)),
            ]);
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _loaded = true);
      if (_messages.isNotEmpty) _scrollToEnd(jump: true);
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final slice = _messages.length > _maxStored
          ? _messages.sublist(_messages.length - _maxStored)
          : _messages;
      await prefs.setString(
        _storageKey,
        jsonEncode([for (final m in slice) m.toJson()]),
      );
    } catch (_) {}
  }

  Future<void> _clearChat() async {
    final ok = await confirm(
      context,
      title: 'Clear chat?',
      message:
          'This removes your saved Ask Santim conversation on this device.',
      confirmLabel: 'Clear',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _messages.clear());
    await _persist();
    Haptics.toggle();
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

  Future<void> _ask([String? preset]) async {
    final question = (preset ?? _controller.text).trim();
    if (question.length < 2 || _thinking) return;
    final api = context.read<ApiClient>();

    setState(() {
      _messages.add(_Message.user(question));
      _thinking = true;
      _controller.clear();
    });
    await _persist();
    _scrollToEnd();

    try {
      final json = await api.post<Map<String, dynamic>>(
        '/ai/ask',
        body: {'question': question},
      );
      if (!mounted) return;
      setState(() {
        _messages.add(
          _Message.reply(
            asStr(json['answer'], 'No answer came back.'),
            chart: _Chart.maybe(json['chart']),
            provider: asStrOrNull(json['provider']),
          ),
        );
        _thinking = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_Message.error(e.message));
        _thinking = false;
      });
    }
    await _persist();
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

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return Scaffold(
      backgroundColor: t.background,
      body: MeshBackground(
        child: SafeArea(
          child: Column(
            children: [
              _ChatHeader(
                hasMessages: _messages.isNotEmpty,
                onClear: _messages.isEmpty ? null : _clearChat,
                onClose: () => Navigator.of(context).maybePop(),
              ),
              if (_configured == false)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                  child: AppCard(
                    padding: const EdgeInsets.all(S.lg),
                    color: t.warning.withValues(alpha: 0.08),
                    borderColor: t.warning.withValues(alpha: 0.25),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.key_outlined, size: 17, color: t.warning),
                        const GapX(S.md),
                        Expanded(
                          child: Text(
                            'No AI provider set up yet. Add a key in Settings to start asking.',
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
                  ),
                ),
              Expanded(
                child: !_loaded
                    ? const Center(child: PageLoader(rows: 2, hero: false))
                    : _messages.isEmpty
                    ? _Intro(starters: _starters, onAsk: _ask)
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        itemCount: _messages.length + (_thinking ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == _messages.length) return const _Thinking();
                          return _Bubble(message: _messages[i]);
                        },
                      ),
              ),
              _Composer(
                controller: _controller,
                thinking: _thinking,
                onAsk: _ask,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.hasMessages,
    this.onClear,
    required this.onClose,
  });

  final bool hasMessages;
  final VoidCallback? onClear;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: t.border.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(
        children: [
          IconPill(
            icon: Icons.arrow_back_rounded,
            background: Colors.transparent,
            tooltip: 'Back',
            onTap: onClose,
          ),
          const GapX(S.xs),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(colors: [t.primary, t.accent]),
              boxShadow: [
                BoxShadow(
                  color: t.primary.withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.auto_awesome,
              size: 18,
              color: t.primaryForeground,
            ),
          ),
          const GapX(S.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ask Santim',
                  style: TextStyle(
                    fontSize: AppType.lead,
                    fontWeight: FontWeight.w800,
                    color: t.foreground,
                  ),
                ),
                Text(
                  hasMessages
                      ? 'Chat saved on this phone'
                      : 'Answers from your own figures',
                  style: TextStyle(
                    fontSize: AppType.caption,
                    color: t.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          if (onClear != null)
            IconPill(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Clear chat',
              onTap: onClear,
            ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.thinking,
    required this.onAsk,
  });

  final TextEditingController controller;
  final bool thinking;
  final Future<void> Function([String?]) onAsk;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        10,
        14,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: t.surface.withValues(alpha: 0.92),
        border: Border(top: BorderSide(color: t.border.withValues(alpha: 0.8))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: AppTextField(
              controller: controller,
              placeholder: 'Ask about your money…',
              prefixIcon: Icons.chat_bubble_outline_rounded,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onAsk(),
            ),
          ),
          const GapX(S.sm),
          PressableScale(
            scale: 0.92,
            onTap: thinking ? null : () => onAsk(),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [t.primary, t.accent]),
                boxShadow: [
                  BoxShadow(
                    color: t.primary.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                Icons.arrow_upward_rounded,
                size: 21,
                color: t.primaryForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.starters, required this.onAsk});
  final List<String> starters;
  final Future<void> Function(String) onAsk;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.xl, S.xxl, S.xl, S.md),
      children: [
        Center(
          child: PopIn(
            child: Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.xl),
                gradient: LinearGradient(colors: [t.primary, t.accent]),
                boxShadow: [
                  BoxShadow(
                    color: t.primary.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                Icons.auto_awesome,
                size: 34,
                color: t.primaryForeground,
              ),
            ),
          ),
        ),
        const Gap(S.xl),
        FadeInUp(
          delay: const Duration(milliseconds: 80),
          child: Text(
            'Your money, in conversation',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppType.heading,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.4,
              color: t.foreground,
            ),
          ),
        ),
        const Gap(S.xs),
        FadeInUp(
          delay: const Duration(milliseconds: 120),
          child: Text(
            'Ask anything about your spending, plans, or tabs. Chats stay on this device.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppType.bodySm,
              height: 1.5,
              color: t.mutedForeground,
            ),
          ),
        ),
        const Gap(S.xxl),
        for (var i = 0; i < starters.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: S.md),
            child: FadeInUp.staggered(
              index: i + 2,
              child: AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: S.lg,
                  vertical: S.md,
                ),
                onTap: () => onAsk(starters[i]),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: t.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(R.sm),
                      ),
                      child: Icon(
                        Icons.north_east_rounded,
                        size: 14,
                        color: t.primary,
                      ),
                    ),
                    const GapX(S.md),
                    Expanded(
                      child: Text(
                        starters[i],
                        style: TextStyle(
                          fontSize: AppType.bodySm,
                          color: t.foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final _Message message;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final m = message;
    final prefs = context.watch<PrefsState>();
    final currency = context.watch<DataState>().activeCurrency;

    return FadeInUp(
      offset: 8,
      child: Padding(
        padding: const EdgeInsets.only(bottom: S.md),
        child: Row(
          mainAxisAlignment: m.fromUser
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!m.fromUser) ...[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(R.sm + 2),
                  gradient: LinearGradient(colors: [t.primary, t.accent]),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  size: 15,
                  color: t.primaryForeground,
                ),
              ),
              const GapX(S.sm),
            ],
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: S.lg,
                  vertical: S.md,
                ),
                decoration: BoxDecoration(
                  gradient: m.fromUser
                      ? LinearGradient(colors: [t.primary, t.accent])
                      : null,
                  color: m.fromUser
                      ? null
                      : m.failed
                      ? t.danger.withValues(alpha: 0.1)
                      : t.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(R.card),
                    topRight: const Radius.circular(R.card),
                    bottomLeft: Radius.circular(m.fromUser ? R.card : 4),
                    bottomRight: Radius.circular(m.fromUser ? 4 : R.card),
                  ),
                  border: m.fromUser ? null : Border.all(color: t.border),
                  boxShadow: m.fromUser
                      ? [
                          BoxShadow(
                            color: t.primary.withValues(alpha: 0.22),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : t.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.text,
                      style: TextStyle(
                        fontSize: AppType.bodySm,
                        height: 1.55,
                        color: m.fromUser
                            ? t.primaryForeground
                            : m.failed
                            ? t.danger
                            : t.foreground,
                      ),
                    ),
                    if (m.chart != null) ...[
                      const Gap(S.md),
                      Text(
                        m.chart!.title,
                        style: TextStyle(
                          fontSize: AppType.label,
                          fontWeight: FontWeight.w700,
                          color: t.mutedForeground,
                        ),
                      ),
                      const Gap(S.sm),
                      SizedBox(
                        width: 250,
                        child: m.chart!.type == 'donut'
                            ? Center(
                                child: DonutChart(
                                  size: 150,
                                  data: [
                                    for (
                                      var i = 0;
                                      i < m.chart!.points.length;
                                      i++
                                    )
                                      Slice(
                                        label: m.chart!.points[i].$1,
                                        value: m.chart!.points[i].$2,
                                        color: financeColorAt(i),
                                      ),
                                  ],
                                  format: (v) => prefs.money(
                                    v,
                                    currency: currency,
                                    compact: true,
                                  ),
                                ),
                              )
                            : RankedBars(
                                data: [
                                  for (final p in m.chart!.points)
                                    BarDatum(label: p.$1, value: p.$2),
                                ],
                                format: (v) =>
                                    prefs.money(v, currency: currency),
                              ),
                      ),
                    ],
                    if (m.provider != null) ...[
                      const Gap(S.sm),
                      Muted('via ${m.provider}', size: 10),
                    ],
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

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.md),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.sm + 2),
              gradient: LinearGradient(colors: [t.primary, t.accent]),
            ),
            child: Icon(
              Icons.auto_awesome,
              size: 15,
              color: t.primaryForeground,
            ),
          ),
          const GapX(S.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: S.lg,
              vertical: S.lg,
            ),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(R.card),
                topRight: Radius.circular(R.card),
                bottomRight: Radius.circular(R.card),
                bottomLeft: Radius.circular(4),
              ),
              border: Border.all(color: t.border),
            ),
            child: const BouncingDots(),
          ),
        ],
      ),
    );
  }
}

/// Cycles the category swatches so an AI-returned chart is still colourful.
Color financeColorAt(int index) {
  const palette = [
    Color(0xFF10B981),
    Color(0xFF3B82F6),
    Color(0xFFF59E0B),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
    Color(0xFFEF4444),
    Color(0xFF6366F1),
  ];
  return palette[index % palette.length];
}
