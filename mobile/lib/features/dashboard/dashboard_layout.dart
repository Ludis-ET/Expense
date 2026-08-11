import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../state/prefs_state.dart';
import '../../widgets/glass.dart';

/// Every card the dashboard can show, in its default order. The customise
/// screen renders this list; the dashboard filters and sorts by it.
///
/// Ids are persisted, so renaming one drops a user's preference for that card.
class DashboardCardSpec {
  const DashboardCardSpec({
    required this.id,
    required this.label,
    required this.blurb,
    required this.icon,
  });

  final String id;
  final String label;
  final String blurb;
  final IconData icon;
}

/// Insight cards — these ride in the tier-2 carousel.
const kInsightCards = <DashboardCardSpec>[
  DashboardCardSpec(
    id: 'insight',
    label: 'Smart insight',
    blurb: 'The single thing most worth knowing this month.',
    icon: Icons.lightbulb_outline,
  ),
  DashboardCardSpec(
    id: 'health',
    label: 'Financial health',
    blurb: 'Your score and the factors moving it.',
    icon: Icons.favorite_outline,
  ),
  DashboardCardSpec(
    id: 'outlook',
    label: 'Monthly outlook',
    blurb: 'What is already committed before you spend anything.',
    icon: Icons.calendar_month_outlined,
  ),
  DashboardCardSpec(
    id: 'pace',
    label: 'Spending pace',
    blurb: 'Whether today’s rate lands you inside the month.',
    icon: Icons.speed_outlined,
  ),
  DashboardCardSpec(
    id: 'weekly',
    label: 'Weekly snapshot',
    blurb: 'This week against last week.',
    icon: Icons.view_week_outlined,
  ),
  DashboardCardSpec(
    id: 'streaks',
    label: 'Spending streaks',
    blurb: 'No-spend days and your current run.',
    icon: Icons.local_fire_department_outlined,
  ),
];

/// Cards in the scrolling body below the carousel.
const kBodyCards = <DashboardCardSpec>[
  DashboardCardSpec(
    id: 'stats',
    label: 'Quick stats',
    blurb: 'Net, average daily spend, unnecessary, upcoming bills.',
    icon: Icons.grid_view_outlined,
  ),
  DashboardCardSpec(
    id: 'recentTx',
    label: 'Recent transactions',
    blurb: 'Your last few entries.',
    icon: Icons.receipt_long_outlined,
  ),
  DashboardCardSpec(
    id: 'budgets',
    label: 'Budget plans',
    blurb: 'Progress on each funded envelope.',
    icon: Icons.savings_outlined,
  ),
  DashboardCardSpec(
    id: 'setAside',
    label: 'Set aside',
    blurb: 'Money locked into plans, and what has been filled.',
    icon: Icons.lock_outline,
  ),
  DashboardCardSpec(
    id: 'upcoming',
    label: 'Upcoming recurring',
    blurb: 'Bills due in the next seven days.',
    icon: Icons.event_repeat_outlined,
  ),
  DashboardCardSpec(
    id: 'tabWishlist',
    label: 'Tab & wishlist',
    blurb: 'What you are owed and what you are saving for.',
    icon: Icons.card_giftcard_outlined,
  ),
  DashboardCardSpec(
    id: 'familySupport',
    label: 'Family support',
    blurb: 'Money sent to family this month.',
    icon: Icons.diversity_3_outlined,
  ),
  DashboardCardSpec(
    id: 'categoryHeat',
    label: 'Category alerts',
    blurb: 'Categories running hotter than usual.',
    icon: Icons.whatshot_outlined,
  ),
  DashboardCardSpec(
    id: 'household',
    label: 'Household',
    blurb: 'Shared spending, when a household is set up.',
    icon: Icons.home_outlined,
  ),
  DashboardCardSpec(
    id: 'analytics',
    label: 'Full analytics link',
    blurb: 'Shortcut to trends, heatmap, burn rate and payees.',
    icon: Icons.bar_chart_rounded,
  ),
];

List<DashboardCardSpec> get kAllDashboardCards => [...kInsightCards, ...kBodyCards];

/// A horizontally paged strip of insight cards. Collapses what used to be six
/// stacked full-width cards — roughly five screen-heights of scrolling — into
/// one screen height the user swipes through.
///
/// Height tracks the **current** page (animated), so short insights are not
/// forced to match a tall sibling like Financial Health.
class InsightCarousel extends StatefulWidget {
  const InsightCarousel({super.key, required this.pages});

  final List<Widget> pages;

  @override
  State<InsightCarousel> createState() => _InsightCarouselState();
}

class _InsightCarouselState extends State<InsightCarousel> {
  late final PageController _controller = PageController(viewportFraction: 0.93);
  int _page = 0;
  final Map<int, double> _heights = {};
  static const _fallbackHeight = 160.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant InsightCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pages.length != widget.pages.length) {
      _heights.clear();
      _page = _page.clamp(0, math.max(0, widget.pages.length - 1));
    }
  }

  void _reportHeight(int index, double height) {
    if (height <= 0) return;
    final prev = _heights[index];
    if (prev != null && (prev - height).abs() < 1) return;
    setState(() => _heights[index] = height);
  }

  double get _currentHeight => _heights[_page] ?? _fallbackHeight;

  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) return const SizedBox.shrink();
    if (widget.pages.length == 1) return widget.pages.single;

    final t = context.t;

    return Column(
      children: [
        AnimatedSize(
          duration: Motion.enter,
          curve: Motion.easeOut,
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: _currentHeight,
            width: double.infinity,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.pages.length,
              padEnds: false,
              onPageChanged: (i) {
                Haptics.select();
                setState(() => _page = i);
              },
              itemBuilder: (_, i) => Padding(
                padding: EdgeInsets.only(right: i == widget.pages.length - 1 ? 0 : S.sm),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _MeasureSize(
                    onChange: (size) => _reportHeight(i, size.height),
                    child: widget.pages[i],
                  ),
                ),
              ),
            ),
          ),
        ),
        const Gap(S.md),
        Semantics(
          label: 'Insight ${_page + 1} of ${widget.pages.length}',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.pages.length; i++)
                AnimatedContainer(
                  duration: Motion.fast,
                  curve: Motion.easeOut,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? t.primary : t.border,
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Reports child layout size upward without affecting paint.
class _MeasureSize extends StatefulWidget {
  const _MeasureSize({required this.onChange, required this.child});

  final ValueChanged<Size> onChange;
  final Widget child;

  @override
  State<_MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<_MeasureSize> {
  Size? _last;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = context.size;
      if (size == null || size == _last) return;
      _last = size;
      widget.onChange(size);
    });
    return widget.child;
  }
}

/// A dashboard section that remembers whether the user left it open. Replaces
/// the old pattern of rendering every block expanded, forever.
class CollapsibleSection extends StatelessWidget {
  const CollapsibleSection({
    super.key,
    required this.id,
    required this.title,
    required this.child,
    this.trailingLabel,
    this.onTrailingTap,
    this.summary,
    this.padding = const EdgeInsets.all(S.lg),
  });

  /// Persisted key for the open/closed state.
  final String id;
  final String title;
  final Widget child;

  /// Optional action shown in the header, e.g. "Manage".
  final String? trailingLabel;
  final VoidCallback? onTrailingTap;

  /// One-line value shown next to the title while collapsed, so closing a
  /// section never hides the number it existed to show.
  final String? summary;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final prefs = context.watch<PrefsState>();
    final open = !prefs.isCollapsed(id);

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            label: title,
            child: InkWell(
              onTap: () {
                Haptics.toggle();
                prefs.setCollapsed(id, open);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(S.lg, S.md, S.md, S.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: AppType.body,
                          fontWeight: W.bold,
                          color: t.foreground,
                        ),
                      ),
                    ),
                    if (!open && summary != null) ...[
                      Flexible(
                        child: Text(
                          summary!,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: AppType.label, color: t.mutedForeground),
                        ),
                      ),
                      const GapX(S.sm),
                    ],
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: Motion.fast,
                      curve: Motion.easeOut,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 22,
                        color: t.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: padding.add(const EdgeInsets.only(top: 0)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  child,
                  if (trailingLabel != null) ...[
                    const Gap(S.md),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: onTrailingTap,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.sm),
                          minimumSize: const Size(0, 44),
                          foregroundColor: t.primary,
                        ),
                        child: Text(
                          trailingLabel!,
                          style: const TextStyle(fontSize: AppType.bodySm, fontWeight: W.semibold),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            crossFadeState: open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: Motion.enter,
            sizeCurve: Motion.easeOut,
            firstCurve: Motion.easeOut,
            secondCurve: Motion.easeOut,
          ),
        ],
      ),
    );
  }
}
