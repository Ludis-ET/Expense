import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/haptics.dart';

import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import 'ui.dart';

class Slice {
  const Slice({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;
}

/// Gives a painted chart one spoken sentence.
///
/// Every chart in this file is a [CustomPaint], which a screen reader reports
/// as an empty rectangle. Wrapping the painted region in a single semantic
/// node   with the painter itself excluded   turns silence into "Spending by
/// category. Groceries 32 percent, transport 18 percent…".
class ChartSemantics extends StatelessWidget {
  const ChartSemantics({
    super.key,
    required this.summary,
    required this.child,
    this.excludeChild = true,
  });

  final String summary;
  final Widget child;

  /// Leave false when the chart's own labels are real [Text] widgets worth
  /// reading   ranked bars, for example, already announce themselves.
  final bool excludeChild;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: summary,
    child: excludeChild ? ExcludeSemantics(child: child) : child,
  );
}

/// "Groceries 32 percent, Transport 18 percent, …"   the top [take] shares.
String describeShares(String title, List<Slice> data, {int take = 5}) {
  final total = data.fold<double>(0, (sum, s) => sum + s.value.abs());
  if (data.isEmpty || total <= 0) return '$title. No data yet.';

  final ranked = [...data]
    ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
  final parts = ranked.take(take).map((s) {
    final pct = (s.value.abs() / total * 100).round();
    return '${s.label} $pct percent';
  });
  final rest = ranked.length - take;

  return '$title. ${parts.join(', ')}'
      '${rest > 0 ? ', and $rest more' : ''}.';
}

/// Donut with tappable segments and a centre readout   the mobile port of
/// `charts/donut.tsx`. Sweeps in over 900ms on first paint.
class DonutChart extends StatefulWidget {
  const DonutChart({
    super.key,
    required this.data,
    this.size = 168,
    this.thickness = 22,
    this.format,
    this.centerLabel = 'total',
    this.onSelect,
  });

  final List<Slice> data;
  final double size;
  final double thickness;
  final String Function(double)? format;
  final String centerLabel;
  final void Function(Slice slice, int index)? onSelect;

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();
  int? _selected;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _tapAt(Offset local) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final v = local - center;
    final r = v.distance;
    final outer = widget.size / 2;
    final inner = outer - widget.thickness;
    if (r < inner || r > outer) {
      setState(() => _selected = null);
      return;
    }
    // Ring starts at 12 o'clock, so rotate the angle a quarter turn.
    var angle = math.atan2(v.dy, v.dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;
    final total = widget.data.fold<double>(0, (s, d) => s + d.value);
    if (total <= 0) return;

    var acc = 0.0;
    for (var i = 0; i < widget.data.length; i++) {
      acc += widget.data[i].value / total * 2 * math.pi;
      if (angle <= acc) {
        Haptics.select();
        setState(() => _selected = _selected == i ? null : i);
        if (_selected != null) widget.onSelect?.call(widget.data[i], i);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final total = widget.data.fold<double>(0, (s, d) => s + d.value);
    final fmt = widget.format ?? (v) => v.toStringAsFixed(0);
    final sel = _selected != null && _selected! < widget.data.length
        ? widget.data[_selected!]
        : null;

    return Column(
      children: [
        ChartSemantics(
          summary: describeShares(
            'Breakdown, total ${fmt(total)}',
            widget.data,
          ),
          child: GestureDetector(
            onTapDown: (d) => _tapAt(d.localPosition),
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(
                  painter: _DonutPainter(
                    data: widget.data,
                    total: total,
                    thickness: widget.thickness,
                    track: t.surfaceMuted,
                    progress: Curves.easeOutCubic.transform(_c.value),
                    selected: _selected,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Amount(fmt(sel?.value ?? total), size: 17),
                        const Gap(S.hair),
                        SizedBox(
                          width: widget.size - widget.thickness * 2 - 12,
                          child: Text(
                            sel?.label ?? widget.centerLabel,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppType.caption,
                              color: t.mutedForeground,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const Gap(S.lg),
        Wrap(
          spacing: S.md,
          runSpacing: S.sm,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < widget.data.length; i++)
              GestureDetector(
                onTap: () =>
                    setState(() => _selected = _selected == i ? null : i),
                child: Opacity(
                  opacity: _selected == null || _selected == i ? 1 : 0.4,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: widget.data[i].color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const GapX(S.xs),
                      Text(
                        widget.data[i].label,
                        style: TextStyle(
                          fontSize: AppType.caption,
                          color: t.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.data,
    required this.total,
    required this.thickness,
    required this.track,
    required this.progress,
    required this.selected,
  });

  final List<Slice> data;
  final double total;
  final double thickness;
  final Color track;
  final double progress;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width - thickness) / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..color = track,
    );

    if (total <= 0) return;

    var start = -math.pi / 2;
    for (var i = 0; i < data.length; i++) {
      final sweep = data[i].value / total * 2 * math.pi * progress;
      final grow = selected == i ? 3.0 : 0.0;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        // A hair of padding between segments keeps them legible.
        math.max(sweep - 0.012, 0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness + grow
          ..strokeCap = StrokeCap.butt
          ..color = selected == null || selected == i
              ? data[i].color
              : data[i].color.withValues(alpha: 0.3),
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress || old.selected != selected || old.data != data;
}

class SeriesPoint {
  const SeriesPoint({
    required this.label,
    required this.income,
    required this.expense,
  });
  final String label;
  final double income;
  final double expense;
}

/// Dual-series income/expense line with a gradient area fill and a draggable
/// readout   the port of `charts/line.tsx`.
class IncomeExpenseLine extends StatefulWidget {
  const IncomeExpenseLine({
    super.key,
    required this.points,
    required this.format,
    this.height = 200,
  });

  final List<SeriesPoint> points;
  final String Function(double) format;
  final double height;

  @override
  State<IncomeExpenseLine> createState() => _IncomeExpenseLineState();
}

class _IncomeExpenseLineState extends State<IncomeExpenseLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..forward();
  int? _active;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    if (widget.points.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 34),
        child: Center(child: Muted('No data yet.')),
      );
    }

    final active = _active != null && _active! < widget.points.length
        ? widget.points[_active!]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _LegendDot(color: t.success, label: 'Income'),
            const GapX(S.md),
            // Dashed swatch: income and expense must stay apart for a viewer
            // who cannot separate the green from the red.
            _LegendDot(color: t.danger, label: 'Expense', dashed: true),
            const Spacer(),
            if (active != null)
              Text(
                active.label,
                style: TextStyle(
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w600,
                  color: t.foreground,
                ),
              ),
          ],
        ),
        if (active != null)
          Padding(
            padding: const EdgeInsets.only(top: S.xxs),
            child: Row(
              children: [
                Amount(
                  '+${widget.format(active.income)}',
                  size: AppType.label,
                  color: t.success,
                ),
                const GapX(S.md),
                Amount(
                  '−${widget.format(active.expense)}',
                  size: AppType.label,
                  color: t.danger,
                ),
              ],
            ),
          ),
        const Gap(S.sm),
        ChartSemantics(
          summary: _spokenSummary(),
          child: LayoutBuilder(
            builder: (context, box) {
              final width = box.maxWidth;
              return GestureDetector(
                onTapDown: (d) => _select(d.localPosition.dx, width),
                onHorizontalDragUpdate: (d) =>
                    _select(d.localPosition.dx, width),
                onHorizontalDragEnd: (_) => setState(() => _active = null),
                child: SizedBox(
                  height: widget.height,
                  width: width,
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => CustomPaint(
                      painter: _LinePainter(
                        points: widget.points,
                        income: t.success,
                        expense: t.danger,
                        grid: t.border,
                        label: t.mutedForeground,
                        progress: Curves.easeOutCubic.transform(_c.value),
                        active: _active,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// The whole plot in one sentence: the span it covers, both totals, and
  /// which way the balance went.
  String _spokenSummary() {
    final pts = widget.points;
    if (pts.isEmpty) return 'Income and expense chart. No data yet.';

    final income = pts.fold<double>(0, (sum, p) => sum + p.income);
    final expense = pts.fold<double>(0, (sum, p) => sum + p.expense);
    final net = income - expense;

    return 'Income and expense over ${pts.length} points, '
        '${pts.first.label} to ${pts.last.label}. '
        'Income ${widget.format(income)}. '
        'Expense ${widget.format(expense)}. '
        '${net >= 0 ? 'Up' : 'Down'} ${widget.format(net.abs())} overall.';
  }

  void _select(double dx, double width) {
    const padL = 6.0;
    const padR = 6.0;
    final usable = width - padL - padR;
    final n = widget.points.length;
    if (n == 0 || usable <= 0) return;
    final i = n == 1
        ? 0
        : (((dx - padL) / usable) * (n - 1)).round().clamp(0, n - 1);
    if (i != _active) {
      Haptics.select();
      setState(() => _active = i);
    }
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.points,
    required this.income,
    required this.expense,
    required this.grid,
    required this.label,
    required this.progress,
    required this.active,
  });

  final List<SeriesPoint> points;
  final Color income;
  final Color expense;
  final Color grid;
  final Color label;
  final double progress;
  final int? active;

  static const _pad = EdgeInsets.fromLTRB(S.xs, S.md, S.xs, S.xxl);

  @override
  void paint(Canvas canvas, Size size) {
    final maxY =
        math.max(
          1.0,
          points.fold<double>(
            0,
            (m, p) => math.max(m, math.max(p.income, p.expense)),
          ),
        ) *
        1.1;

    double x(int i) =>
        _pad.left +
        (points.length == 1 ? 0.5 : i / (points.length - 1)) *
            (size.width - _pad.horizontal);
    double y(double v) =>
        size.height - _pad.bottom - (v / maxY) * (size.height - _pad.vertical);

    // Horizontal guides.
    final gridPaint = Paint()
      ..color = grid.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final gy = _pad.top + (size.height - _pad.vertical) * (i / 3);
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), gridPaint);
    }

    void series(
      double Function(SeriesPoint) pick,
      Color color, {
      bool dash = false,
    }) {
      final path = Path();
      final area = Path();
      for (var i = 0; i < points.length; i++) {
        final px = x(i);
        final py = y(pick(points[i]) * progress);
        if (i == 0) {
          path.moveTo(px, py);
          area.moveTo(px, size.height - _pad.bottom);
          area.lineTo(px, py);
        } else {
          path.lineTo(px, py);
          area.lineTo(px, py);
        }
      }
      area.lineTo(x(points.length - 1), size.height - _pad.bottom);
      area.close();

      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color;

      canvas.drawPath(dash ? _dashPath(path, on: 7, off: 5) : path, stroke);

      if (active != null && active! < points.length) {
        final dot = Offset(x(active!), y(pick(points[active!]) * progress));
        canvas.drawCircle(dot, 5, Paint()..color = color);
        canvas.drawCircle(
          dot,
          5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white.withValues(alpha: 0.9),
        );
      }
    }

    series((p) => p.income, income);
    // Dashed so the two series stay distinguishable without colour vision
    // Santim's income green and expense red sit at similar luminance.
    series((p) => p.expense, expense, dash: true);

    if (active != null && active! < points.length) {
      final px = x(active!);
      canvas.drawLine(
        Offset(px, _pad.top),
        Offset(px, size.height - _pad.bottom),
        Paint()
          ..color = label.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
    }

    // X labels, thinned so they never collide.
    final step = math.max(1, (points.length / 5).ceil());
    for (var i = 0; i < points.length; i++) {
      if (i % step != 0 && i != points.length - 1) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: points[i].label,
          style: TextStyle(fontSize: AppType.micro, color: label),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final tx = (x(i) - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(tx, size.height - tp.height - 2));
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.progress != progress || old.active != active || old.points != points;
}

/// Re-walks [source] emitting [on]-long segments separated by [off] gaps.
/// Flutter has no dashed-stroke paint style, so the path has to be rebuilt.
Path _dashPath(Path source, {required double on, required double off}) {
  final out = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    var draw = true;
    while (distance < metric.length) {
      final step = draw ? on : off;
      final next = math.min(distance + step, metric.length);
      if (draw) out.addPath(metric.extractPath(distance, next), Offset.zero);
      distance = next;
      draw = !draw;
    }
  }
  return out;
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    this.dashed = false,
  });
  final Color color;
  final String label;

  /// Draws the swatch as a dashed bar rather than a dot, matching the dashed
  /// stroke used for the same series in the plot.
  final bool dashed;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (dashed)
        SizedBox(
          width: 14,
          height: 8,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 2; i++)
                Container(
                  width: 5,
                  height: 3,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                ),
            ],
          ),
        )
      else
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      const GapX(S.xxs),
      Muted(label, size: AppType.caption),
    ],
  );
}

class BarDatum {
  const BarDatum({
    required this.label,
    required this.value,
    this.color,
    this.caption,
  });
  final String label;
  final double value;
  final Color? color;
  final String? caption;
}

/// Horizontal ranked bars   the port of `charts/bar.tsx`, used for top payees,
/// category movers and day-of-week averages.
class RankedBars extends StatelessWidget {
  const RankedBars({
    super.key,
    required this.data,
    required this.format,
    this.max,
    this.onTap,
  });

  final List<BarDatum> data;
  final String Function(double) format;
  final double? max;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    if (data.isEmpty)
      return const EmptyState(title: 'Nothing to show yet', compact: true);
    final peak =
        max ?? data.fold<double>(1, (m, d) => math.max(m, d.value.abs()));

    // The bars carry real Text labels and values, so they are left readable
    // and only the ranking itself is announced up front.
    return ChartSemantics(
      summary:
          'Ranked bars, ${data.length} rows, '
          'largest ${data.first.label} at ${format(data.first.value)}.',
      excludeChild: false,
      child: Column(
        children: [
          for (var i = 0; i < data.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == data.length - 1 ? 0 : S.md),
              child: FadeInUp.staggered(
                index: i,
                offset: 6,
                child: GestureDetector(
                  onTap: onTap == null ? null : () => onTap!(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              data[i].label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppType.bodySm,
                                fontWeight: FontWeight.w500,
                                color: t.foreground,
                              ),
                            ),
                          ),
                          const GapX(S.sm),
                          Amount(format(data[i].value), size: 12.5),
                        ],
                      ),
                      const Gap(S.xs),
                      ProgressBar(
                        value: peak <= 0
                            ? 0
                            : (data[i].value.abs() / peak) * 100,
                        height: 7,
                        gradient: data[i].color == null
                            ? null
                            : [
                                data[i].color!,
                                data[i].color!.withValues(alpha: 0.65),
                              ],
                      ),
                      if (data[i].caption != null) ...[
                        const Gap(S.xxs),
                        Muted(data[i].caption!, size: 11),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Calendar heatmap of daily spend   the port of `charts/heatmap.tsx`. Weeks
/// run down each column, matching GitHub's contribution grid.
class SpendHeatmap extends StatelessWidget {
  const SpendHeatmap({
    super.key,
    required this.days,
    required this.format,
    this.onTapDay,
    this.cell = 12,
  });

  final Map<DateTime, double> days;
  final String Function(double) format;
  final void Function(DateTime day, double amount)? onTapDay;
  final double cell;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    if (days.isEmpty)
      return const EmptyState(title: 'No spending recorded yet', compact: true);

    final sorted = days.keys.toList()..sort();
    final first = sorted.first;
    final last = sorted.last;
    final peak = days.values.fold<double>(0, math.max);

    // Back up to the Sunday on or before the first day so columns align.
    final start = first.subtract(Duration(days: first.weekday % 7));
    final weeks = ((last.difference(start).inDays) / 7).ceil() + 1;

    final spentDays = days.values.where((v) => v > 0).length;
    final busiest = sorted.reduce(
      (a, b) => (days[a] ?? 0) >= (days[b] ?? 0) ? a : b,
    );

    return ChartSemantics(
      summary:
          'Daily spending heatmap, ${days.length} days. '
          'Spent on $spentDays of them. '
          'Heaviest day ${busiest.day}/${busiest.month} at '
          '${format(days[busiest] ?? 0)}. Peak ${format(peak)}.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var w = 0; w < weeks; w++)
                  Padding(
                    padding: const EdgeInsets.only(right: S.xxs),
                    child: Column(
                      children: [
                        for (var d = 0; d < 7; d++)
                          Builder(
                            builder: (context) {
                              final day = start.add(Duration(days: w * 7 + d));
                              final key = DateTime(
                                day.year,
                                day.month,
                                day.day,
                              );
                              final amount = days[key];
                              final within =
                                  !day.isBefore(
                                    DateTime(
                                      first.year,
                                      first.month,
                                      first.day,
                                    ),
                                  ) &&
                                  !day.isAfter(
                                    DateTime(last.year, last.month, last.day),
                                  );
                              final ratio = (amount == null || peak <= 0)
                                  ? 0.0
                                  : amount / peak;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: S.xxs),
                                child: GestureDetector(
                                  onTap: within && onTapDay != null
                                      ? () => onTapDay!(key, amount ?? 0)
                                      : null,
                                  child: Container(
                                    width: cell,
                                    height: cell,
                                    decoration: BoxDecoration(
                                      color: !within
                                          ? Colors.transparent
                                          : ratio <= 0
                                          ? t.surfaceMuted
                                          : Color.lerp(
                                              t.primary.withValues(alpha: 0.22),
                                              t.primary,
                                              math.pow(ratio, 0.6).toDouble(),
                                            ),
                                      borderRadius: BorderRadius.circular(2.5),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Gap(S.sm),
          Row(
            children: [
              Muted('Less', size: 10.5),
              const GapX(S.xs),
              for (final step in [0.0, 0.25, 0.5, 0.75, 1.0])
                Padding(
                  padding: const EdgeInsets.only(right: S.xxs),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: step == 0
                          ? t.surfaceMuted
                          : Color.lerp(
                              t.primary.withValues(alpha: 0.22),
                              t.primary,
                              step,
                            ),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
              const GapX(S.xxs),
              Muted('More', size: AppType.micro),
              const Spacer(),
              Muted('Peak ${format(peak)}', size: AppType.micro),
            ],
          ),
        ],
      ),
    );
  }
}

/// The dot strip on the dashboard: one dot per day, filled when the day's spend
/// stayed under the running average.
class SpendStrip extends StatelessWidget {
  const SpendStrip({super.key, required this.days, this.dotSize = 9});

  /// `(under, spent)` per day, oldest first.
  final List<(bool under, bool spent)> days;
  final double dotSize;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final under = days.where((d) => d.$2 && d.$1).length;
    final over = days.where((d) => d.$2 && !d.$1).length;
    final quiet = days.where((d) => !d.$2).length;

    return ChartSemantics(
      summary:
          '${days.length} day spending strip. '
          '$under under average, $over over, $quiet with no spending.',
      child: Wrap(
        spacing: S.xxs,
        runSpacing: S.xxs,
        children: [
          for (var i = 0; i < days.length; i++)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 260 + i * 12),
              curve: Motion.spring,
              builder: (context, v, child) =>
                  Transform.scale(scale: v, child: child),
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: !days[i].$2
                      ? t.surfaceMuted
                      : days[i].$1
                      ? t.success
                      : t.danger.withValues(alpha: 0.85),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact sparkline for stat cards.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.color,
    this.height = 34,
    this.fill = true,
  });

  final List<double> values;
  final Color? color;
  final double height;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    if (values.length < 2) return SizedBox(height: height);

    final first = values.first;
    final last = values.last;
    final direction = last > first
        ? 'rising'
        : (last < first ? 'falling' : 'flat');

    return ChartSemantics(
      summary: 'Trend over ${values.length} points, $direction.',
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 800),
          curve: Motion.easeOut,
          builder: (context, v, _) => CustomPaint(
            painter: _SparkPainter(
              values: values,
              color: color ?? t.primary,
              progress: v,
              fill: fill,
            ),
          ),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({
    required this.values,
    required this.color,
    required this.progress,
    required this.fill,
  });

  final List<double> values;
  final Color color;
  final double progress;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = values.reduce(math.max);
    final minV = values.reduce(math.min);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : maxV - minV;

    final path = Path();
    final area = Path()..moveTo(0, size.height);
    final count = math.max(2, (values.length * progress).ceil());

    for (var i = 0; i < count && i < values.length; i++) {
      final x = i / (values.length - 1) * size.width;
      final y =
          size.height - ((values[i] - minV) / range) * (size.height - 3) - 1.5;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      area.lineTo(x, y);
    }
    area.lineTo(
      math.min(count - 1, values.length - 1) / (values.length - 1) * size.width,
      size.height,
    );
    area.close();

    if (fill) {
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.progress != progress || old.values != values;
}

/// Vertical bar column chart used for weekly / monthly comparisons.
class ColumnChart extends StatelessWidget {
  const ColumnChart({
    super.key,
    required this.data,
    required this.format,
    this.height = 150,
  });

  final List<BarDatum> data;
  final String Function(double) format;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    if (data.isEmpty)
      return const EmptyState(title: 'No data yet', compact: true);
    final peak = data.fold<double>(1, (m, d) => math.max(m, d.value));
    final tallest = data.reduce((a, b) => a.value >= b.value ? a : b);

    return ChartSemantics(
      summary:
          '${data.length} columns, ${data.first.label} to ${data.last.label}. '
          'Highest ${tallest.label} at ${format(tallest.value)}.',
      excludeChild: false,
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < data.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: S.xxs),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        format(data[i].value),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          fontSize: AppType.micro,
                          color: t.mutedForeground,
                        ),
                      ),
                      const Gap(S.xxs),
                      TweenAnimationBuilder<double>(
                        tween: Tween(
                          begin: 0,
                          end: (data[i].value / peak).clamp(0.02, 1.0),
                        ),
                        duration: Duration(milliseconds: 600 + i * 60),
                        curve: Motion.easeOut,
                        builder: (context, v, _) => Container(
                          height: (height - 42) * v,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                data[i].color ?? t.primary,
                                (data[i].color ?? t.primary).withValues(
                                  alpha: 0.45,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Gap(S.xs),
                      Text(
                        data[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.micro,
                          color: t.mutedForeground,
                        ),
                      ),
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
