import 'common.dart';
import 'models.dart' show Ref;

/// `GET /analytics/page`   one payload, one screen.
class AnalyticsPlanRow {
  AnalyticsPlanRow({
    required this.id,
    required this.name,
    required this.kind,
    required this.openingPlanned,
    required this.adjusted,
    required this.planned,
    required this.funded,
    required this.spent,
    required this.remaining,
    required this.pctOfOpening,
    this.icon,
    this.color,
    this.cycleLabel,
    this.periodNoun,
  });

  final String id;
  final String name;
  final String? icon;
  final String? color;
  final BudgetKind kind;
  final String? cycleLabel;
  final String? periodNoun;

  /// What the cycle opened with, before any mid-cycle raise or cut.
  final String openingPlanned;

  /// Net of the raises (+) and cuts (-) made during the cycle.
  final String adjusted;
  final String planned;
  final String funded;
  final String spent;
  final String remaining;

  /// Spend against the opening figure. Can exceed 100.
  final double pctOfOpening;

  factory AnalyticsPlanRow.fromJson(Map<String, dynamic> j) => AnalyticsPlanRow(
    id: asStr(j['id'], ''),
    name: asStr(j['name'], ''),
    icon: asStrOrNull(j['icon']),
    color: asStrOrNull(j['color']),
    kind: BudgetKind.parse(j['kind']),
    cycleLabel: asStrOrNull(j['cycleLabel']),
    periodNoun: asStrOrNull(j['periodNoun']),
    openingPlanned: asStr(j['openingPlanned']),
    adjusted: asStr(j['adjusted']),
    planned: asStr(j['planned']),
    funded: asStr(j['funded']),
    spent: asStr(j['spent']),
    remaining: asStr(j['remaining']),
    pctOfOpening: asNum(j['pctOfOpening']),
  );
}

class AnalyticsCommitment {
  AnalyticsCommitment({
    required this.id,
    required this.name,
    required this.kind,
    required this.amount,
    required this.frequency,
    required this.interval,
    required this.nextRun,
    required this.autoPost,
    required this.monthlyEquivalent,
    this.category,
  });

  final String id;
  final String name;
  final TxKind kind;
  final String amount;
  final Frequency frequency;
  final int interval;
  final DateTime nextRun;
  final bool autoPost;
  final Ref? category;
  final String monthlyEquivalent;

  factory AnalyticsCommitment.fromJson(Map<String, dynamic> j) =>
      AnalyticsCommitment(
        id: asStr(j['id'], ''),
        name: asStr(j['name'], ''),
        kind: TxKind.parse(j['kind']),
        amount: asStr(j['amount']),
        frequency: Frequency.parse(j['frequency']),
        interval: asInt(j['interval'], 1),
        nextRun: asDate(j['nextRun']) ?? DateTime.now(),
        autoPost: asBool(j['autoPost']),
        category: Ref.maybe(j['category']),
        monthlyEquivalent: asStr(j['monthlyEquivalent']),
      );
}

class AnalyticsCounterparty {
  AnalyticsCounterparty({
    required this.name,
    required this.kind,
    required this.outstanding,
    required this.overdue,
    this.dueDate,
  });

  final String name;
  final LedgerKind kind;
  final String outstanding;
  final DateTime? dueDate;
  final bool overdue;

  factory AnalyticsCounterparty.fromJson(Map<String, dynamic> j) =>
      AnalyticsCounterparty(
        name: asStr(j['name'], ''),
        kind: LedgerKind.parse(j['kind']),
        outstanding: asStr(j['outstanding']),
        dueDate: asDate(j['dueDate']),
        overdue: asBool(j['overdue']),
      );
}

class AnalyticsPageData {
  AnalyticsPageData({
    required this.month,
    required this.periodStart,
    required this.periodEnd,
    required this.inProgress,
    required this.daysElapsed,
    required this.daysInMonth,
    required this.currency,
    required this.missingRates,
    required this.scopeComplete,
    required this.hasPrevious,
    required this.income,
    required this.expense,
    required this.net,
    required this.prevIncome,
    required this.prevExpense,
    required this.prevNet,
    required this.unplannedAmount,
    required this.unplannedTotalExpense,
    required this.unplannedPct,
    required this.cashReal,
    required this.cashLocked,
    required this.cashAvailable,
    required this.lockedPct,
    required this.accountCount,
    required this.plans,
    required this.planOpening,
    required this.planAdjusted,
    required this.planSpent,
    required this.planPctOfOpening,
    required this.overspentCount,
    required this.adjustedCount,
    required this.monthlyOut,
    required this.monthlyIn,
    required this.commitments,
    required this.wishWanting,
    required this.wishPlanned,
    required this.wishBought,
    required this.wishDropped,
    required this.wishPlannedValue,
    required this.lent,
    required this.lentCount,
    required this.borrowed,
    required this.borrowedCount,
    required this.ledgerExpectedIn,
    required this.ledgerExpectedOut,
    required this.counterparties,
    required this.overdueCount,
    this.firstTransactionAt,
    this.deltaNetPct,
    this.deltaExpensePct,
    this.savingsRate,
    this.shareOfIncome,
    this.avgDaysToPlan,
    this.avgDaysToBuy,
  });

  final String month;
  final DateTime periodStart;
  final DateTime periodEnd;
  final bool inProgress;
  final int daysElapsed;
  final int daysInMonth;

  final String currency;

  /// Currencies held with no rate into the scoped one, so left out of totals.
  final List<String> missingRates;
  final bool scopeComplete;

  final bool hasPrevious;
  final DateTime? firstTransactionAt;

  final String income;
  final String expense;
  final String net;
  final String prevIncome;
  final String prevExpense;
  final String prevNet;
  final double? deltaNetPct;
  final double? deltaExpensePct;
  final double? savingsRate;

  final String unplannedAmount;
  final String unplannedTotalExpense;
  final double unplannedPct;

  final String cashReal;
  final String cashLocked;
  final String cashAvailable;
  final double lockedPct;
  final int accountCount;

  final List<AnalyticsPlanRow> plans;
  final String planOpening;
  final String planAdjusted;
  final String planSpent;
  final double planPctOfOpening;
  final int overspentCount;
  final int adjustedCount;

  final String monthlyOut;
  final String monthlyIn;
  final List<AnalyticsCommitment> commitments;
  final double? shareOfIncome;

  final int wishWanting;
  final int wishPlanned;
  final int wishBought;
  final int wishDropped;
  final String wishPlannedValue;
  final double? avgDaysToPlan;
  final double? avgDaysToBuy;

  final String lent;
  final int lentCount;
  final String borrowed;
  final int borrowedCount;
  final String ledgerExpectedIn;
  final String ledgerExpectedOut;
  final List<AnalyticsCounterparty> counterparties;
  final int overdueCount;

  factory AnalyticsPageData.fromJson(Map<String, dynamic> j) {
    final period = asMap(j['period']);
    final scope = asMap(j['scope']);
    final history = asMap(j['history']);
    final cf = asMap(j['cashFlow']);
    final prev = asMap(cf['previous']);
    final unplanned = asMap(j['unplanned']);
    final cash = asMap(j['cash']);
    final plans = asMap(j['plans']);
    final planTotals = asMap(plans['totals']);
    final commitments = asMap(j['commitments']);
    final wishlist = asMap(j['wishlist']);
    final ledger = asMap(j['ledger']);

    return AnalyticsPageData(
      month: asStr(period['month'], ''),
      periodStart: asDate(period['start']) ?? DateTime.now(),
      periodEnd: asDate(period['end']) ?? DateTime.now(),
      inProgress: asBool(period['inProgress']),
      daysElapsed: asInt(period['daysElapsed']),
      daysInMonth: asInt(period['daysInMonth'], 30),
      currency: asStr(scope['currency'], 'ETB'),
      missingRates: asStrList(scope['missingRates']),
      scopeComplete: asBool(scope['complete'], true),
      hasPrevious: asBool(history['hasPrevious']),
      firstTransactionAt: asDate(history['firstTransactionAt']),
      income: asStr(cf['income']),
      expense: asStr(cf['expense']),
      net: asStr(cf['net']),
      prevIncome: asStr(prev['income']),
      prevExpense: asStr(prev['expense']),
      prevNet: asStr(prev['net']),
      deltaNetPct: cf['deltaNetPct'] == null ? null : asNum(cf['deltaNetPct']),
      deltaExpensePct: cf['deltaExpensePct'] == null
          ? null
          : asNum(cf['deltaExpensePct']),
      savingsRate: cf['savingsRate'] == null ? null : asNum(cf['savingsRate']),
      unplannedAmount: asStr(unplanned['amount']),
      unplannedTotalExpense: asStr(unplanned['totalExpense']),
      unplannedPct: asNum(unplanned['pct']),
      cashReal: asStr(cash['real']),
      cashLocked: asStr(cash['locked']),
      cashAvailable: asStr(cash['available']),
      lockedPct: asNum(cash['lockedPct']),
      accountCount: asInt(cash['accountCount']),
      plans: mapList(plans['items'], AnalyticsPlanRow.fromJson),
      planOpening: asStr(planTotals['opening']),
      planAdjusted: asStr(planTotals['adjusted']),
      planSpent: asStr(planTotals['spent']),
      planPctOfOpening: asNum(planTotals['pctOfOpening']),
      overspentCount: asInt(plans['overspentCount']),
      adjustedCount: asInt(plans['adjustedCount']),
      monthlyOut: asStr(commitments['monthlyOut']),
      monthlyIn: asStr(commitments['monthlyIn']),
      commitments: mapList(commitments['items'], AnalyticsCommitment.fromJson),
      shareOfIncome: commitments['shareOfIncome'] == null
          ? null
          : asNum(commitments['shareOfIncome']),
      wishWanting: asInt(wishlist['wanting']),
      wishPlanned: asInt(wishlist['planned']),
      wishBought: asInt(wishlist['bought']),
      wishDropped: asInt(wishlist['dropped']),
      wishPlannedValue: asStr(wishlist['plannedValue']),
      avgDaysToPlan: wishlist['avgDaysToPlan'] == null
          ? null
          : asNum(wishlist['avgDaysToPlan']),
      avgDaysToBuy: wishlist['avgDaysToBuy'] == null
          ? null
          : asNum(wishlist['avgDaysToBuy']),
      lent: asStr(ledger['lent']),
      lentCount: asInt(ledger['lentCount']),
      borrowed: asStr(ledger['borrowed']),
      borrowedCount: asInt(ledger['borrowedCount']),
      ledgerExpectedIn: asStr(ledger['expectedIn']),
      ledgerExpectedOut: asStr(ledger['expectedOut']),
      counterparties: mapList(
        ledger['counterparties'],
        AnalyticsCounterparty.fromJson,
      ),
      overdueCount: asInt(ledger['overdueCount']),
    );
  }
}

// --- Report endpoints the charts read ---------------------------------------

class CategoryTotals {
  CategoryTotals({
    required this.currency,
    required this.total,
    required this.items,
  });

  final String currency;
  final String total;
  final List<CategoryTotalsItem> items;

  factory CategoryTotals.fromJson(Map<String, dynamic> j) => CategoryTotals(
    currency: asStr(j['currency'], 'ETB'),
    total: asStr(j['total']),
    items: mapList(j['items'], CategoryTotalsItem.fromJson),
  );
}

class CategoryTotalsItem {
  CategoryTotalsItem({
    required this.amount,
    required this.count,
    required this.pct,
    this.category,
  });

  final Ref? category;
  final String amount;
  final int count;
  final double pct;

  factory CategoryTotalsItem.fromJson(Map<String, dynamic> j) =>
      CategoryTotalsItem(
        category: Ref.maybe(j['category']),
        amount: asStr(j['amount']),
        count: asInt(j['count']),
        pct: asNum(j['pct']),
      );
}

class IncomeVsExpensePoint {
  IncomeVsExpensePoint({
    required this.month,
    required this.income,
    required this.expense,
    this.savingsRate,
  });

  final String month;
  final String income;
  final String expense;
  final double? savingsRate;

  factory IncomeVsExpensePoint.fromJson(Map<String, dynamic> j) =>
      IncomeVsExpensePoint(
        month: asStr(j['month'], ''),
        income: asStr(j['income']),
        expense: asStr(j['expense']),
        savingsRate: j['savingsRate'] == null ? null : asNum(j['savingsRate']),
      );
}

class IncomeVsExpense {
  IncomeVsExpense({required this.currency, required this.points});
  final String currency;
  final List<IncomeVsExpensePoint> points;

  factory IncomeVsExpense.fromJson(Map<String, dynamic> j) => IncomeVsExpense(
    currency: asStr(j['currency'], 'ETB'),
    points: mapList(j['points'], IncomeVsExpensePoint.fromJson),
  );
}

class HeatmapDay {
  HeatmapDay({required this.date, required this.total});
  final DateTime date;
  final String total;

  factory HeatmapDay.fromJson(Map<String, dynamic> j) => HeatmapDay(
    date: asDate(j['date']) ?? DateTime.now(),
    total: asStr(j['total']),
  );
}

class SpendHeatmapData {
  SpendHeatmapData({
    required this.currency,
    required this.year,
    required this.days,
  });
  final String currency;
  final int year;
  final List<HeatmapDay> days;

  factory SpendHeatmapData.fromJson(Map<String, dynamic> j) => SpendHeatmapData(
    currency: asStr(j['currency'], 'ETB'),
    year: asInt(j['year'], DateTime.now().year),
    days: mapList(j['days'], HeatmapDay.fromJson),
  );
}

class PayeeTotal {
  PayeeTotal({required this.total, required this.count, this.payee});
  final String? payee;
  final String total;
  final int count;

  factory PayeeTotal.fromJson(Map<String, dynamic> j) => PayeeTotal(
    payee: asStrOrNull(j['payee']),
    total: asStr(j['total']),
    count: asInt(j['count']),
  );
}

class TopPayees {
  TopPayees({required this.currency, required this.items});
  final String currency;
  final List<PayeeTotal> items;

  factory TopPayees.fromJson(Map<String, dynamic> j) => TopPayees(
    currency: asStr(j['currency'], 'ETB'),
    items: mapList(j['items'], PayeeTotal.fromJson),
  );
}

class SeasonalMonth {
  SeasonalMonth({
    required this.month,
    required this.name,
    required this.samples,
    required this.avgIncome,
    required this.avgExpense,
    required this.avgNet,
  });

  final int month;
  final String name;

  /// How many calendar months of history fed this average.
  final int samples;
  final String avgIncome;
  final String avgExpense;
  final String avgNet;

  static SeasonalMonth? maybe(dynamic v) =>
      v is Map ? SeasonalMonth.fromJson(Map<String, dynamic>.from(v)) : null;

  factory SeasonalMonth.fromJson(Map<String, dynamic> j) => SeasonalMonth(
    month: asInt(j['month'], 1),
    name: asStr(j['name'], ''),
    samples: asInt(j['samples']),
    avgIncome: asStr(j['avgIncome']),
    avgExpense: asStr(j['avgExpense']),
    avgNet: asStr(j['avgNet']),
  );
}

class SeasonalDay {
  SeasonalDay({
    required this.day,
    required this.name,
    required this.avgSpend,
    required this.total,
    required this.txCount,
    required this.samples,
  });

  final int day;
  final String name;
  final String avgSpend;
  final String total;
  final int txCount;
  final int samples;

  factory SeasonalDay.fromJson(Map<String, dynamic> j) => SeasonalDay(
    day: asInt(j['day']),
    name: asStr(j['name'], ''),
    avgSpend: asStr(j['avgSpend']),
    total: asStr(j['total']),
    txCount: asInt(j['txCount']),
    samples: asInt(j['samples']),
  );
}

class SeasonalYear {
  SeasonalYear({
    required this.year,
    required this.income,
    required this.expense,
    required this.net,
    required this.txCount,
    this.savingsRate,
  });

  final int year;
  final String income;
  final String expense;
  final String net;
  final int txCount;
  final double? savingsRate;

  factory SeasonalYear.fromJson(Map<String, dynamic> j) => SeasonalYear(
    year: asInt(j['year']),
    income: asStr(j['income']),
    expense: asStr(j['expense']),
    net: asStr(j['net']),
    txCount: asInt(j['txCount']),
    savingsRate: j['savingsRate'] == null ? null : asNum(j['savingsRate']),
  );
}

class SeasonalWeek {
  SeasonalWeek({
    required this.week,
    required this.label,
    required this.income,
    required this.expense,
    required this.net,
  });

  final String week;
  final String label;
  final String income;
  final String expense;
  final String net;

  factory SeasonalWeek.fromJson(Map<String, dynamic> j) => SeasonalWeek(
    week: asStr(j['week'], ''),
    label: asStr(j['label'], ''),
    income: asStr(j['income']),
    expense: asStr(j['expense']),
    net: asStr(j['net']),
  );
}

class SeasonalReport {
  SeasonalReport({
    required this.currency,
    required this.monthsObserved,
    required this.months,
    required this.daysOfWeek,
    required this.years,
    required this.weekly,
    this.dearestMonth,
    this.cheapestMonth,
    this.heaviestDay,
  });

  final String currency;
  final int monthsObserved;
  final List<SeasonalMonth> months;
  final SeasonalMonth? dearestMonth;
  final SeasonalMonth? cheapestMonth;
  final List<SeasonalDay> daysOfWeek;
  final SeasonalDay? heaviestDay;
  final List<SeasonalYear> years;
  final List<SeasonalWeek> weekly;

  factory SeasonalReport.fromJson(Map<String, dynamic> j) => SeasonalReport(
    currency: asStr(j['currency'], 'ETB'),
    monthsObserved: asInt(j['monthsObserved']),
    months: mapList(j['months'], SeasonalMonth.fromJson),
    dearestMonth: SeasonalMonth.maybe(j['dearestMonth']),
    cheapestMonth: SeasonalMonth.maybe(j['cheapestMonth']),
    daysOfWeek: mapList(j['daysOfWeek'], SeasonalDay.fromJson),
    heaviestDay: j['heaviestDay'] is Map
        ? SeasonalDay.fromJson(asMap(j['heaviestDay']))
        : null,
    years: mapList(j['years'], SeasonalYear.fromJson),
    weekly: mapList(j['weekly'], SeasonalWeek.fromJson),
  );
}

class CategoryMover {
  CategoryMover({
    required this.current,
    required this.previous,
    required this.change,
    required this.isNew,
    required this.stopped,
    this.category,
    this.changePct,
  });

  final Ref? category;
  final String current;
  final String previous;
  final String change;

  /// Null when the category is new this month   a percentage off zero says nothing.
  final double? changePct;
  final bool isNew;
  final bool stopped;

  factory CategoryMover.fromJson(Map<String, dynamic> j) => CategoryMover(
    category: Ref.maybe(j['category']),
    current: asStr(j['current']),
    previous: asStr(j['previous']),
    change: asStr(j['change']),
    changePct: j['changePct'] == null ? null : asNum(j['changePct']),
    isNew: asBool(j['isNew']),
    stopped: asBool(j['stopped']),
  );
}

class CategoryMovers {
  CategoryMovers({
    required this.currency,
    required this.month,
    required this.hasPrevious,
    required this.up,
    required this.down,
  });

  final String currency;
  final String month;
  final bool hasPrevious;
  final List<CategoryMover> up;
  final List<CategoryMover> down;

  factory CategoryMovers.fromJson(Map<String, dynamic> j) => CategoryMovers(
    currency: asStr(j['currency'], 'ETB'),
    month: asStr(j['month'], ''),
    hasPrevious: asBool(j['hasPrevious']),
    up: mapList(j['up'], CategoryMover.fromJson),
    down: mapList(j['down'], CategoryMover.fromJson),
  );
}

class DailySpending {
  DailySpending({
    required this.currency,
    required this.label,
    required this.isMonth,
    required this.start,
    required this.end,
    required this.days,
    required this.total,
    required this.pace,
    required this.dayCount,
    required this.daysUnder,
    required this.daysOver,
    required this.noSpendDays,
    required this.currentStreak,
    required this.bestStreak,
    this.month,
    this.biggestDayDate,
    this.biggestDayAmount,
  });

  final String currency;
  final String label;
  final bool isMonth;
  final String? month;
  final DateTime start;
  final DateTime end;
  final List<SpendDayPoint> days;
  final String total;
  final String pace;
  final int dayCount;
  final int daysUnder;
  final int daysOver;
  final int noSpendDays;
  final int currentStreak;
  final int bestStreak;
  final DateTime? biggestDayDate;
  final String? biggestDayAmount;

  factory DailySpending.fromJson(Map<String, dynamic> j) {
    final s = asMap(j['stats']);
    final biggest = s['biggestDay'] is Map ? asMap(s['biggestDay']) : null;
    return DailySpending(
      currency: asStr(j['currency'], 'ETB'),
      label: asStr(j['label'], ''),
      isMonth: asBool(j['isMonth']),
      month: asStrOrNull(j['month']),
      start: asDate(j['start']) ?? DateTime.now(),
      end: asDate(j['end']) ?? DateTime.now(),
      days: mapList(j['days'], SpendDayPoint.fromJson),
      total: asStr(s['total']),
      pace: asStr(s['pace']),
      dayCount: asInt(s['dayCount']),
      daysUnder: asInt(s['daysUnder']),
      daysOver: asInt(s['daysOver']),
      noSpendDays: asInt(s['noSpendDays']),
      currentStreak: asInt(s['currentStreak']),
      bestStreak: asInt(s['bestStreak']),
      biggestDayDate: biggest == null ? null : asDate(biggest['date']),
      biggestDayAmount: biggest == null ? null : asStr(biggest['amount']),
    );
  }
}

class SpendDayPoint {
  SpendDayPoint({
    required this.date,
    required this.amount,
    required this.spent,
    required this.under,
  });

  final DateTime date;
  final String amount;
  final bool spent;
  final bool under;

  factory SpendDayPoint.fromJson(Map<String, dynamic> j) => SpendDayPoint(
    date: asDate(j['date']) ?? DateTime.now(),
    amount: asStr(j['amount']),
    spent: asBool(j['spent']),
    under: asBool(j['under']),
  );
}
