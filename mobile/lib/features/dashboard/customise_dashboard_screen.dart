import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../core/layout.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../state/prefs_state.dart';
import '../../widgets/ui.dart';
import 'dashboard_layout.dart';

/// Lets the user switch dashboard cards off and drag them into the order they
/// want. Someone who never uses the wishlist should not scroll past it every
/// time they open the app.
class CustomiseDashboardScreen extends StatelessWidget {
  const CustomiseDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PrefsState>();
    final hiddenCount = prefs.hiddenCards.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customise dashboard'),
        actions: [
          if (hiddenCount > 0 || prefs.cardOrder.isNotEmpty)
            TextButton(
              onPressed: () {
                Haptics.commit();
                prefs.resetDashboard();
                toast(context, 'Dashboard reset');
              },
              child: const Text('Reset'),
            ),
          const GapX(S.sm),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(S.lg, S.lg, S.lg, ShellLayout.bottomClearance(context)),
        children: [
          PageHeader(
            title: 'Your cards',
            description:
                'Drag to reorder, switch off what you do not use. '
                'Cards with nothing to show are hidden automatically, so a card '
                'switched on here may still not appear until it has data.',
          ),
          const _Group(
            title: 'Worth knowing',
            hint: 'These ride in the swipeable strip under your balance.',
            specs: kInsightCards,
          ),
          const Gap(S.xl),
          const _Group(
            title: 'Below the strip',
            hint: 'Sections and cards down the page.',
            specs: kBodyCards,
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.hint, required this.specs});

  final String title;
  final String hint;
  final List<DashboardCardSpec> specs;

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PrefsState>();
    final ids = prefs.applyOrder(specs.map((s) => s.id).toList());
    final byId = {for (final s in specs) s.id: s};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title, hint: hint),
        const Gap(S.sm),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: S.sm),
          child: ReorderableListView.builder(
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: ids.length,
            onReorder: (from, to) {
              Haptics.select();
              final next = [...ids];
              final moved = next.removeAt(from);
              next.insert(from < to ? to - 1 : to, moved);

              // Persist the full order across both groups so the two lists
              // never fight over a shared rank table.
              final other = kAllDashboardCards
                  .map((s) => s.id)
                  .where((id) => !next.contains(id))
                  .toList();
              final merged = specs == kInsightCards ? [...next, ...other] : [...other, ...next];
              prefs.setCardOrder(merged);
            },
            itemBuilder: (context, i) {
              final spec = byId[ids[i]]!;
              return _CardRow(
                key: ValueKey(spec.id),
                spec: spec,
                index: i,
                visible: prefs.isCardVisible(spec.id),
                onChanged: (v) {
                  Haptics.toggle();
                  prefs.setCardVisible(spec.id, v);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({
    super.key,
    required this.spec,
    required this.index,
    required this.visible,
    required this.onChanged,
  });

  final DashboardCardSpec spec;
  final int index;
  final bool visible;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.md, vertical: S.xxs),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Semantics(
              label: 'Reorder ${spec.label}',
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                child: Icon(Icons.drag_indicator, size: 20, color: t.mutedForeground),
              ),
            ),
          ),
          IconTile(icon: spec.icon, color: visible ? t.primary : t.mutedForeground, size: 34),
          const GapX(S.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec.label,
                  style: TextStyle(
                    fontSize: AppType.bodySm,
                    fontWeight: W.semibold,
                    color: visible ? t.foreground : t.mutedForeground,
                  ),
                ),
                Muted(spec.blurb, size: AppType.caption, maxLines: 2),
              ],
            ),
          ),
          const GapX(S.sm),
          Switch(
            value: visible,
            onChanged: onChanged,
            activeThumbColor: t.primaryForeground,
            activeTrackColor: t.primary,
          ),
        ],
      ),
    );
  }
}
