import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:santim/core/theme/theme.dart';
import 'package:santim/core/theme/tokens.dart';
import 'package:santim/state/prefs_state.dart';
import 'package:santim/widgets/charts.dart';
import 'package:santim/widgets/ui.dart';

Widget _wrap(Widget child, {TextScaler? scaler}) => MaterialApp(
  theme: buildTheme(SantimTokens.light),
  home: MediaQuery(
    data: MediaQueryData(textScaler: scaler ?? TextScaler.noScaling),
    child: Scaffold(body: child),
  ),
);

void main() {
  group('type scale', () {
    test('snap maps legacy sizes onto a scale step', () {
      // The half-point sizes the codebase was littered with.
      expect(AppType.snap(13.5), AppType.bodySm);
      expect(AppType.snap(11.5), AppType.caption);
      expect(AppType.snap(12.5), AppType.label);
      expect(AppType.snap(16.5), AppType.lead);
    });

    test('snap is idempotent on values already on the scale', () {
      for (final step in [
        AppType.micro,
        AppType.caption,
        AppType.label,
        AppType.bodySm,
        AppType.body,
        AppType.lead,
        AppType.heading,
        AppType.figure,
        AppType.display,
        AppType.hero,
      ]) {
        expect(AppType.snap(step), step, reason: 'step $step moved');
      }
    });

    test('snap biases downward on a tie so nothing overflows', () {
      // 15 sits exactly between body (14) and lead (16).
      expect(AppType.snap(15), AppType.body);
    });

    test('snap clamps rather than extrapolating past the ends', () {
      expect(AppType.snap(2), AppType.micro);
      expect(AppType.snap(120), AppType.hero);
    });
  });

  group('spoken amounts', () {
    test('moves a leading currency code to the end', () {
      expect(spokenAmount('ETB 1,234.50'), '1,234.50 ETB');
    });

    test('reads a leading minus as a word', () {
      expect(spokenAmount('−240 br'), startsWith('minus '));
      expect(spokenAmount('-240 br'), startsWith('minus '));
    });

    test('says hidden rather than spelling out the mask', () {
      expect(spokenAmount('••••••'), 'hidden');
    });

    test('leaves a plain number alone', () {
      expect(spokenAmount('42'), '42');
    });
  });

  group('chart descriptions', () {
    test('ranks shares and reports the remainder', () {
      final summary = describeShares('Spending', const [
        Slice(label: 'Groceries', value: 50, color: Colors.green),
        Slice(label: 'Transport', value: 30, color: Colors.blue),
        Slice(label: 'Gifts', value: 20, color: Colors.orange),
      ], take: 2);

      expect(summary, startsWith('Spending. Groceries 50 percent'));
      expect(summary, contains('Transport 30 percent'));
      expect(summary, contains('and 1 more'));
    });

    test('says so when there is nothing to describe', () {
      expect(describeShares('Spending', const []), contains('No data yet'));
    });
  });

  group('dashboard preferences', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('hidden cards round-trip', () async {
      final prefs = PrefsState(await SharedPreferences.getInstance());
      expect(prefs.isCardVisible('weekly'), isTrue);

      await prefs.setCardVisible('weekly', false);
      expect(prefs.isCardVisible('weekly'), isFalse);

      await prefs.setCardVisible('weekly', true);
      expect(prefs.isCardVisible('weekly'), isTrue);
    });

    test('applyOrder honours the user order', () async {
      final prefs = PrefsState(await SharedPreferences.getInstance());
      await prefs.setCardOrder(['c', 'a', 'b']);
      expect(prefs.applyOrder(['a', 'b', 'c']), ['c', 'a', 'b']);
    });

    test('applyOrder keeps cards the user has never seen', () async {
      final prefs = PrefsState(await SharedPreferences.getInstance());
      await prefs.setCardOrder(['b', 'a']);
      // 'new' shipped in a later release and is absent from the saved order.
      final sorted = prefs.applyOrder(['a', 'b', 'new']);
      expect(sorted.take(2), ['b', 'a']);
      expect(sorted, contains('new'));
      expect(sorted.length, 3);
    });

    test('applyOrder is a no-op before the user reorders anything', () async {
      final prefs = PrefsState(await SharedPreferences.getInstance());
      expect(prefs.applyOrder(['a', 'b', 'c']), ['a', 'b', 'c']);
    });

    test('collapsed sections round-trip', () async {
      final prefs = PrefsState(await SharedPreferences.getInstance());
      expect(prefs.isCollapsed('recentTx'), isFalse);
      await prefs.setCollapsed('recentTx', true);
      expect(prefs.isCollapsed('recentTx'), isTrue);
    });
  });

  group('touch targets', () {
    testWidgets('small buttons still get a 48dp hit area', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Center(
            child: AppButton(label: 'Fund', size: BtnSize.sm, onPressed: () {}),
          ),
        ),
      );

      // The drawn pill is deliberately smaller than the tappable box.
      final pill = tester.getSize(
        find
            .descendant(
              of: find.byType(AppButton),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(pill.height, 40);

      final target = tester.getSize(find.byType(ConstrainedBox).first);
      expect(target.height, greaterThanOrEqualTo(48));
    });

    testWidgets('icon pills are tappable across the full 48dp', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(
          Center(
            child: IconPill(
              icon: Icons.search,
              tooltip: 'Search',
              onTap: () => taps++,
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(IconPill)).height, 48);

      // A tap 22dp from centre lands outside the 38dp circle but inside the
      // hit area   this is exactly the mis-tap the old 38dp pill lost.
      final centre = tester.getCenter(find.byType(IconPill));
      await tester.tapAt(centre + const Offset(0, 22));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('large text', () {
    testWidgets('a stat row survives a 1.6x text scaler', (tester) async {
      await tester.pumpWidget(
        _wrap(
          scaler: const TextScaler.linear(1.6),
          Row(
            children: [
              const Expanded(child: Muted('Spent from plans')),
              Amount('ETB 12,345', size: AppType.figure),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
