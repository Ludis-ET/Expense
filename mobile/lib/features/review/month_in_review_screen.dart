import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/haptics.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../models/models.dart';
import '../../state/auth_state.dart';
import '../../state/data_state.dart';
import '../../state/prefs_state.dart';
import '../../widgets/ui.dart';

/// A once-a-month recap of how the month went.
///
/// Everything here is already computed for the dashboard — biggest category,
/// no-spend streak, unnecessary spend, net — it just was never gathered into a
/// moment worth looking at. No new endpoint is involved.
class MonthInReviewScreen extends StatefulWidget {
  const MonthInReviewScreen({super.key});

  @override
  State<MonthInReviewScreen> createState() => _MonthInReviewScreenState();
}

class _MonthInReviewScreenState extends State<MonthInReviewScreen> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('nothing to capture');

      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('could not encode the card');

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/santim-month-in-review.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'My month in Santim',
        ),
      );
      Haptics.commit();
    } catch (_) {
      if (mounted) {
        Haptics.reject();
        toast(context, 'Could not build the share image', error: true);
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final data = context.watch<DataState>();
    final prefs = context.watch<PrefsState>();
    final user = context.watch<AuthState>().user;
    final raw = data.dashboard.data;

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(title: const Text('Month in review')),
      body: raw == null
          ? const PageLoader(rows: 2)
          : ListView(
              padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.lg, S.huge),
              children: [
                // This subtree is what gets captured and shared, so it goes
                // through the same masking as the rest of the app: with Hide
                // amounts on, the shared image carries no figures either.
                RepaintBoundary(
                  key: _cardKey,
                  child: _ReviewCard(
                    raw: raw,
                    prefs: prefs,
                    currency: data.activeCurrency,
                    name: user?.firstName,
                  ),
                ),
                const Gap(S.xl),
                AppButton(
                  label: 'Share this card',
                  icon: Icons.ios_share_rounded,
                  size: BtnSize.lg,
                  expand: true,
                  loading: _sharing,
                  onPressed: _share,
                ),
                const Gap(S.md),
                Muted(
                  prefs.amountsHidden
                      ? 'Amounts are hidden, so the card shares without figures.'
                      : 'The card includes your figures. Turn on Hide amounts '
                          'in the topbar first if you would rather not share them.',
                  size: AppType.caption,
                ),
              ],
            ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.raw,
    required this.prefs,
    required this.currency,
    this.name,
  });

  final DashboardData raw;
  final PrefsState prefs;
  final String currency;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final month = raw.month;
    final net = toNum(month.net);
    final income = toNum(month.income);
    final savingsRate = income > 0 ? (net / income * 100).round() : null;

    String money(Object? v) => prefs.money(v, currency: currency);

    final top = raw.topCategories.isEmpty ? null : raw.topCategories.first;
    final streak = raw.spendingStreak;

    return Container(
      padding: const EdgeInsets.all(S.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(R.xl),
        border: Border.all(color: t.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            t.primary.withValues(alpha: t.isDark ? 0.18 : 0.1),
            t.surface,
            t.accent.withValues(alpha: t.isDark ? 0.12 : 0.07),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BrandMark(size: 28),
              const GapX(S.sm),
              const BrandWord(fontSize: AppType.lead),
              const Spacer(),
              AppBadge(DateFormat('MMMM yyyy').format(DateTime.now()), tone: BadgeTone.primary),
            ],
          ),
          const Gap(S.xl),
          Text(
            name == null ? 'Your month' : "$name's month",
            style: TextStyle(
              fontSize: AppType.figure,
              fontWeight: W.bold,
              letterSpacing: -0.6,
              color: t.foreground,
            ),
          ),
          const Gap(S.xxs),
          Muted(
            net >= 0
                ? 'You finished ahead. Here is where it went.'
                : 'You spent more than came in. Here is where it went.',
            size: AppType.bodySm,
          ),
          const Gap(S.xl),

          _Stat(
            label: 'Net this month',
            value: money(month.net),
            tone: net >= 0 ? BadgeTone.success : BadgeTone.danger,
            icon: net >= 0 ? Icons.trending_up : Icons.trending_down,
          ),
          const Gap(S.md),
          _Stat(
            label: 'Money in',
            value: money(month.income),
            tone: BadgeTone.info,
            icon: Icons.south_west_rounded,
          ),
          const Gap(S.md),
          _Stat(
            label: 'Money out',
            value: money(month.expense),
            tone: BadgeTone.neutral,
            icon: Icons.north_east_rounded,
          ),
          if (top != null) ...[
            const Gap(S.md),
            _Stat(
              label: 'Biggest category',
              value: '${top.category?.name ?? 'Uncategorised'} · ${money(top.amount)}',
              tone: BadgeTone.warning,
              icon: financeIcon(top.category?.icon),
            ),
          ],
          const Gap(S.md),
          _Stat(
            label: 'Best no-spend streak',
            value: '${streak.bestStreak} day${streak.bestStreak == 1 ? '' : 's'}',
            tone: BadgeTone.primary,
            icon: Icons.local_fire_department_outlined,
          ),
          const Gap(S.md),
          _Stat(
            label: 'Unnecessary spending',
            value: money(raw.unnecessary.total),
            tone: toNum(raw.unnecessary.total) > 0 ? BadgeTone.danger : BadgeTone.success,
            icon: Icons.bolt_outlined,
          ),

          if (savingsRate != null) ...[
            const Gap(S.xl),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(S.lg),
              decoration: BoxDecoration(
                color: t.surfaceMuted.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(R.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Savings rate'),
                  const Gap(S.sm),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Amount(
                        '$savingsRate%',
                        size: AppType.display,
                        color: savingsRate >= 0 ? t.primary : t.danger,
                      ),
                      const GapX(S.sm),
                      Padding(
                        padding: const EdgeInsets.only(bottom: S.xs),
                        child: Muted('of everything you earned', size: AppType.caption),
                      ),
                    ],
                  ),
                  const Gap(S.md),
                  ProgressBar(
                    value: savingsRate.toDouble().clamp(0, 100),
                    label: 'Savings rate',
                    tone: savingsRate >= 20
                        ? BadgeTone.success
                        : savingsRate >= 0
                            ? BadgeTone.warning
                            : BadgeTone.danger,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.tone,
    required this.icon,
  });

  final String label;
  final String value;
  final BadgeTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final (bg, fg) = AppBadge.colorsFor(context, tone);

    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(R.md)),
          child: Icon(icon, size: 17, color: fg),
        ),
        const GapX(S.md),
        Expanded(child: Muted(label, size: AppType.bodySm)),
        const GapX(S.sm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppType.bodySm,
              fontWeight: W.bold,
              color: t.foreground,
            ),
          ),
        ),
      ],
    );
  }
}
