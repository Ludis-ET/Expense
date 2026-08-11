import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:santim/core/theme/theme.dart';
import 'package:santim/core/theme/tokens.dart';
import 'package:santim/core/utils/format.dart';
import 'package:santim/widgets/ui.dart';

void main() {
  group('formatting', () {
    test('money formats without decimals by default', () {
      expect(formatMoney(1234.56, currency: 'ETB'), contains('1,235'));
      expect(formatMoney(1234.5, currency: 'ETB', decimals: true), contains('.50'));
    });

    test('hidden money keeps the currency symbol', () {
      expect(formatHiddenMoney('USD'), r'$ ••••••');
    });

    test('signed money carries the right sign per kind', () {
      expect(formatSignedMoney(100, 'INCOME'), startsWith('+'));
      expect(formatSignedMoney(100, 'EXPENSE'), startsWith('−'));
      expect(formatSignedMoney(100, 'TRANSFER'), isNot(startsWith('+')));
    });

    test('percentages are signed with a true minus', () {
      expect(formatPct(12.4), '+12%');
      expect(formatPct(-8.6), '−9%');
      expect(formatPct(null), '-');
    });

    test('Ethiopian conversion runs ~7-8 years behind', () {
      final e = toEthiopian(DateTime(2026, 8, 11));
      expect(e.year, 2018);
      expect(e.monthName, isNotEmpty);
    });
  });

  testWidgets('brand mark and wordmark render in both themes', (tester) async {
    for (final tokens in [SantimTokens.light, SantimTokens.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(tokens),
          home: const Scaffold(
            body: Column(children: [BrandMark(), BrandWord()]),
          ),
        ),
      );
      expect(find.text('S'), findsOneWidget);
      expect(find.byType(BrandWord), findsOneWidget);
    }
  });

  testWidgets('progress bar clamps out-of-range values', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(SantimTokens.light),
        home: const Scaffold(
          body: Column(
            children: [
              ProgressBar(value: 240),
              ProgressBar(value: -40),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ProgressBar), findsNWidgets(2));
  });
}
