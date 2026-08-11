import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../models/common.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../widgets/charts.dart';
import '../../widgets/fields.dart';
import '../../widgets/ui.dart';
import '../settings/settings_screen.dart';

/// "Ask Santim" — the assistant answers only from your own figures, and can
/// return a chart when a comparison is easier seen than read.
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
        failed = false;

  _Message.reply(this.text, {this.chart, this.provider})
      : fromUser = false,
        failed = false;

  _Message.error(this.text)
      : fromUser = false,
        chart = null,
        provider = null,
        failed = true;

  final String text;
  final bool fromUser;
  final _Chart? chart;
  final String? provider;
  final bool failed;
}

class _Chart {
  const _Chart({required this.type, required this.title, required this.points});
  final String type;
  final String title;
  final List<(String, double)> points;

  static _Chart? maybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final data = asList(m['data']);
    if (data.isEmpty) return null;
    return _Chart(
      type: asStr(m['type'], 'bar'),
      title: asStr(m['title'], ''),
      points: [for (final d in data) (asStr(d['label'], ''), asNum(d['value']))],
    );
  }
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Message>[];

  bool _thinking = false;
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
    _checkStatus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    try {
      final json = await context.read<ApiClient>().get<Map<String, dynamic>>('/ai/status');
      if (mounted) setState(() => _configured = asBool(json['configured']));
    } catch (_) {
      if (mounted) setState(() => _configured = false);
    }
  }

  Future<void> _ask([String? preset]) async {
    final question = (preset ?? _controller.text).trim();
    if (question.length < 2 || _thinking) return;

    setState(() {
      _messages.add(_Message.user(question));
      _thinking = true;
      _controller.clear();
    });
    _scrollToEnd();

    try {
      final json = await context
          .read<ApiClient>()
          .post<Map<String, dynamic>>('/ai/ask', body: {'question': question});
      if (!mounted) return;
      setState(() {
        _messages.add(_Message.reply(
          asStr(json['answer'], 'No answer came back.'),
          chart: _Chart.maybe(json['chart']),
          provider: asStrOrNull(json['provider']),
        ));
        _thinking = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_Message.error(e.message));
        _thinking = false;
      });
    }
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: Motion.fast,
        curve: Motion.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.auto_awesome, size: 18, color: t.primary),
            const SizedBox(width: 8),
            Text(
              'Ask Santim',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: t.foreground),
            ),
          ],
        ),
      ),
      body: MeshBackground(
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              if (_configured == false)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                  child: AppCard(
                    padding: const EdgeInsets.all(14),
                    color: t.warning.withValues(alpha: 0.08),
                    borderColor: t.warning.withValues(alpha: 0.25),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.key_outlined, size: 17, color: t.warning),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(
                            'No AI provider set up yet. Add a key in Settings to '
                            'start asking questions.',
                            style: TextStyle(fontSize: 12.5, height: 1.4, color: t.foreground),
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 18, color: t.warning),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: _messages.isEmpty
                    ? _intro(context)
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
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _controller,
                        placeholder: 'Ask about your money…',
                        prefixIcon: Icons.chat_bubble_outline,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _ask(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    PressableScale(
                      scale: 0.92,
                      onTap: _thinking ? null : () => _ask(),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(R.md),
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _intro(BuildContext context) {
    final t = context.t;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      children: [
        Center(
          child: PopIn(
            child: Container(
              width: 72,
              height: 72,
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
              child: Icon(Icons.auto_awesome, size: 32, color: t.primaryForeground),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FadeInUp(
          delay: const Duration(milliseconds: 100),
          child: Text(
            'Ask about your own money',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.4,
              color: t.foreground,
            ),
          ),
        ),
        const SizedBox(height: 6),
        FadeInUp(
          delay: const Duration(milliseconds: 140),
          child: Text(
            'Answers come only from your own figures — nothing is invented, and '
            'nothing leaves your account.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.5, color: t.mutedForeground),
          ),
        ),
        const SizedBox(height: 26),
        for (var i = 0; i < _starters.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FadeInUp.staggered(
              index: i + 3,
              child: AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                onTap: () => _ask(_starters[i]),
                child: Row(
                  children: [
                    Icon(Icons.north_east_rounded, size: 15, color: t.primary),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        _starters[i],
                        style: TextStyle(fontSize: 13.5, color: t.foreground),
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
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment:
              m.fromUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!m.fromUser) ...[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(R.sm + 2),
                  gradient: LinearGradient(colors: [t.primary, t.accent]),
                ),
                child: Icon(Icons.auto_awesome, size: 15, color: t.primaryForeground),
              ),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: m.fromUser
                      ? t.primary
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
                  boxShadow: m.fromUser ? null : t.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.text,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.55,
                        color: m.fromUser
                            ? t.primaryForeground
                            : m.failed
                                ? t.danger
                                : t.foreground,
                      ),
                    ),
                    if (m.chart != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        m.chart!.title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: t.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: 250,
                        child: m.chart!.type == 'donut'
                            ? Center(
                                child: DonutChart(
                                  size: 150,
                                  data: [
                                    for (var i = 0; i < m.chart!.points.length; i++)
                                      Slice(
                                        label: m.chart!.points[i].$1,
                                        value: m.chart!.points[i].$2,
                                        color: financeColorAt(i),
                                      ),
                                  ],
                                  format: (v) =>
                                      prefs.money(v, currency: currency, compact: true),
                                ),
                              )
                            : RankedBars(
                                data: [
                                  for (final p in m.chart!.points)
                                    BarDatum(label: p.$1, value: p.$2),
                                ],
                                format: (v) => prefs.money(v, currency: currency),
                              ),
                      ),
                    ],
                    if (m.provider != null) ...[
                      const SizedBox(height: 8),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.sm + 2),
              gradient: LinearGradient(colors: [t.primary, t.accent]),
            ),
            child: Icon(Icons.auto_awesome, size: 15, color: t.primaryForeground),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
