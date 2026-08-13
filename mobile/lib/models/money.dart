/// Movements, undo, the Money Doctor, and payday rules.
///
/// Kept apart from `models.dart` because these describe the money *system*
/// rather than the things it moves - what happened, whether it adds up, and the
/// rules that fill plans on their own.
library;

import 'models.dart';

// ---------------------------------------------------------------------------
// Movements and undo
// ---------------------------------------------------------------------------

/// What kind of thing moved money. Spending, income and transfers change what
/// you own; setting money aside only changes what you can spend.
enum MovementType {
  expense,
  income,
  transfer,
  fund,
  release,
  move,
  adjust;

  static MovementType parse(dynamic v) {
    final s = asStr(v, 'expense');
    return MovementType.values.firstWhere(
      (m) => m.name == s,
      orElse: () => MovementType.expense,
    );
  }
}

/// One thing that moved money, from any of the three ledgers.
class Movement {
  Movement({
    required this.id,
    required this.type,
    required this.title,
    required this.amount,
    required this.currency,
    required this.at,
    required this.recordedAt,
    required this.undoable,
    this.subtitle,
    this.blockedReason,
    this.accountId,
    this.budgetId,
  });

  /// `tx:<id>`, `alloc:<id>` or `adj:<id>`.
  final String id;
  final MovementType type;
  final String title;
  final String? subtitle;

  /// Signed: negative took money out, or tied it up in a plan.
  final String amount;
  final String currency;
  final DateTime at;
  final DateTime recordedAt;
  final bool undoable;

  /// Why it cannot be taken back, when it cannot.
  final String? blockedReason;
  final String? accountId;
  final String? budgetId;

  double get value => asNum(amount);

  factory Movement.fromJson(Map<String, dynamic> j) => Movement(
    id: asStr(j['id'], ''),
    type: MovementType.parse(j['type']),
    title: asStr(j['title'], 'Movement'),
    subtitle: asStrOrNull(j['subtitle']),
    amount: asStr(j['amount']),
    currency: asStr(j['currency'], 'ETB'),
    at: asDate(j['at']) ?? DateTime.now(),
    recordedAt: asDate(j['recordedAt']) ?? DateTime.now(),
    undoable: asBool(j['undoable']),
    blockedReason: asStrOrNull(j['blockedReason']),
    accountId: asStrOrNull(j['accountId']),
    budgetId: asStrOrNull(j['budgetId']),
  );
}

class MovementsResponse {
  MovementsResponse({required this.items, required this.undoWindowHours});

  final List<Movement> items;
  final int undoWindowHours;

  factory MovementsResponse.fromJson(Map<String, dynamic> j) =>
      MovementsResponse(
        items: mapList(j['items'], Movement.fromJson),
        undoWindowHours: asInt(j['undoWindowHours'], 48),
      );
}

// ---------------------------------------------------------------------------
// The Money Doctor
// ---------------------------------------------------------------------------

/// A place where the books do not balance. Normally none of these exist.
class MoneyProblem {
  MoneyProblem({
    required this.code,
    required this.message,
    required this.amount,
    this.accountId,
    this.budgetId,
  });

  /// I2..I6 - which rule is broken.
  final String code;
  final String message;
  final String amount;
  final String? accountId;
  final String? budgetId;

  factory MoneyProblem.fromJson(Map<String, dynamic> j) => MoneyProblem(
    code: asStr(j['code'], ''),
    message: asStr(j['message'], ''),
    amount: asStr(j['amount']),
    accountId: asStrOrNull(j['accountId']),
    budgetId: asStrOrNull(j['budgetId']),
  );
}

/// A wallet where the bank's own reported figure disagrees with ours.
class WalletDrift {
  WalletDrift({
    required this.account,
    required this.santimBalance,
    required this.bankBalance,
    required this.difference,
    required this.direction,
    this.reportedAt,
  });

  final Ref account;
  final String santimBalance;
  final String bankBalance;
  final String difference;

  /// 'missing-spending' | 'missing-income'
  final String direction;
  final DateTime? reportedAt;

  bool get missingSpending => direction == 'missing-spending';

  factory WalletDrift.fromJson(Map<String, dynamic> j) => WalletDrift(
    account: Ref.maybe(j['account']) ?? Ref(id: '', name: 'Wallet'),
    santimBalance: asStr(j['santimBalance']),
    bankBalance: asStr(j['bankBalance']),
    difference: asStr(j['difference']),
    direction: asStr(j['direction'], 'missing-spending'),
    reportedAt: asDate(j['reportedAt']),
  );
}

class WalletHealth {
  WalletHealth({
    required this.id,
    required this.name,
    required this.currency,
    required this.real,
    required this.reserved,
    required this.free,
    this.icon,
    this.color,
  });

  final String id;
  final String name;
  final String currency;
  final String real;
  final String reserved;
  final String free;
  final String? icon;
  final String? color;

  factory WalletHealth.fromJson(Map<String, dynamic> j) => WalletHealth(
    id: asStr(j['id'], ''),
    name: asStr(j['name'], ''),
    currency: asStr(j['currency'], 'ETB'),
    real: asStr(j['real']),
    reserved: asStr(j['reserved']),
    free: asStr(j['free']),
    icon: asStrOrNull(j['icon']),
    color: asStrOrNull(j['color']),
  );
}

class PlanHolding {
  PlanHolding({
    required this.id,
    required this.name,
    required this.currency,
    required this.holding,
    this.icon,
    this.color,
  });

  final String id;
  final String name;
  final String currency;
  final String holding;
  final String? icon;
  final String? color;

  factory PlanHolding.fromJson(Map<String, dynamic> j) => PlanHolding(
    id: asStr(j['id'], ''),
    name: asStr(j['name'], ''),
    currency: asStr(j['currency'], 'ETB'),
    holding: asStr(j['holding']),
    icon: asStrOrNull(j['icon']),
    color: asStrOrNull(j['color']),
  );
}

/// The health check on your own books, and everything needed to act on it.
class MoneyHealth {
  MoneyHealth({
    required this.healthy,
    required this.checkedAt,
    required this.problems,
    required this.drift,
    required this.currency,
    required this.real,
    required this.reserved,
    required this.readyToAssign,
    required this.wallets,
    required this.plans,
  });

  final bool healthy;
  final DateTime checkedAt;
  final List<MoneyProblem> problems;
  final List<WalletDrift> drift;
  final String currency;
  final String real;
  final String reserved;
  final String readyToAssign;
  final List<WalletHealth> wallets;
  final List<PlanHolding> plans;

  factory MoneyHealth.fromJson(Map<String, dynamic> j) {
    final money = asMap(j['money']);
    return MoneyHealth(
      healthy: asBool(j['healthy']),
      checkedAt: asDate(j['checkedAt']) ?? DateTime.now(),
      problems: mapList(j['problems'], MoneyProblem.fromJson),
      drift: mapList(j['drift'], WalletDrift.fromJson),
      currency: asStr(j['currency'], 'ETB'),
      real: asStr(money['real']),
      reserved: asStr(money['reserved']),
      readyToAssign: asStr(money['readyToAssign']),
      wallets: mapList(j['wallets'], WalletHealth.fromJson),
      plans: mapList(j['plans'], PlanHolding.fromJson),
    );
  }
}

// ---------------------------------------------------------------------------
// Payday rules
// ---------------------------------------------------------------------------

/// How much of an arriving payday a step puts into its plan.
enum FundingStepMode {
  fixed,
  percent,
  fill;

  String get wire => switch (this) {
    FundingStepMode.fixed => 'FIXED',
    FundingStepMode.percent => 'PERCENT',
    FundingStepMode.fill => 'FILL',
  };

  String get label => switch (this) {
    FundingStepMode.fixed => 'a set amount',
    FundingStepMode.percent => 'a share of what arrives',
    FundingStepMode.fill => 'top it up',
  };

  static FundingStepMode parse(dynamic v) {
    final s = asStr(v, 'FILL').toUpperCase();
    return switch (s) {
      'FIXED' => FundingStepMode.fixed,
      'PERCENT' => FundingStepMode.percent,
      _ => FundingStepMode.fill,
    };
  }
}

class FundingStep {
  FundingStep({
    required this.id,
    required this.budgetId,
    required this.position,
    required this.mode,
    required this.amount,
    this.budget,
  });

  final String id;
  final String budgetId;
  final Ref? budget;
  final int position;
  final FundingStepMode mode;
  final String amount;

  factory FundingStep.fromJson(Map<String, dynamic> j) => FundingStep(
    id: asStr(j['id'], ''),
    budgetId: asStr(j['budgetId'], ''),
    budget: Ref.maybe(j['budget']),
    position: asInt(j['position']),
    mode: FundingStepMode.parse(j['mode']),
    amount: asStr(j['amount']),
  );

  Map<String, dynamic> toJson() => {
    'budgetId': budgetId,
    'mode': mode.wire,
    'amount': asNum(amount),
  };
}

/// "When my salary lands, fill Rent, then Groceries, then Transport."
class FundingRule {
  FundingRule({
    required this.id,
    required this.name,
    required this.currency,
    required this.minAmount,
    required this.active,
    required this.confirmFirst,
    required this.steps,
    this.accountId,
    this.account,
    this.lastRunAt,
  });

  final String id;
  final String name;
  final String? accountId;
  final Ref? account;
  final String currency;
  final String minAmount;
  final bool active;

  /// Ask before moving money. On by default - money moving on its own is
  /// alarming the first time it happens.
  final bool confirmFirst;
  final DateTime? lastRunAt;
  final List<FundingStep> steps;

  factory FundingRule.fromJson(Map<String, dynamic> j) => FundingRule(
    id: asStr(j['id'], ''),
    name: asStr(j['name'], ''),
    accountId: asStrOrNull(j['accountId']),
    account: Ref.maybe(j['account']),
    currency: asStr(j['currency'], 'ETB'),
    minAmount: asStr(j['minAmount']),
    active: asBool(j['active']),
    confirmFirst: asBool(j['confirmFirst']),
    lastRunAt: asDate(j['lastRunAt']),
    steps: mapList(j['steps'], FundingStep.fromJson),
  );
}

class PlannedFill {
  PlannedFill({
    required this.budgetId,
    required this.budgetName,
    required this.amount,
    required this.mode,
    this.icon,
    this.color,
    this.short,
  });

  final String budgetId;
  final String budgetName;
  final String amount;
  final FundingStepMode mode;
  final String? icon;
  final String? color;

  /// Set when the money ran out before this plan got its full share.
  final String? short;

  factory PlannedFill.fromJson(Map<String, dynamic> j) => PlannedFill(
    budgetId: asStr(j['budgetId'], ''),
    budgetName: asStr(j['budgetName'], ''),
    amount: asStr(j['amount']),
    mode: FundingStepMode.parse(j['mode']),
    icon: asStrOrNull(j['icon']),
    color: asStrOrNull(j['color']),
    short: asStrOrNull(j['short']),
  );
}

/// What a payday rule would do, before it does it.
class FundingPreview {
  FundingPreview({
    required this.ruleId,
    required this.ruleName,
    required this.accountId,
    required this.accountName,
    required this.currency,
    required this.availableAmount,
    required this.fills,
    required this.totalAmount,
    required this.leftOver,
    this.triggerAmount,
    this.ran = false,
  });

  final String ruleId;
  final String ruleName;
  final String accountId;
  final String accountName;
  final String currency;
  final String availableAmount;

  /// The income that triggered this, when there is one.
  final String? triggerAmount;
  final List<PlannedFill> fills;
  final String totalAmount;
  final String leftOver;
  final bool ran;

  factory FundingPreview.fromJson(Map<String, dynamic> j) => FundingPreview(
    ruleId: asStr(j['ruleId'], ''),
    ruleName: asStr(j['ruleName'], ''),
    accountId: asStr(j['accountId'], ''),
    accountName: asStr(j['accountName'], ''),
    currency: asStr(j['currency'], 'ETB'),
    availableAmount: asStr(j['availableAmount']),
    triggerAmount: asStrOrNull(j['triggerAmount']),
    fills: mapList(j['fills'], PlannedFill.fromJson),
    totalAmount: asStr(j['totalAmount']),
    leftOver: asStr(j['leftOver']),
    ran: asBool(j['ran']),
  );
}
