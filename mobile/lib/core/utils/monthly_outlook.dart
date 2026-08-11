import '../../models/models.dart';
import '../../models/outlook_history.dart';
import 'format.dart';

/// One line in the monthly outlook (recurring rule, budget plan, or buffer).
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
    this.coveredByRule = false,
    this.rawAmount,
  });

  final String id;
  final String title;

  /// What this line contributes to the target, after deduplication.
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

  /// True when a recurring rule already pays for this plan's category, so the
  /// plan's amount was reduced (often to zero) to avoid counting the same birr
  /// twice.
  final bool coveredByRule;

  /// The plan's own monthly figure before deduplication. Only differs from
  /// [monthlyAmount] when [coveredByRule].
  final double? rawAmount;

  double get displayAmount => rawAmount ?? monthlyAmount;
}

enum OutlookSource { recurring, budgetPlan, buffer }

/// Which question the income target is answering.
///
/// The old outlook produced a single number that silently added recurring
/// bills, every budget plan, a surprise reserve sized from the *current*
/// cycle's unplanned spend, and a guess inferred from the last eight
/// transactions. Layering makes each part visible and separately arguable.
enum OutlookTarget {
  /// Recurring expense rules only — what lands whether or not you act.
  floor,

  /// Floor plus the budget plans a rule does not already pay for.
  steady,

  /// Steady plus a surprise buffer.
  comfortable,
}

extension OutlookTargetX on OutlookTarget {
  String get label => switch (this) {
        OutlookTarget.floor => 'Floor',
        OutlookTarget.steady => 'Steady',
        OutlookTarget.comfortable => 'Comfortable',
      };

  String get question => switch (this) {
        OutlookTarget.floor => 'If I do nothing, what must I cover?',
        OutlookTarget.steady => 'What to run the month as planned',
        OutlookTarget.comfortable => 'Planned, plus room for surprises',
      };
}

/// Where the surprise buffer came from — shown so the figure is never magic.
enum BufferBasis {
  /// The user set a planned cushion on the Unplanned envelope.
  planned,

  /// Median unplanned spend across completed months.
  median,

  /// No history and no cushion set.
  none,
}

/// Computed cashflow outlook for the active currency.
class MonthlyOutlook {
  const MonthlyOutlook({
    required this.currency,
    required this.expectedIncome,
    required this.floorSpend,
    required this.planSpend,
    required this.buffer,
    required this.bufferBasis,
    required this.bufferSampleMonths,
    required this.actualIncomeMtd,
    required this.actualExpenseMtd,
    required this.incomeLines,
    required this.expenseLines,
    required this.planLines,
    required this.repeatCandidates,
    required this.history,
    required this.breakEvenDay,
    required this.duplicateCategories,
    required this.uncoveredExpenseCategories,
    required this.asOf,
  });

  final String currency;

  /// What recurring income rules say you will bring in.
  final double expectedIncome;

  /// Recurring expense rules — the floor.
  final double floorSpend;

  /// Budget plans, already net of anything a recurring rule pays for.
  final double planSpend;

  /// Surprise cushion. Never derived from the current month.
  final double buffer;

  final BufferBasis bufferBasis;

  /// Completed months the median was taken from.
  final int bufferSampleMonths;

  final double actualIncomeMtd;
  final double actualExpenseMtd;

  final List<OutlookLine> incomeLines;
  final List<OutlookLine> expenseLines;
  final List<OutlookLine> planLines;

  /// When the outlook was computed — a couple of insights depend on how far
  /// into the month we are.
  final DateTime asOf;

  /// Plain-language read of the numbers, derived rather than stored.
  List<String> get insights => _buildInsights(this, asOf);

  /// Repeating payees with no rule yet. Deliberately **not** part of any
  /// target: three months of history cannot be turned into a commitment
  /// without the user saying so. They are suggestions to create a rule.
  final List<RepeatCandidate> repeatCandidates;

  final OutlookHistory? history;

  /// Day of the month by which recurring income has covered recurring bills,
  /// or null when it never does.
  final int? breakEvenDay;

  /// Categories where a plan and a recurring rule overlapped, so the plan was
  /// reduced. Surfaced so the deduction is explainable.
  final int duplicateCategories;

  /// Expense categories with real spending but neither a rule nor a plan —
  /// the reason a target might read low.
  final int uncoveredExpenseCategories;

  double get forecastedIncome => expectedIncome;

  /// The income target for [target].
  double requiredFor(OutlookTarget target) => switch (target) {
        OutlookTarget.floor => floorSpend,
        OutlookTarget.steady => floorSpend + planSpend,
        OutlookTarget.comfortable => floorSpend + planSpend + buffer,
      };

  /// Default headline: the full picture, but every layer is reachable.
  double get requiredIncome => requiredFor(OutlookTarget.comfortable);

  double gapFor(OutlookTarget target) => requiredFor(target) - forecastedIncome;

  double? coverageFor(OutlookTarget target) {
    final need = requiredFor(target);
    return need <= 0 ? null : forecastedIncome / need * 100;
  }

  /// The lightest target your recurring income already covers, or null when it
  /// does not cover even the floor.
  OutlookTarget? get coveredTarget {
    for (final t in [
      OutlookTarget.comfortable,
      OutlookTarget.steady,
      OutlookTarget.floor,
    ]) {
      if (forecastedIncome >= requiredFor(t) && requiredFor(t) > 0) return t;
    }
    return null;
  }

  double get incomeGap => expectedIncome - actualIncomeMtd;

  double get spendHeadroom =>
      floorSpend <= 0 ? 0 : (floorSpend - actualExpenseMtd).clamp(0, double.infinity);

  /// What [target] works out to per pay period.
  double perPeriod(OutlookTarget target, PayCadence cadence) =>
      requiredFor(target) / cadence.periodsPerMonth;

  bool get hasAnySignal =>
      incomeLines.isNotEmpty ||
      expenseLines.isNotEmpty ||
      planLines.isNotEmpty ||
      repeatCandidates.isNotEmpty ||
      buffer > 0 ||
      actualIncomeMtd > 0 ||
      actualExpenseMtd > 0;

  /// How much to trust the number, in one sentence.
  String get confidence {
    final parts = <String>[
      '${expenseLines.length} recurring ${expenseLines.length == 1 ? 'bill' : 'bills'}',
      '${planLines.length} ${planLines.length == 1 ? 'plan' : 'plans'}',
    ];
    final caveats = <String>[
      if (uncoveredExpenseCategories > 0)
        '$uncoveredExpenseCategories spending ${uncoveredExpenseCategories == 1 ? 'category has' : 'categories have'} neither',
      if (duplicateCategories > 0)
        '$duplicateCategories overlapping ${duplicateCategories == 1 ? 'category was' : 'categories were'} counted once',
    ];
    return 'Based on ${parts.join(' and ')}'
        '${caveats.isEmpty ? '.' : ' — ${caveats.join('; ')}.'}';
  }
}

/// How often money arrives, for the per-payday view.
enum PayCadence { monthly, fortnightly, weekly }

extension PayCadenceX on PayCadence {
  double get periodsPerMonth => switch (this) {
        PayCadence.monthly => 1,
        PayCadence.fortnightly => 30.436875 / 14,
        PayCadence.weekly => 30.436875 / 7,
      };

  String get label => switch (this) {
        PayCadence.monthly => 'per month',
        PayCadence.fortnightly => 'per fortnight',
        PayCadence.weekly => 'per week',
      };

  String get short => switch (this) {
        PayCadence.monthly => 'Monthly',
        PayCadence.fortnightly => 'Fortnightly',
        PayCadence.weekly => 'Weekly',
      };
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

/// Monthly figure for a real budget plan — always **plannedAmount**, never spent.
double monthlyBudgetPlan(BudgetRow b) {
  if (b.isUnplanned || b.isClosed) return 0;
  final planned = toNum(b.plannedAmount);
  if (planned <= 0) return 0;
  return _monthlyFromPlanned(b, planned);
}

/// The cushion the user deliberately set on the Unplanned envelope, if any.
double plannedUnplannedCushion(BudgetRow b) {
  if (!b.isUnplanned || b.isClosed) return 0;
  final planned = toNum(b.plannedAmount);
  if (planned <= 0) return 0;
  return _monthlyFromPlanned(b, planned);
}

double _monthlyFromPlanned(BudgetRow b, double planned) {
  final interval = b.recurrenceInterval <= 0 ? 1 : b.recurrenceInterval;
  if (b.kind == BudgetKind.oneTime || b.kind == BudgetKind.unplanned) {
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
  required MonthSummary? month,
  OutlookHistory? history,
  List<CategoryBreakdownItem> topCategories = const [],
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final activeRules = rules.where((r) {
    if (!r.active || r.currency != currency) return false;
    if (r.endDate != null && r.endDate!.isBefore(today)) return false;
    return true;
  }).toList();

  OutlookLine lineFromRule(RecurringRule r) => OutlookLine(
        id: r.id,
        title: r.name,
        monthlyAmount: monthlyEquivalentAmount(toNum(r.amount), r.frequency, r.interval),
        kind: r.kind,
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
      );

  final incomeLines = activeRules.where((r) => r.kind == TxKind.income).map(lineFromRule).toList()
    ..sort((a, b) => b.monthlyAmount.compareTo(a.monthlyAmount));

  final expenseRules = activeRules.where((r) => r.kind == TxKind.expense).toList();
  final expenseLines = expenseRules.map(lineFromRule).toList()
    ..sort((a, b) => b.monthlyAmount.compareTo(a.monthlyAmount));

  // How much recurring spend each category already carries. A plan for the
  // same category is how you *fund* that bill, not a second bill — without
  // this, rent set aside in an envelope and rent paid by a rule both landed in
  // the target.
  final ruleSpendByCategory = <String, double>{};
  for (final r in expenseRules) {
    final id = r.categoryId;
    if (id == null) continue;
    ruleSpendByCategory[id] = (ruleSpendByCategory[id] ?? 0) +
        monthlyEquivalentAmount(toNum(r.amount), r.frequency, r.interval);
  }

  var duplicateCategories = 0;
  final remainingRuleCover = {...ruleSpendByCategory};

  final planLines = <OutlookLine>[];
  for (final b in budgets) {
    if (b.isUnplanned || b.isClosed || b.currency != currency) continue;
    final raw = monthlyBudgetPlan(b);
    if (raw <= 0) continue;

    var contribution = raw;
    var covered = false;
    final categoryId = b.categoryId;
    if (categoryId != null) {
      final cover = remainingRuleCover[categoryId] ?? 0;
      if (cover > 0) {
        final absorbed = cover >= raw ? raw : cover;
        contribution = raw - absorbed;
        remainingRuleCover[categoryId] = cover - absorbed;
        covered = true;
        duplicateCategories += 1;
      }
    }

    planLines.add(
      OutlookLine(
        id: b.id,
        title: b.name,
        monthlyAmount: contribution,
        rawAmount: raw,
        coveredByRule: covered,
        kind: TxKind.expense,
        source: OutlookSource.budgetPlan,
        subtitle: [
          'Plan ${b.kind.label}',
          if (b.recurrenceLabel != null) b.recurrenceLabel!,
          if (covered) 'a recurring bill already covers this category',
        ].join(' · '),
        cadence: b.recurrenceLabel ?? b.kind.label,
        note: b.note,
        categoryName: b.category?.name,
      ),
    );
  }
  planLines.sort((a, b) => b.displayAmount.compareTo(a.displayAmount));

  // --- buffer ----------------------------------------------------------------

  // Priority: a cushion the user set, then the median of completed months.
  // Never this cycle's unplanned spend — that made the target climb through
  // the month and rewarded overspending with a higher "needed income".
  var buffer = 0.0;
  var bufferBasis = BufferBasis.none;
  for (final b in budgets) {
    if (!b.isUnplanned || b.isClosed || b.currency != currency) continue;
    final cushion = plannedUnplannedCushion(b);
    if (cushion > 0) {
      buffer += cushion;
      bufferBasis = BufferBasis.planned;
    }
  }
  if (bufferBasis == BufferBasis.none && history != null && history.unplannedMedian > 0) {
    buffer = history.unplannedMedian;
    bufferBasis = BufferBasis.median;
  }

  final forecastedIncome = incomeLines.fold<double>(0, (s, l) => s + l.monthlyAmount);
  final floorSpend = expenseLines.fold<double>(0, (s, l) => s + l.monthlyAmount);
  final planSpend = planLines.fold<double>(0, (s, l) => s + l.monthlyAmount);

  // Categories with real spending that neither a rule nor a plan accounts for.
  final accountedCategories = <String>{
    ...ruleSpendByCategory.keys,
    ...budgets
        .where((b) => !b.isUnplanned && !b.isClosed && b.categoryId != null)
        .map((b) => b.categoryId!),
  };
  final uncovered = topCategories
      .where((c) => c.category?.id != null && toNum(c.amount) > 0)
      .where((c) => !accountedCategories.contains(c.category!.id))
      .length;

  final actualIn = toNum(month?.income);
  final actualOut = toNum(month?.expense);

  return MonthlyOutlook(
    currency: currency,
    expectedIncome: forecastedIncome,
    floorSpend: floorSpend,
    planSpend: planSpend,
    buffer: buffer,
    bufferBasis: bufferBasis,
    bufferSampleMonths: history?.unplannedSampleMonths ?? 0,
    actualIncomeMtd: actualIn,
    actualExpenseMtd: actualOut,
    incomeLines: incomeLines,
    expenseLines: expenseLines,
    planLines: planLines,
    repeatCandidates: history?.repeatCandidates ?? const [],
    history: history,
    breakEvenDay: _breakEvenDay(activeRules, today),
    duplicateCategories: duplicateCategories,
    uncoveredExpenseCategories: uncovered,
    asOf: today,
  );
}

/// The day of the month by which recurring income has covered recurring bills.
///
/// Rules are placed on the day they next run, which is exact for monthly rules
/// and an approximation for weekly ones — good enough to answer "am I short at
/// the start of the month and fine by the 25th, or the other way round?".
int? _breakEvenDay(List<RecurringRule> rules, DateTime today) {
  final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
  final income = List<double>.filled(daysInMonth + 1, 0);
  final expense = List<double>.filled(daysInMonth + 1, 0);

  for (final r in rules) {
    final monthly = monthlyEquivalentAmount(toNum(r.amount), r.frequency, r.interval);
    if (monthly <= 0) continue;

    if (r.frequency == Frequency.daily || r.frequency == Frequency.weekly) {
      // Spread sub-monthly rules evenly rather than dropping them all on one
      // day, which would invent a cliff that does not exist.
      final perDay = monthly / daysInMonth;
      for (var d = 1; d <= daysInMonth; d++) {
        if (r.kind == TxKind.income) {
          income[d] += perDay;
        } else {
          expense[d] += perDay;
        }
      }
      continue;
    }

    final day = (r.dayOfMonth ?? r.nextRun.day).clamp(1, daysInMonth);
    if (r.kind == TxKind.income) {
      income[day] += monthly;
    } else {
      expense[day] += monthly;
    }
  }

  var cumulativeIn = 0.0;
  var cumulativeOut = 0.0;
  var sawExpense = false;
  for (var d = 1; d <= daysInMonth; d++) {
    cumulativeIn += income[d];
    cumulativeOut += expense[d];
    if (cumulativeOut > 0) sawExpense = true;
    if (sawExpense && cumulativeIn >= cumulativeOut) return d;
  }
  return null;
}

List<String> _buildInsights(MonthlyOutlook o, DateTime today) {
  final insights = <String>[];
  final steady = o.requiredFor(OutlookTarget.steady);
  final comfortable = o.requiredFor(OutlookTarget.comfortable);

  if (o.floorSpend > 0) {
    if (o.forecastedIncome <= 0) {
      insights.add(
        'Your bills alone come to ${o.floorSpend.round()} a month. Add a salary rule to see whether that is covered.',
      );
    } else if (o.forecastedIncome < o.floorSpend) {
      insights.add(
        'Recurring income does not cover recurring bills — short ${(o.floorSpend - o.forecastedIncome).round()} before you spend on anything else.',
      );
    } else if (o.forecastedIncome < steady) {
      insights.add(
        'Bills are covered, but you are ${(steady - o.forecastedIncome).round()} short of funding your plans as well.',
      );
    } else if (o.forecastedIncome < comfortable) {
      insights.add(
        'Bills and plans are covered. Another ${(comfortable - o.forecastedIncome).round()} would cover a typical month of surprises too.',
      );
    } else {
      insights.add(
        'Recurring income covers everything with about ${(o.forecastedIncome - comfortable).round()} spare.',
      );
    }
  }

  if (o.breakEvenDay != null) {
    insights.add(
      'Your bills are paid off by day ${o.breakEvenDay} of the month — before that you are running on last month\'s balance.',
    );
  } else if (o.floorSpend > 0 && o.forecastedIncome > 0) {
    insights.add(
      'Recurring income never catches up with the bills inside the month. Moving a due date later would help.',
    );
  }

  switch (o.bufferBasis) {
    case BufferBasis.planned:
      insights.add(
        'The ${o.buffer.round()} surprise buffer is the cushion you set on Unplanned.',
      );
    case BufferBasis.median:
      insights.add(
        'The ${o.buffer.round()} buffer is your median unplanned spend over ${o.bufferSampleMonths} completed ${o.bufferSampleMonths == 1 ? 'month' : 'months'} — it does not move during the month.',
      );
    case BufferBasis.none:
      if (o.floorSpend > 0) {
        insights.add(
          'No surprise buffer yet. Set a cushion on the Unplanned plan, or give it a month or two of history.',
        );
      }
  }

  if (o.duplicateCategories > 0) {
    insights.add(
      '${o.duplicateCategories} ${o.duplicateCategories == 1 ? 'plan covers a category' : 'plans cover categories'} a recurring bill already pays — counted once, not twice.',
    );
  }

  if (o.uncoveredExpenseCategories > 0) {
    insights.add(
      '${o.uncoveredExpenseCategories} spending ${o.uncoveredExpenseCategories == 1 ? 'category has' : 'categories have'} no bill or plan, so the target is probably lower than real life.',
    );
  }

  if (o.repeatCandidates.isNotEmpty) {
    insights.add(
      'Spotted ${o.repeatCandidates.length} repeating ${o.repeatCandidates.length == 1 ? 'payee' : 'payees'} with no rule. Turning them into rules makes this target sharper.',
    );
  }

  final covered = o.history?.coveredMonths;
  final total = o.history?.months.length ?? 0;
  if (covered != null && total > 0) {
    insights.add(
      'You covered your spending in $covered of the last $total ${total == 1 ? 'month' : 'months'}.',
    );
  }

  if (o.forecastedIncome > 0 && o.actualIncomeMtd < o.forecastedIncome * 0.5 && today.day >= 10) {
    insights.add('Income so far is well below forecast. Check a pending salary or receipt.');
  }

  if (insights.isEmpty) {
    insights.add(
      'Add your recurring bills and budget plans — Santim will work out the income the month needs.',
    );
  }
  return insights;
}
