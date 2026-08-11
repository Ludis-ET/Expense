import 'common.dart';
import 'models.dart' show Ref;

/// `GET /analytics/outlook-history`   the history the monthly outlook needs
/// that the dashboard payload cannot provide.
class OutlookHistory {
  const OutlookHistory({
    required this.currency,
    required this.months,
    required this.unplannedMedian,
    required this.unplannedSampleMonths,
    required this.repeatCandidates,
    required this.patternWindowDays,
  });

  final String currency;

  /// Completed months only, oldest first. The current month is excluded on
  /// purpose   it is partial, and letting it in is what made the old buffer
  /// climb as the month went on.
  final List<OutlookMonth> months;

  /// Median unplanned spend across those months. Stable within a month, which
  /// is the whole point: an income target should not move because you had a
  /// bad Tuesday.
  final double unplannedMedian;

  /// How many months the median was taken from   drives the confidence line.
  final int unplannedSampleMonths;

  /// Repeating payees with no recurring rule yet.
  final List<RepeatCandidate> repeatCandidates;

  final int patternWindowDays;

  /// Months where income covered expense, most recent last.
  int get coveredMonths => months.where((m) => m.covered).length;

  factory OutlookHistory.fromJson(Map<String, dynamic> j) => OutlookHistory(
    currency: asStr(j['currency'], 'ETB'),
    months: mapList(j['months'], OutlookMonth.fromJson),
    unplannedMedian: asNum(j['unplannedMedian']),
    unplannedSampleMonths: (asNum(j['unplannedSampleMonths'])).round(),
    repeatCandidates: mapList(j['repeatCandidates'], RepeatCandidate.fromJson),
    patternWindowDays: (asNum(j['patternWindowDays'], 90)).round(),
  );
}

class OutlookMonth {
  const OutlookMonth({
    required this.month,
    required this.income,
    required this.expense,
    required this.unplanned,
    required this.net,
    required this.covered,
  });

  /// `yyyy-MM`.
  final String month;
  final double income;
  final double expense;
  final double unplanned;
  final double net;
  final bool covered;

  factory OutlookMonth.fromJson(Map<String, dynamic> j) => OutlookMonth(
    month: asStr(j['month'], ''),
    income: asNum(j['income']),
    expense: asNum(j['expense']),
    unplanned: asNum(j['unplanned']),
    net: asNum(j['net']),
    covered: j['covered'] == true,
  );
}

/// A payee seen often enough to look like a commitment, with no rule behind it.
class RepeatCandidate {
  const RepeatCandidate({
    required this.payee,
    required this.kind,
    required this.count,
    required this.avgAmount,
    required this.monthlyAmount,
    required this.avgGapDays,
    required this.cadence,
    this.categoryId,
    this.category,
    this.lastSeen,
  });

  final String payee;

  /// `INCOME` or `EXPENSE`.
  final String kind;
  final int count;
  final double avgAmount;

  /// A true monthly rate, derived from the gap between occurrences   not the
  /// average of one occurrence, which is what the old client-side guess used.
  final double monthlyAmount;

  final int avgGapDays;

  /// Human phrasing of the cadence, e.g. "about weekly".
  final String cadence;

  final String? categoryId;
  final Ref? category;
  final DateTime? lastSeen;

  bool get isExpense => kind == 'EXPENSE';

  factory RepeatCandidate.fromJson(Map<String, dynamic> j) => RepeatCandidate(
    payee: asStr(j['payee'], ''),
    kind: asStr(j['kind'], 'EXPENSE'),
    count: (asNum(j['count'])).round(),
    avgAmount: asNum(j['avgAmount']),
    monthlyAmount: asNum(j['monthlyAmount']),
    avgGapDays: (asNum(j['avgGapDays'])).round(),
    cadence: asStr(j['cadence'], ''),
    categoryId: asStrOrNull(j['categoryId']),
    category: Ref.maybe(j['category']),
    lastSeen: asDate(j['lastSeen']),
  );
}
