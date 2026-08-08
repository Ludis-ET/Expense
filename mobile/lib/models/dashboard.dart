import 'finance.dart';

/// This month's income/expense roll-up, as `/analytics/summary` returns it.
class MonthSummary {
  const MonthSummary({
    required this.currency,
    required this.income,
    required this.expense,
    required this.net,
    required this.avgDailySpend,
    this.expenseDeltaPct,
    this.incomeDeltaPct,
  });

  final String currency;
  final String income;
  final String expense;
  final String net;
  final String avgDailySpend;

  /// Change against the previous month. Null when there is no prior month to
  /// compare against - which is not the same as 0% and must not render as it.
  final double? expenseDeltaPct;
  final double? incomeDeltaPct;

  const MonthSummary.empty()
      : currency = 'ETB',
        income = '0.00',
        expense = '0.00',
        net = '0.00',
        avgDailySpend = '0.00',
        expenseDeltaPct = null,
        incomeDeltaPct = null;

  factory MonthSummary.fromJson(Map<String, dynamic> json) => MonthSummary(
        currency: json['currency'] as String? ?? 'ETB',
        income: json['income']?.toString() ?? '0.00',
        expense: json['expense']?.toString() ?? '0.00',
        net: json['net']?.toString() ?? '0.00',
        avgDailySpend: json['avgDailySpend']?.toString() ?? '0.00',
        expenseDeltaPct: (json['expenseDeltaPct'] as num?)?.toDouble(),
        incomeDeltaPct: (json['incomeDeltaPct'] as num?)?.toDouble(),
      );
}

/// The `/dashboard` payload, trimmed to what the mobile home screen shows.
class DashboardData {
  const DashboardData({
    required this.totalBalance,
    required this.realBalance,
    required this.budgetLocked,
    required this.displayCurrency,
    required this.month,
    required this.recent,
    required this.budgetsAtRisk,
  });

  /// Money genuinely free to spend: real balance minus plan reservations.
  final String totalBalance;
  final String realBalance;

  /// The slice held by budget plans.
  final String budgetLocked;

  final String displayCurrency;
  final MonthSummary month;
  final List<Transaction> recent;

  /// Active plans running low or already drained.
  final List<Budget> budgetsAtRisk;

  const DashboardData.empty()
      : totalBalance = '0.00',
        realBalance = '0.00',
        budgetLocked = '0.00',
        displayCurrency = 'ETB',
        month = const MonthSummary.empty(),
        recent = const [],
        budgetsAtRisk = const [];

  factory DashboardData.fromJson(Map<String, dynamic> json) => DashboardData(
        totalBalance: json['totalBalance']?.toString() ?? '0.00',
        realBalance: json['realBalance']?.toString() ?? '0.00',
        budgetLocked: json['budgetLocked']?.toString() ?? '0.00',
        displayCurrency: json['displayCurrency'] as String? ?? 'ETB',
        month: MonthSummary.fromJson((json['month'] as Map<String, dynamic>?) ?? const {}),
        recent: ((json['recentTransactions'] as List?) ?? const [])
            .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
            .toList(),
        budgetsAtRisk: ((json['budgetsAtRisk'] as List?) ?? const [])
            .map((e) => Budget.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
