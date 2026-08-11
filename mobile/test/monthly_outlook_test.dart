import 'package:flutter_test/flutter_test.dart';

import 'package:santim/core/utils/monthly_outlook.dart';
import 'package:santim/models/models.dart';
import 'package:santim/models/outlook_history.dart';

RecurringRule _rule({
  required String id,
  required String name,
  required double amount,
  required TxKind kind,
  String? categoryId,
  Frequency frequency = Frequency.monthly,
  int interval = 1,
  int? dayOfMonth,
}) => RecurringRule.fromJson({
  'id': id,
  'name': name,
  'kind': kind == TxKind.income ? 'INCOME' : 'EXPENSE',
  'amount': amount.toStringAsFixed(2),
  'currency': 'ETB',
  'accountId': 'acc-1',
  'categoryId': categoryId,
  'frequency': frequency.name.toUpperCase(),
  'interval': interval,
  'dayOfMonth': dayOfMonth,
  'nextRun': DateTime.utc(2026, 8, dayOfMonth ?? 1).toIso8601String(),
  'autoPost': true,
  'active': true,
  'postedCount': 0,
});

BudgetRow _plan({
  required String id,
  required String name,
  required double planned,
  String? categoryId,
  bool unplanned = false,
}) => BudgetRow.fromJson({
  'id': id,
  'name': name,
  'categoryId': categoryId,
  'kind': unplanned ? 'UNPLANNED' : 'RECURRING',
  'isUnplanned': unplanned,
  'recurrenceUnit': 'MONTH',
  'recurrenceInterval': 1,
  'currency': 'ETB',
  'state': 'ACTIVE',
  'plannedAmount': planned.toStringAsFixed(2),
  'openingPlanned': planned.toStringAsFixed(2),
  'adjustedThisCycle': '0.00',
  'fundedAmount': '0.00',
  'carriedIn': '0.00',
  'fillable': '0.00',
  'spentAmount': '0.00',
  'balance': '0.00',
  'pctFunded': 0,
  'pctOfPlan': 0,
  'pctSpentOfFunded': 0,
  'cycleIndex': 0,
});

OutlookHistory _history({
  double median = 0,
  int sampleMonths = 0,
  List<Map<String, dynamic>> months = const [],
}) => OutlookHistory.fromJson({
  'currency': 'ETB',
  'months': months,
  'unplannedMedian': median.toStringAsFixed(2),
  'unplannedSampleMonths': sampleMonths,
  'repeatCandidates': const [],
  'patternWindowDays': 90,
});

MonthlyOutlook _build({
  List<RecurringRule> rules = const [],
  List<BudgetRow> budgets = const [],
  OutlookHistory? history,
  DateTime? now,
}) => buildMonthlyOutlook(
  currency: 'ETB',
  rules: rules,
  budgets: budgets,
  month: null,
  history: history,
  now: now ?? DateTime(2026, 8, 15),
);

void main() {
  group('income target layers', () {
    test('floor counts recurring bills only', () {
      final o = _build(
        rules: [
          _rule(id: 'r1', name: 'Rent', amount: 5000, kind: TxKind.expense),
          _rule(id: 'r2', name: 'Internet', amount: 1000, kind: TxKind.expense),
        ],
        budgets: [_plan(id: 'b1', name: 'Groceries', planned: 3000)],
      );

      expect(o.requiredFor(OutlookTarget.floor), 6000);
    });

    test('steady adds plans on top of the floor', () {
      final o = _build(
        rules: [
          _rule(id: 'r1', name: 'Rent', amount: 5000, kind: TxKind.expense),
        ],
        budgets: [_plan(id: 'b1', name: 'Groceries', planned: 3000)],
      );

      expect(o.requiredFor(OutlookTarget.steady), 8000);
    });

    test('comfortable adds the buffer', () {
      final o = _build(
        rules: [
          _rule(id: 'r1', name: 'Rent', amount: 5000, kind: TxKind.expense),
        ],
        history: _history(median: 900, sampleMonths: 3),
      );

      expect(o.buffer, 900);
      expect(o.requiredFor(OutlookTarget.comfortable), 5900);
    });
  });

  group('deduplication', () {
    test('a plan for a category a bill already pays adds nothing', () {
      final o = _build(
        rules: [
          _rule(
            id: 'r1',
            name: 'Rent',
            amount: 5000,
            kind: TxKind.expense,
            categoryId: 'cat-rent',
          ),
        ],
        budgets: [
          _plan(
            id: 'b1',
            name: 'Rent envelope',
            planned: 5000,
            categoryId: 'cat-rent',
          ),
        ],
      );

      // The old maths returned 10,000 for the same 5,000 of rent.
      expect(o.requiredFor(OutlookTarget.steady), 5000);
      expect(o.planSpend, 0);
      expect(o.duplicateCategories, 1);
      expect(o.planLines.single.coveredByRule, isTrue);
      // The plan still shows its own amount to the user.
      expect(o.planLines.single.displayAmount, 5000);
    });

    test('a plan larger than the bill adds only the difference', () {
      final o = _build(
        rules: [
          _rule(
            id: 'r1',
            name: 'Rent',
            amount: 5000,
            kind: TxKind.expense,
            categoryId: 'cat-rent',
          ),
        ],
        budgets: [
          _plan(
            id: 'b1',
            name: 'Rent envelope',
            planned: 6500,
            categoryId: 'cat-rent',
          ),
        ],
      );

      expect(o.planSpend, 1500);
      expect(o.requiredFor(OutlookTarget.steady), 6500);
    });

    test('a plan in an unrelated category is untouched', () {
      final o = _build(
        rules: [
          _rule(
            id: 'r1',
            name: 'Rent',
            amount: 5000,
            kind: TxKind.expense,
            categoryId: 'cat-rent',
          ),
        ],
        budgets: [
          _plan(
            id: 'b1',
            name: 'Groceries',
            planned: 3000,
            categoryId: 'cat-food',
          ),
        ],
      );

      expect(o.planSpend, 3000);
      expect(o.duplicateCategories, 0);
    });
  });

  group('surprise buffer', () {
    test('prefers a cushion the user set over history', () {
      final o = _build(
        budgets: [
          _plan(id: 'u1', name: 'Unplanned', planned: 1500, unplanned: true),
        ],
        history: _history(median: 400, sampleMonths: 4),
      );

      expect(o.buffer, 1500);
      expect(o.bufferBasis, BufferBasis.planned);
    });

    test('falls back to the median of completed months', () {
      final o = _build(history: _history(median: 750, sampleMonths: 3));

      expect(o.buffer, 750);
      expect(o.bufferBasis, BufferBasis.median);
      expect(o.bufferSampleMonths, 3);
    });

    test('is zero with no cushion and no history', () {
      final o = _build(
        rules: [
          _rule(id: 'r1', name: 'Rent', amount: 5000, kind: TxKind.expense),
        ],
      );

      expect(o.buffer, 0);
      expect(o.bufferBasis, BufferBasis.none);
      expect(
        o.requiredFor(OutlookTarget.comfortable),
        o.requiredFor(OutlookTarget.steady),
      );
    });

    test('never grows from the current cycle\'s unplanned spending', () {
      // An Unplanned envelope with no planned cushion but heavy spend this
      // cycle used to inflate the target   the bug that started all this.
      final spent = BudgetRow.fromJson({
        'id': 'u1',
        'name': 'Unplanned',
        'kind': 'UNPLANNED',
        'isUnplanned': true,
        'recurrenceUnit': 'MONTH',
        'recurrenceInterval': 1,
        'currency': 'ETB',
        'state': 'ACTIVE',
        'plannedAmount': '0.00',
        'openingPlanned': '0.00',
        'adjustedThisCycle': '0.00',
        'fundedAmount': '0.00',
        'carriedIn': '0.00',
        'fillable': '0.00',
        'spentAmount': '9999.00',
        'balance': '0.00',
        'pctFunded': 0,
        'pctOfPlan': 0,
        'pctSpentOfFunded': 0,
        'cycleIndex': 0,
      });

      final o = _build(budgets: [spent]);
      expect(o.buffer, 0);
    });
  });

  group('coverage', () {
    test('coveredTarget reports the richest target the income clears', () {
      final o = _build(
        rules: [
          _rule(id: 'r1', name: 'Rent', amount: 5000, kind: TxKind.expense),
          _rule(id: 'i1', name: 'Salary', amount: 8000, kind: TxKind.income),
        ],
        budgets: [_plan(id: 'b1', name: 'Groceries', planned: 3000)],
        history: _history(median: 1000, sampleMonths: 3),
      );

      // floor 5000, steady 8000, comfortable 9000 against income 8000.
      expect(o.coveredTarget, OutlookTarget.steady);
      expect(o.gapFor(OutlookTarget.comfortable), 1000);
      expect(o.gapFor(OutlookTarget.floor), -3000);
    });

    test('coveredTarget is null when even the bills are not covered', () {
      final o = _build(
        rules: [
          _rule(id: 'r1', name: 'Rent', amount: 5000, kind: TxKind.expense),
          _rule(id: 'i1', name: 'Salary', amount: 2000, kind: TxKind.income),
        ],
      );

      expect(o.coveredTarget, isNull);
    });
  });

  group('per-payday', () {
    test('splits the monthly target across pay periods', () {
      final o = _build(
        rules: [
          _rule(
            id: 'r1',
            name: 'Rent',
            amount: 3043.6875,
            kind: TxKind.expense,
          ),
        ],
      );

      expect(
        o.perPeriod(OutlookTarget.floor, PayCadence.monthly),
        closeTo(3043.69, 0.01),
      );
      expect(
        o.perPeriod(OutlookTarget.floor, PayCadence.weekly),
        closeTo(700, 0.01),
      );
    });
  });

  group('break-even day', () {
    test('is the day income overtakes the bills', () {
      final o = _build(
        rules: [
          _rule(
            id: 'r1',
            name: 'Rent',
            amount: 5000,
            kind: TxKind.expense,
            dayOfMonth: 5,
          ),
          _rule(
            id: 'i1',
            name: 'Salary',
            amount: 9000,
            kind: TxKind.income,
            dayOfMonth: 25,
          ),
        ],
        now: DateTime(2026, 8, 15),
      );

      expect(o.breakEvenDay, 25);
    });

    test('is null when income never catches up', () {
      final o = _build(
        rules: [
          _rule(
            id: 'r1',
            name: 'Rent',
            amount: 5000,
            kind: TxKind.expense,
            dayOfMonth: 5,
          ),
          _rule(
            id: 'i1',
            name: 'Salary',
            amount: 1000,
            kind: TxKind.income,
            dayOfMonth: 25,
          ),
        ],
      );

      expect(o.breakEvenDay, isNull);
    });

    test('is null when there are no bills at all', () {
      final o = _build(
        rules: [
          _rule(id: 'i1', name: 'Salary', amount: 9000, kind: TxKind.income),
        ],
      );

      expect(o.breakEvenDay, isNull);
    });
  });

  group('repeat candidates', () {
    test('never contribute to any target', () {
      final history = OutlookHistory.fromJson({
        'currency': 'ETB',
        'months': const [],
        'unplannedMedian': '0.00',
        'unplannedSampleMonths': 0,
        'repeatCandidates': [
          {
            'payee': 'Kaldis',
            'kind': 'EXPENSE',
            'count': 12,
            'avgAmount': '90.00',
            'monthlyAmount': '1080.00',
            'avgGapDays': 3,
            'cadence': 'a few times a week',
          },
        ],
        'patternWindowDays': 90,
      });

      final o = _build(
        rules: [
          _rule(id: 'r1', name: 'Rent', amount: 5000, kind: TxKind.expense),
        ],
        history: history,
      );

      expect(o.repeatCandidates, hasLength(1));
      expect(o.requiredFor(OutlookTarget.comfortable), 5000);
    });
  });

  group('insights', () {
    test('explain where the buffer came from', () {
      final o = _build(
        rules: [
          _rule(id: 'r1', name: 'Rent', amount: 5000, kind: TxKind.expense),
        ],
        history: _history(median: 800, sampleMonths: 3),
      );

      expect(
        o.insights.any(
          (i) => i.contains('median unplanned spend over 3 completed months'),
        ),
        isTrue,
      );
    });

    test('flag a deduplicated plan rather than hiding it', () {
      final o = _build(
        rules: [
          _rule(
            id: 'r1',
            name: 'Rent',
            amount: 5000,
            kind: TxKind.expense,
            categoryId: 'cat-rent',
          ),
        ],
        budgets: [
          _plan(id: 'b1', name: 'Rent', planned: 5000, categoryId: 'cat-rent'),
        ],
      );

      expect(
        o.insights.any((i) => i.contains('counted once, not twice')),
        isTrue,
      );
    });
  });
}
