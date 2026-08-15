// Showing money move, rather than describing it.
//
// Every screen that shifts money used to explain itself in a sentence, and the
// sentences disagreed: one said "up to X still fits", another said nothing at
// all and let the server refuse. A figure going from one value to another is
// the same fact in a form you can check at a glance, so it is the only form
// used here.
//
// Two shapes cover everything:
//
// * MoneyImpact   what a pending action will do, previewed live as it is
//   typed. Used by the fill/give-back sheet and the transfer sheet.
// * MoneyFlow   what a recorded movement already did, as two sides and an
//   arrow. Used by the transaction sheet for cross-currency transfers and for
//   a plan spend that one wallet fronted for another.
import 'package:flutter/material.dart';

import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import '../core/utils/format.dart';
import 'ui.dart';

/// One figure that is about to change.
@immutable
class MoneyDelta {
  const MoneyDelta({
    required this.label,
    required this.before,
    required this.after,
    required this.currency,
    this.caption,
    this.icon = Icons.account_balance_wallet_outlined,
    this.color,
  });

  final String label;
  final double before;
  final double after;
  final String currency;

  /// What the figure *is*   "available", "in the pot". Two words at most.
  final String? caption;
  final IconData icon;
  final Color? color;

  bool get changed => (after - before).abs() >= 0.005;
  bool get overdrawn => after < -0.005;
}

/// The live preview card. Renders nothing at all until something would actually
/// change, so an untouched form is never decorated with two identical numbers.
class MoneyImpact extends StatelessWidget {
  const MoneyImpact({super.key, required this.rows, this.warning});

  final List<MoneyDelta> rows;

  /// Shown under the figures when the action cannot go through as typed. The
  /// numbers above already show why, so this stays to one line.
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final live = rows.where((r) => r.changed).toList();

    return AnimatedSize(
      duration: Motion.fast,
      curve: Motion.easeOut,
      alignment: Alignment.topCenter,
      child: live.isEmpty
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: S.md,
                vertical: S.md,
              ),
              decoration: BoxDecoration(
                color: t.surfaceMuted.withValues(alpha: t.isDark ? 0.5 : 0.65),
                borderRadius: BorderRadius.circular(R.lg),
                border: Border.all(
                  color: warning != null
                      ? t.danger.withValues(alpha: 0.35)
                      : t.border.withValues(alpha: 0.7),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < live.length; i++) ...[
                    if (i > 0) const Gap(S.sm),
                    _DeltaRow(delta: live[i]),
                  ],
                  if (warning != null) ...[
                    const Gap(S.sm),
                    Divider(height: 1, color: t.border.withValues(alpha: 0.8)),
                    const Gap(S.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 14,
                          color: t.danger,
                        ),
                        const GapX(S.sm),
                        Expanded(
                          child: Text(
                            warning!,
                            style: TextStyle(
                              fontSize: AppType.caption,
                              height: 1.4,
                              color: t.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _DeltaRow extends StatelessWidget {
  const _DeltaRow({required this.delta});

  final MoneyDelta delta;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final tint = delta.color ?? t.mutedForeground;

    // Money arriving is the only state worth colouring. Money leaving is not a
    // loss   it is the thing the user asked for   so it stays foreground, and
    // only an impossible result goes red.
    final afterColor = delta.overdrawn
        ? t.danger
        : delta.after > delta.before
        ? t.primary
        : t.foreground;

    return Row(
      children: [
        IconTile(icon: delta.icon, color: tint, size: 30, radius: R.sm),
        const GapX(S.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                delta.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppType.bodySm,
                  fontWeight: W.semibold,
                  color: t.foreground,
                ),
              ),
              if (delta.caption != null)
                Muted(delta.caption!, size: AppType.micro, maxLines: 1),
            ],
          ),
        ),
        const GapX(S.sm),
        // Deliberately not flexible. The figures are the point of the row, so
        // they take their natural width first and the label ellipsises into
        // whatever is left   the other way round shrinks the numbers.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatMoney(delta.before, currency: ''),
              style: TextStyle(
                fontSize: AppType.label,
                color: t.mutedForeground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Icon(
                Icons.arrow_right_alt_rounded,
                size: 15,
                color: t.mutedForeground,
              ),
            ),
            AnimatedNumber(
              value: delta.after,
              builder: (context, v) => Amount(
                formatMoney(v, currency: delta.currency),
                size: AppType.body,
                color: afterColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One side of a [MoneyFlow]   a wallet, a plan, a currency.
@immutable
class FlowSide {
  const FlowSide({
    required this.label,
    required this.amount,
    this.caption,
    this.icon = Icons.account_balance_wallet_outlined,
    this.color,
  });

  final String label;

  /// Pre-formatted   the two sides of a cross-currency transfer are not in the
  /// same denomination, so this widget never formats money itself.
  final String amount;

  /// One word for what happened to this side: "paid", "freed", "arrived".
  final String? caption;
  final IconData icon;
  final Color? color;
}

/// A movement that already happened, as two sides and an arrow.
///
/// This exists because two facts the ledger records were being dropped on the
/// floor: which wallet's reservation a plan spend actually freed, and what
/// landed on the far side of a transfer that crossed a currency. Both are
/// two-sided by nature, and both were being rendered as a single figure.
class MoneyFlow extends StatelessWidget {
  const MoneyFlow({
    super.key,
    required this.from,
    required this.to,
    this.footnote,
    this.tone,
  });

  final FlowSide from;
  final FlowSide to;

  /// The exchange rate, or anything else that only makes sense under both
  /// sides at once. Optional, and usually absent.
  final String? footnote;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final accent = tone ?? t.accent;

    return Container(
      padding: const EdgeInsets.all(S.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: t.isDark ? 0.09 : 0.06),
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _Side(side: from, align: CrossAxisAlignment.start)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.sm),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_right_alt_rounded,
                    size: 16,
                    color: accent,
                  ),
                ),
              ),
              Expanded(child: _Side(side: to, align: CrossAxisAlignment.end)),
            ],
          ),
          if (footnote != null) ...[
            const Gap(S.sm),
            Divider(height: 1, color: accent.withValues(alpha: 0.18)),
            const Gap(S.sm),
            Muted(footnote!, size: AppType.caption),
          ],
        ],
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.side, required this.align});

  final FlowSide side;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final end = align == CrossAxisAlignment.end;

    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: end ? TextDirection.rtl : TextDirection.ltr,
          children: [
            IconTile(
              icon: side.icon,
              color: side.color ?? t.mutedForeground,
              size: 26,
              radius: R.sm,
            ),
            const GapX(S.xs),
            Flexible(
              child: Text(
                side.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: end ? TextAlign.right : TextAlign.left,
                style: TextStyle(
                  fontSize: AppType.bodySm,
                  fontWeight: W.semibold,
                  color: t.foreground,
                ),
              ),
            ),
          ],
        ),
        const Gap(S.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: end ? Alignment.centerRight : Alignment.centerLeft,
          child: Amount(side.amount, size: AppType.body),
        ),
        if (side.caption != null)
          Muted(side.caption!, size: AppType.micro, maxLines: 1),
      ],
    );
  }
}
