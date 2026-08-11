import '../../models/models.dart';
import 'format.dart';

/// One line in the monthly outlook (recurring rule, budget plan, or inferred pattern).
class OutlookLine {
  const OutlookLine({
    required this.id,
    required this.title,
    required this.monthlyAmount,
    required this.kind,
    required this.source,
    this.subtitle,
    this.cadence,
    this.nextDate,
    this.payee,
    this.note,
    this.categoryName,
    this.autoPost = false,
  });

  final String id;
  final String title;
  final double monthlyAmount;
  final TxKind kind;
  final OutlookSource source;
  final String? subtitle;
  final String? cadence;
  final DateTime? nextDate;
  final String? payee;
  final String? note;
  final String? categoryName;
  final bool autoPost;
}

enum OutlookSource { recurring, budgetPlan, transactionPattern }

/// Computed cashflow outlook for the active currency.
class MonthlyOutlook {
  const MonthlyOutlook({
    required this.currency,
    required this.expectedIncome,
    required this.committedSpend,
    required this.plannedEnvelopes,
    required this.actualIncomeMtd,
    required this.actualExpenseMtd,
    required this.incomeLines,
    required this.expenseLines,
    required this.planLines,
    required this.patternLines,
    required this.insights,
  });

  final String currency;
  final double expectedIncome;
  final double committedSpend;
  final double plannedEnvelopes;
  final double actualIncomeMtd;
  final double actualExpenseMtd;
  final List<OutlookLine> incomeLines;
  final List<OutlookLine> expenseLines;
  final List<OutlookLine> planLines;
  final List<OutlookLine> patternLines;
  final List<String> insights;

  double get outlookNet => expectedIncome - committedSpend;
  double get freeAfterPlans => expectedIncome - committedSpend - plannedEnvelopes;
  double get incomeGap => expectedIncome - actualIncomeMtd;
  double get spendHeadroom =>
      committedSpend <= 0 ? 0 : (committedSpend - actualExpenseMtd).clamp(0, double.infinity);

  /// Share of expected income already spoken for by recurring bills (0–100+).
  double? get spokenForPct =>
      expectedIncome <= 0 ? null : (committedSpend / expectedIncome * 100);

  bool get hasAnySignal =>
      incomeLines.isNotEmpty ||
      expenseLines.isNotEmpty ||
      planLines.isNotEmpty ||
      patternLines.isNotEmpty ||
      actualIncomeMtd > 0 ||
      actualExpenseMtd > 0;
}

/// Aligns Recurring / Analytics / Outlook on one monthly conversion.
double monthlyEquivalentAmount(double amount, Frequency frequency, int interval) {
  final perPeriod = amount / (interval <= 0 ? 1 : interval);
  const daysPerMonth = 30.436875;
  return switch (frequency) {
    Frequency.daily => perPeriod * daysPerMonth,
    Frequency.weekly => perPeriod * (daysPerMonth / 7),
    Frequency.monthly => perPeriod,
    Frequency.yearly => perPeriod / 12,
  };
}

double monthlyBudgetPlan(BudgetRow b) {
  if (b.isUnplanned || b.isClosed) return 0;
  final planned = toNum(b.plannedAmount);
  if (planned <= 0) return 0;
  final interval = b.recurrenceInterval <= 0 ? 1 : b.recurrenceInterval;
  if (b.kind == BudgetKind.oneTime) {
    // Spread one-time plans across the remaining / current month once.
    return planned;
  }
  final unit = b.recurrenceUnit ?? RecurrenceUnit.month;
  final per = planned / interval;
  return switch (unit) {
    RecurrenceUnit.hour => per * 24 * 30.436875,
    RecurrenceUnit.day => per * 30.436875,
    RecurrenceUnit.week => per * (30.436875 / 7),
    RecurrenceUnit.month => per,
    RecurrenceUnit.quarter => per / 3,
    RecurrenceUnit.year => per / 12,
  };
}

MonthlyOutlook buildMonthlyOutlook({
  required String currency,
  required List<RecurringRule> rules,
  required List<BudgetRow> budgets,
  required List<Transaction> recentTransactions,
  required MonthSummary? month,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final activeRules = rules.where((r) {
    if (!r.active || r.currency != currency) return false;
    if (r.endDate != null && r.endDate!.isBefore(today)) return false;
    return true;
  }).toList();

  final incomeLines = activeRules
      .where((r) => r.kind == TxKind.income)
      .map(
        (r) => OutlookLine(
          id: r.id,
          title: r.name,
          monthlyAmount: monthlyEquivalentAmount(toNum(r.amount), r.frequency, r.interval),
          kind: TxKind.income,
          source: OutlookSource.recurring,
          subtitle: [
            if (r.payee != null && r.payee!.trim().isNotEmpty) r.payee,
            if (r.category != null) r.category!.name,
            if (r.account != null) r.account!.name,
          ].whereType<String>().join(' · '),
          cadence: r.cadence,
          nextDate: r.nextRun,
          payee: r.payee,
          note: r.note,
          categoryName: r.category?.name,
          autoPost: r.autoPost,
        ),
      )
      .toList()
    ..sort((a, b) => b.monthlyAmount.compareTo(a.monthlyAmount));

  final expenseLines = activeRules
      .where((r) => r.kind == TxKind.expense)
      .map(
        (r) => OutlookLine(
          id: r.id,
          title: r.name,
          monthlyAmount: monthlyEquivalentAmount(toNum(r.amount), r.frequency, r.interval),
          kind: TxKind.expense,
          source: OutlookSource.recurring,
          subtitle: [
            if (r.payee != null && r.payee!.trim().isNotEmpty) r.payee,
            if (r.category != null) r.category!.name,
            if (r.account != null) r.account!.name,
          ].whereType<String>().join(' · '),
          cadence: r.cadence,
          nextDate: r.nextRun,
          payee: r.payee,
          note: r.note,
          categoryName: r.category?.name,
          autoPost: r.autoPost,
        ),
      )
      .toList()
    ..sort((a, b) => b.monthlyAmount.compareTo(a.monthlyAmount));

  final planLines = budgets
      .where((b) => !b.isUnplanned && !b.isClosed && b.currency == currency)
      .map(
        (b) => OutlookLine(
          id: b.id,
          title: b.name,
          monthlyAmount: monthlyBudgetPlan(b),
          kind: TxKind.expense,
          source: OutlookSource.budgetPlan,
          subtitle: [
            b.kind.label,
            if (b.recurrenceLabel != null) b.recurrenceLabel!,
            if (b.note != null && b.note!.trim().isNotEmpty) b.note!,
          ].join(' · '),
          cadence: b.recurrenceLabel ?? b.kind.label,
          note: b.note,
          categoryName: b.category?.name,
        ),
      )
      .where((l) => l.monthlyAmount > 0)
      .toList()
    ..sort((a, b) => b.monthlyAmount.compareTo(a.monthlyAmount));

  // Infer repeating income/expense from richly detailed transactions
  // (payee + note) that are not already covered by a recurring rule.
  final patternLines = _inferPatterns(
    recentTransactions.where((tx) => tx.currency == currency).toList(),
    coveredNames: {
      ...incomeLines.map((l) => l.title.toLowerCase()),
      ...expenseLines.map((l) => (l.payee ?? l.title).toLowerCase()),
    },
  );

  final expectedIncome = incomeLines.fold<double>(0, (s, l) => s + l.monthlyAmount);
  final committedSpend = expenseLines.fold<double>(0, (s, l) => s + l.monthlyAmount);
  final plannedEnvelopes = planLines.fold<double>(0, (s, l) => s + l.monthlyAmount);
  final actualIn = toNum(month?.income);
  final actualOut = toNum(month?.expense);

  final insights = <String>[];
  if (expectedIncome > 0 && committedSpend > 0) {
    final pct = committedSpend / expectedIncome * 100;
    if (pct >= 90) {
      insights.add(
        'Recurring bills already claim ${pct.round()}% of expected income — little room left.',
      );
    } else if (pct >= 60) {
      insights.add(
        '${pct.round()}% of expected income is spoken for by recurring bills. Aim to keep this under 60%.',
      );
    } else {
      insights.add(
        'Only ${pct.round()}% of expected income is locked in bills — healthy breathing room.',
      );
    }
  }
  if (expectedIncome > 0 && actualIn < expectedIncome * 0.5 && today.day >= 10) {
    insights.add(
      'Actual income so far is well below what recurring income predicts. Check pending salary or receipts.',
    );
  }
  if (expectedIncome == 0 && actualIn > 0) {
    insights.add(
      'You have income this month but no recurring income rule. Add salary/freelance as recurring to forecast better.',
    );
  }
  if (committedSpend == 0 && actualOut > 0) {
    insights.add(
      'No recurring bills yet. Capture rent, utilities, and subscriptions once so the outlook stays honest.',
    );
  }
  if (plannedEnvelopes > 0 && expectedIncome > 0) {
    final free = expectedIncome - committedSpend - plannedEnvelopes;
    if (free < 0) {
      insights.add(
        'Plans + bills exceed expected income by ${(-free).round()} — trim envelopes or raise expected inflows.',
      );
    } else {
      insights.add(
        'After bills and budget plans, about ${free.round()} stays flexible this month.',
      );
    }
  }
  if (patternLines.isNotEmpty) {
    insights.add(
      'Spotted ${patternLines.length} repeating ${patternLines.length == 1 ? 'pattern' : 'patterns'} from detailed transactions you may want to promote to recurring.',
    );
  }
  if (insights.isEmpty && expectedIncome > 0) {
    insights.add('Your outlook is built from active recurring rules — keep them current for accuracy.');
  }

  return MonthlyOutlook(
    currency: currency,
    expectedIncome: expectedIncome,
    committedSpend: committedSpend,
    plannedEnvelopes: plannedEnvelopes,
    actualIncomeMtd: actualIn,
    actualExpenseMtd: actualOut,
    incomeLines: incomeLines,
    expenseLines: expenseLines,
    planLines: planLines,
    patternLines: patternLines,
    insights: insights,
  );
}

List<OutlookLine> _inferPatterns(
  List<Transaction> txs, {
  required Set<String> coveredNames,
}) {
  // Group by kind + payee (or note), count occurrences, require details.
  final buckets = <String, _PatternBucket>{};
  for (final tx in txs) {
    if (tx.kind != TxKind.income && tx.kind != TxKind.expense) continue;
    if (tx.recurringRuleId != null) continue;
    final payee = tx.payee?.trim();
    final note = tx.note?.trim();
    if ((payee == null || payee.isEmpty) && (note == null || note.isEmpty)) continue;
    final keyName = (payee != null && payee.isNotEmpty) ? payee : note!;
    if (coveredNames.contains(keyName.toLowerCase())) continue;
    final key = '${tx.kind.name}|${keyName.toLowerCase()}';
    final bucket = buckets.putIfAbsent(
      key,
      () => _PatternBucket(kind: tx.kind, title: keyName, note: note, payee: payee),
    );
    bucket.total += toNum(tx.amount);
    bucket.count += 1;
    bucket.categoryName ??= tx.category?.name;
  }

  return buckets.values
      .where((b) => b.count >= 2)
      .map(
        (b) => OutlookLine(
          id: 'pattern-${b.kind.name}-${b.title.hashCode}',
          title: b.title,
          // Rough monthly: average occurrence amount (not true cadence).
          monthlyAmount: b.total / b.count,
          kind: b.kind,
          source: OutlookSource.transactionPattern,
          subtitle: [
            'Seen ${b.count}× recently',
            if (b.categoryName != null) b.categoryName!,
            if (b.note != null && b.note != b.title) b.note!,
          ].join(' · '),
          payee: b.payee,
          note: b.note,
          categoryName: b.categoryName,
        ),
      )
      .toList()
    ..sort((a, b) => b.monthlyAmount.compareTo(a.monthlyAmount));
}

class _PatternBucket {
  _PatternBucket({
    required this.kind,
    required this.title,
    this.note,
    this.payee,
  });

  final TxKind kind;
  final String title;
  final String? note;
  final String? payee;
  String? categoryName;
  double total = 0;
  int count = 0;
}
