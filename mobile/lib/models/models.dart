import 'common.dart';

export 'common.dart';

class User {
  User({
    required this.id,
    required this.name,
    required this.email,
    required this.currency,
    required this.firstDayOfWeek,
    this.locale,
    this.calendar,
    this.avatarId,
    this.bannerId,
    this.cashAccountId,
  });

  final String id;
  final String name;
  final String email;
  final String currency;
  final int firstDayOfWeek;
  final String? locale;
  final String? calendar;
  final String? avatarId;
  final String? bannerId;
  final String? cashAccountId;

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: asStr(j['id'], ''),
        name: asStr(j['name'], ''),
        email: asStr(j['email'], ''),
        currency: asStr(j['currency'], 'ETB'),
        firstDayOfWeek: asInt(j['firstDayOfWeek'], 1),
        locale: asStrOrNull(j['locale']),
        calendar: asStrOrNull(j['calendar']),
        avatarId: asStrOrNull(j['avatarId']),
        bannerId: asStrOrNull(j['bannerId']),
        cashAccountId: asStrOrNull(j['cashAccountId']),
      );

  String get firstName => name.split(' ').first;
}

class Account {
  Account({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    required this.openingBalance,
    required this.balance,
    required this.realBalance,
    required this.lockedAmount,
    required this.isDefault,
    required this.archived,
    this.icon,
    this.color,
    this.isShared = false,
    this.householdId,
  });

  final String id;
  final String name;
  final AccountType type;
  final String currency;
  final String openingBalance;

  /// Available: real money minus what budget plans have reserved.
  final String balance;

  /// Money physically in the account.
  final String realBalance;

  /// Reserved by budget plans.
  final String lockedAmount;
  final bool isDefault;
  final bool archived;
  final String? icon;
  final String? color;
  final bool isShared;
  final String? householdId;

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: asStr(j['id'], ''),
        name: asStr(j['name'], ''),
        type: AccountType.parse(j['type']),
        currency: asStr(j['currency'], 'ETB'),
        openingBalance: asStr(j['openingBalance']),
        balance: asStr(j['balance']),
        realBalance: asStr(j['realBalance'], asStr(j['balance'])),
        lockedAmount: asStr(j['lockedAmount']),
        isDefault: asBool(j['isDefault']),
        archived: asBool(j['archived']),
        icon: asStrOrNull(j['icon']),
        color: asStrOrNull(j['color']),
        isShared: asBool(j['isShared']),
        householdId: asStrOrNull(j['householdId']),
      );
}

class TxCategory {
  TxCategory({
    required this.id,
    required this.name,
    required this.kind,
    required this.icon,
    required this.color,
    this.isDefault = false,
    this.archived = false,
    this.transactionCount,
  });

  final String id;
  final String name;

  /// 'INCOME' | 'EXPENSE'
  final String kind;
  final String icon;
  final String color;
  final bool isDefault;
  final bool archived;
  final int? transactionCount;

  bool get isIncome => kind == 'INCOME';

  factory TxCategory.fromJson(Map<String, dynamic> j) => TxCategory(
        id: asStr(j['id'], ''),
        name: asStr(j['name'], ''),
        kind: asStr(j['kind'], 'EXPENSE'),
        icon: asStr(j['icon'], 'tag'),
        color: asStr(j['color'], '#64748b'),
        isDefault: asBool(j['isDefault']),
        archived: asBool(j['archived']),
        transactionCount: j['transactionCount'] == null ? null : asInt(j['transactionCount']),
      );
}

/// A trimmed reference the API embeds inside other rows.
class Ref {
  Ref({required this.id, required this.name, this.icon, this.color, this.currency, this.type});

  final String id;
  final String name;
  final String? icon;
  final String? color;
  final String? currency;
  final String? type;

  static Ref? maybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    if (m['id'] == null) return null;
    return Ref(
      id: asStr(m['id'], ''),
      name: asStr(m['name'], ''),
      icon: asStrOrNull(m['icon']),
      color: asStrOrNull(m['color']),
      currency: asStrOrNull(m['currency']),
      type: asStrOrNull(m['type']),
    );
  }
}

/// Client-only sync state for rows queued in the offline outbox.
enum PendingState { none, pending, syncing, error }

class Transaction {
  Transaction({
    required this.id,
    required this.kind,
    required this.amount,
    required this.currency,
    required this.date,
    required this.accountId,
    required this.tags,
    this.account,
    this.transferAccountId,
    this.transferAccount,
    this.categoryId,
    this.category,
    this.budgetId,
    this.budget,
    this.budgetCycle,
    this.budgetSourceAccountId,
    this.budgetSourceAccount,
    this.note,
    this.payee,
    this.recurringRuleId,
    this.pending = PendingState.none,
  });

  final String id;
  final TxKind kind;
  final String amount;
  final String currency;
  final DateTime date;
  final String accountId;
  final Ref? account;
  final String? transferAccountId;
  final Ref? transferAccount;
  final String? categoryId;
  final Ref? category;

  /// Set when the expense was paid out of a budget plan's pot.
  final String? budgetId;
  final Ref? budget;
  final int? budgetCycle;
  final String? budgetSourceAccountId;
  final Ref? budgetSourceAccount;
  final String? note;
  final String? payee;
  final List<String> tags;
  final String? recurringRuleId;
  final PendingState pending;

  double get value => asNum(amount);

  /// What the row should read as: payee, else note, else the category name.
  String get title {
    if (payee != null && payee!.isNotEmpty) return payee!;
    if (note != null && note!.isNotEmpty) return note!;
    if (kind == TxKind.transfer) {
      return 'Transfer${transferAccount != null ? ' to ${transferAccount!.name}' : ''}';
    }
    return category?.name ?? kind.label;
  }

  factory Transaction.fromJson(Map<String, dynamic> j) => Transaction(
        id: asStr(j['id'], ''),
        kind: TxKind.parse(j['kind']),
        amount: asStr(j['amount']),
        currency: asStr(j['currency'], 'ETB'),
        date: asDate(j['date']) ?? DateTime.now(),
        accountId: asStr(j['accountId'], ''),
        account: Ref.maybe(j['account']),
        transferAccountId: asStrOrNull(j['transferAccountId']),
        transferAccount: Ref.maybe(j['transferAccount']),
        categoryId: asStrOrNull(j['categoryId']),
        category: Ref.maybe(j['category']),
        budgetId: asStrOrNull(j['budgetId']),
        budget: Ref.maybe(j['budget']),
        budgetCycle: j['budgetCycle'] == null ? null : asInt(j['budgetCycle']),
        budgetSourceAccountId: asStrOrNull(j['budgetSourceAccountId']),
        budgetSourceAccount: Ref.maybe(j['budgetSourceAccount']),
        note: asStrOrNull(j['note']),
        payee: asStrOrNull(j['payee']),
        tags: asStrList(j['tags']),
        recurringRuleId: asStrOrNull(j['recurringRuleId']),
      );
}

class TransactionPage {
  TransactionPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<Transaction> items;
  final int total;
  final int page;
  final int pageSize;

  bool get hasMore => page * pageSize < total;

  factory TransactionPage.fromJson(Map<String, dynamic> j) => TransactionPage(
        items: mapList(j['items'], Transaction.fromJson),
        total: asInt(j['total']),
        page: asInt(j['page'], 1),
        pageSize: asInt(j['pageSize'], 20),
      );
}

class RecurringRule {
  RecurringRule({
    required this.id,
    required this.name,
    required this.kind,
    required this.amount,
    required this.currency,
    required this.accountId,
    required this.frequency,
    required this.interval,
    required this.nextRun,
    required this.autoPost,
    required this.active,
    required this.postedCount,
    this.account,
    this.categoryId,
    this.category,
    this.payee,
    this.note,
    this.dayOfMonth,
    this.endDate,
  });

  final String id;
  final String name;
  final TxKind kind;
  final String amount;
  final String currency;
  final String accountId;
  final Ref? account;
  final String? categoryId;
  final Ref? category;
  final String? payee;
  final String? note;
  final Frequency frequency;
  final int interval;
  final int? dayOfMonth;
  final DateTime nextRun;
  final DateTime? endDate;
  final bool autoPost;
  final bool active;
  final int postedCount;

  String get cadence =>
      interval == 1 ? frequency.label : 'Every $interval ${frequency.name}s';

  factory RecurringRule.fromJson(Map<String, dynamic> j) => RecurringRule(
        id: asStr(j['id'], ''),
        name: asStr(j['name'], ''),
        kind: TxKind.parse(j['kind']),
        amount: asStr(j['amount']),
        currency: asStr(j['currency'], 'ETB'),
        accountId: asStr(j['accountId'], ''),
        account: Ref.maybe(j['account']),
        categoryId: asStrOrNull(j['categoryId']),
        category: Ref.maybe(j['category']),
        payee: asStrOrNull(j['payee']),
        note: asStrOrNull(j['note']),
        frequency: Frequency.parse(j['frequency']),
        interval: asInt(j['interval'], 1),
        dayOfMonth: j['dayOfMonth'] == null ? null : asInt(j['dayOfMonth']),
        nextRun: asDate(j['nextRun']) ?? DateTime.now(),
        endDate: asDate(j['endDate']),
        autoPost: asBool(j['autoPost']),
        active: asBool(j['active'], true),
        postedCount: asInt(j['postedCount']),
      );
}

/// `BudgetHealth` — drives the colour of every plan chip and bar.
enum BudgetHealth {
  unplanned,
  scheduled,
  empty,
  partlyFunded,
  ready,
  spending,
  low,
  drained,
  closed;

  static BudgetHealth parse(dynamic v) => switch ('$v') {
        'unplanned' => BudgetHealth.unplanned,
        'scheduled' => BudgetHealth.scheduled,
        'empty' => BudgetHealth.empty,
        'partly-funded' => BudgetHealth.partlyFunded,
        'ready' => BudgetHealth.ready,
        'spending' => BudgetHealth.spending,
        'low' => BudgetHealth.low,
        'drained' => BudgetHealth.drained,
        'closed' => BudgetHealth.closed,
        _ => BudgetHealth.empty,
      };

  String get label => switch (this) {
        BudgetHealth.unplanned => 'Unplanned',
        BudgetHealth.scheduled => 'Scheduled',
        BudgetHealth.empty => 'Empty',
        BudgetHealth.partlyFunded => 'Partly filled',
        BudgetHealth.ready => 'Ready',
        BudgetHealth.spending => 'Spending',
        BudgetHealth.low => 'Running low',
        BudgetHealth.drained => 'Drained',
        BudgetHealth.closed => 'Closed',
      };
}

class BudgetRow {
  BudgetRow({
    required this.id,
    required this.name,
    required this.kind,
    required this.isUnplanned,
    required this.currency,
    required this.recurrenceInterval,
    required this.alertThreshold,
    required this.state,
    required this.plannedAmount,
    required this.openingPlanned,
    required this.adjustedThisCycle,
    required this.fundedAmount,
    required this.carriedIn,
    required this.fillable,
    required this.spentAmount,
    required this.balance,
    required this.pctFunded,
    required this.pctOfPlan,
    required this.pctSpentOfFunded,
    required this.health,
    required this.cycleIndex,
    required this.startsAt,
    required this.started,
    required this.cycleStartedAt,
    this.categoryId,
    this.category,
    this.recurrenceUnit,
    this.recurrenceLabel,
    this.periodNoun,
    this.icon,
    this.color,
    this.note,
    this.closedAt,
    this.nextResetAt,
    this.endDate,
    this.cycleLabel,
  });

  final String id;
  final String name;
  final String? categoryId;
  final Ref? category;
  final BudgetKind kind;

  /// The built-in catch-all plan: no pot, never funded, cannot be deleted.
  final bool isUnplanned;
  final RecurrenceUnit? recurrenceUnit;
  final int recurrenceInterval;

  /// "monthly", "every 6 hours" — ready to print.
  final String? recurrenceLabel;

  /// The noun one cycle is measured in: "month", "6 hours".
  final String? periodNoun;
  final String currency;
  final String? icon;
  final String? color;
  final String? note;
  final int alertThreshold;

  /// 'ACTIVE' | 'CLOSED'
  final String state;
  final DateTime? closedAt;

  /// How much you plan to spend per cycle — also the fill-up ceiling.
  final String plannedAmount;
  final String openingPlanned;
  final String adjustedThisCycle;
  final String fundedAmount;
  final String carriedIn;
  final String fillable;
  final String spentAmount;
  final String balance;

  final double pctFunded;
  final double pctOfPlan;
  final double pctSpentOfFunded;
  final BudgetHealth health;

  final int cycleIndex;
  final DateTime startsAt;
  final bool started;
  final DateTime cycleStartedAt;
  final DateTime? nextResetAt;
  final DateTime? endDate;
  final String? cycleLabel;

  bool get isClosed => state == 'CLOSED';

  factory BudgetRow.fromJson(Map<String, dynamic> j) => BudgetRow(
        id: asStr(j['id'], ''),
        name: asStr(j['name'], ''),
        categoryId: asStrOrNull(j['categoryId']),
        category: Ref.maybe(j['category']),
        kind: BudgetKind.parse(j['kind']),
        isUnplanned: asBool(j['isUnplanned']),
        recurrenceUnit: RecurrenceUnit.parse(j['recurrenceUnit']),
        recurrenceInterval: asInt(j['recurrenceInterval'], 1),
        recurrenceLabel: asStrOrNull(j['recurrenceLabel']),
        periodNoun: asStrOrNull(j['periodNoun']),
        currency: asStr(j['currency'], 'ETB'),
        icon: asStrOrNull(j['icon']),
        color: asStrOrNull(j['color']),
        note: asStrOrNull(j['note']),
        alertThreshold: asInt(j['alertThreshold'], 80),
        state: asStr(j['state'], 'ACTIVE'),
        closedAt: asDate(j['closedAt']),
        plannedAmount: asStr(j['plannedAmount']),
        openingPlanned: asStr(j['openingPlanned']),
        adjustedThisCycle: asStr(j['adjustedThisCycle']),
        fundedAmount: asStr(j['fundedAmount']),
        carriedIn: asStr(j['carriedIn']),
        fillable: asStr(j['fillable']),
        spentAmount: asStr(j['spentAmount']),
        balance: asStr(j['balance']),
        pctFunded: asNum(j['pctFunded']),
        pctOfPlan: asNum(j['pctOfPlan']),
        pctSpentOfFunded: asNum(j['pctSpentOfFunded']),
        health: BudgetHealth.parse(j['health']),
        cycleIndex: asInt(j['cycleIndex']),
        startsAt: asDate(j['startsAt']) ?? DateTime.now(),
        started: asBool(j['started'], true),
        cycleStartedAt: asDate(j['cycleStartedAt']) ?? DateTime.now(),
        nextResetAt: asDate(j['nextResetAt']),
        endDate: asDate(j['endDate']),
        cycleLabel: asStrOrNull(j['cycleLabel']),
      );
}

class BudgetTotals {
  BudgetTotals({
    required this.planned,
    required this.funded,
    required this.spent,
    required this.locked,
    required this.unplannedSpent,
    required this.activeCount,
    required this.closedCount,
  });

  final String planned;
  final String funded;
  final String spent;
  final String locked;

  /// Spending that never went through a funded plan, this cycle.
  final String unplannedSpent;
  final int activeCount;
  final int closedCount;

  factory BudgetTotals.fromJson(Map<String, dynamic> j) => BudgetTotals(
        planned: asStr(j['planned']),
        funded: asStr(j['funded']),
        spent: asStr(j['spent']),
        locked: asStr(j['locked']),
        unplannedSpent: asStr(j['unplannedSpent']),
        activeCount: asInt(j['activeCount']),
        closedCount: asInt(j['closedCount']),
      );
}

class BudgetsResponse {
  BudgetsResponse({required this.items, required this.totals});

  final List<BudgetRow> items;
  final BudgetTotals totals;

  factory BudgetsResponse.fromJson(Map<String, dynamic> j) => BudgetsResponse(
        items: mapList(j['items'], BudgetRow.fromJson),
        totals: BudgetTotals.fromJson(asMap(j['totals'])),
      );
}

class BudgetSource {
  BudgetSource({required this.account, required this.available});
  final Ref? account;
  final String available;

  factory BudgetSource.fromJson(Map<String, dynamic> j) => BudgetSource(
        account: Ref.maybe(j['account']),
        available: asStr(j['available']),
      );
}

class BudgetAllocation {
  BudgetAllocation({
    required this.id,
    required this.kind,
    required this.amount,
    required this.date,
    required this.cycleIndex,
    this.note,
    this.account,
  });

  final String id;

  /// 'FUND' | 'RELEASE'
  final String kind;

  /// Signed: negative for a give-back.
  final String amount;
  final DateTime date;
  final String? note;
  final Ref? account;
  final int cycleIndex;

  factory BudgetAllocation.fromJson(Map<String, dynamic> j) => BudgetAllocation(
        id: asStr(j['id'], ''),
        kind: asStr(j['kind'], 'FUND'),
        amount: asStr(j['amount']),
        date: asDate(j['date']) ?? DateTime.now(),
        note: asStrOrNull(j['note']),
        account: Ref.maybe(j['account']),
        cycleIndex: asInt(j['cycleIndex']),
      );
}

class BudgetAdjustment {
  BudgetAdjustment({
    required this.id,
    required this.amount,
    required this.date,
    required this.cycleIndex,
    this.reason,
  });

  final String id;

  /// Signed: a raise is positive, a cut negative.
  final String amount;
  final DateTime date;
  final String? reason;
  final int cycleIndex;

  factory BudgetAdjustment.fromJson(Map<String, dynamic> j) => BudgetAdjustment(
        id: asStr(j['id'], ''),
        amount: asStr(j['amount']),
        date: asDate(j['date']) ?? DateTime.now(),
        reason: asStrOrNull(j['reason']),
        cycleIndex: asInt(j['cycleIndex']),
      );
}

class BudgetTransaction {
  BudgetTransaction({
    required this.id,
    required this.amount,
    required this.currency,
    required this.date,
    required this.tags,
    this.payee,
    this.note,
    this.category,
    this.account,
    this.budgetCycle,
  });

  final String id;
  final String amount;
  final String currency;
  final DateTime date;
  final String? payee;
  final String? note;
  final List<String> tags;
  final Ref? category;
  final Ref? account;
  final int? budgetCycle;

  factory BudgetTransaction.fromJson(Map<String, dynamic> j) => BudgetTransaction(
        id: asStr(j['id'], ''),
        amount: asStr(j['amount']),
        currency: asStr(j['currency'], 'ETB'),
        date: asDate(j['date']) ?? DateTime.now(),
        payee: asStrOrNull(j['payee']),
        note: asStrOrNull(j['note']),
        tags: asStrList(j['tags']),
        category: Ref.maybe(j['category']),
        account: Ref.maybe(j['account']),
        budgetCycle: j['budgetCycle'] == null ? null : asInt(j['budgetCycle']),
      );
}

/// One row of the plan's movement history — a fund, a release, a spend or an
/// adjustment, already sorted by the API.
class BudgetTimelineEntry {
  BudgetTimelineEntry({
    required this.type,
    required this.at,
    required this.cycleIndex,
    this.allocation,
    this.transaction,
    this.adjustment,
  });

  /// 'fund' | 'release' | 'spend' | 'adjust'
  final String type;
  final DateTime at;
  final int cycleIndex;
  final BudgetAllocation? allocation;
  final BudgetTransaction? transaction;
  final BudgetAdjustment? adjustment;

  factory BudgetTimelineEntry.fromJson(Map<String, dynamic> j) {
    final type = asStr(j['type'], 'spend');
    final entry = asMap(j['entry']);
    return BudgetTimelineEntry(
      type: type,
      at: asDate(j['at']) ?? DateTime.now(),
      cycleIndex: asInt(j['cycleIndex']),
      allocation: (type == 'fund' || type == 'release') ? BudgetAllocation.fromJson(entry) : null,
      transaction: type == 'spend' ? BudgetTransaction.fromJson(entry) : null,
      adjustment: type == 'adjust' ? BudgetAdjustment.fromJson(entry) : null,
    );
  }

  String get amount => switch (type) {
        'fund' || 'release' => allocation?.amount ?? '0',
        'spend' => transaction?.amount ?? '0',
        _ => adjustment?.amount ?? '0',
      };
}

/// A finished cycle, frozen at the moment it rolled over.
class BudgetCycleSnapshot {
  BudgetCycleSnapshot({
    required this.index,
    required this.label,
    required this.startedAt,
    required this.endedAt,
    required this.openingPlanned,
    required this.adjustedAmount,
    required this.plannedAmount,
    required this.carriedIn,
    required this.fundedAmount,
    required this.spentAmount,
    required this.leftoverAmount,
    required this.txCount,
    required this.adjustments,
  });

  final int index;
  final String label;
  final DateTime startedAt;
  final DateTime endedAt;
  final String openingPlanned;
  final String adjustedAmount;
  final String plannedAmount;
  final String carriedIn;
  final String fundedAmount;
  final String spentAmount;
  final String leftoverAmount;
  final int txCount;
  final List<BudgetAdjustment> adjustments;

  factory BudgetCycleSnapshot.fromJson(Map<String, dynamic> j) => BudgetCycleSnapshot(
        index: asInt(j['index']),
        label: asStr(j['label'], ''),
        startedAt: asDate(j['startedAt']) ?? DateTime.now(),
        endedAt: asDate(j['endedAt']) ?? DateTime.now(),
        openingPlanned: asStr(j['openingPlanned']),
        adjustedAmount: asStr(j['adjustedAmount']),
        plannedAmount: asStr(j['plannedAmount']),
        carriedIn: asStr(j['carriedIn']),
        fundedAmount: asStr(j['fundedAmount']),
        spentAmount: asStr(j['spentAmount']),
        leftoverAmount: asStr(j['leftoverAmount']),
        txCount: asInt(j['txCount']),
        adjustments: mapList(j['adjustments'], BudgetAdjustment.fromJson),
      );
}

class BudgetDetail {
  BudgetDetail({
    required this.row,
    required this.timeline,
    required this.timelineTruncated,
    required this.allocations,
    required this.adjustments,
    required this.cycleTxCount,
    required this.sources,
    required this.cycles,
    required this.lifetimeAllocated,
    required this.lifetimeSpent,
    required this.lifetimeTxCount,
    required this.lifetimeCycleCount,
    this.firstTxAt,
  });

  final BudgetRow row;
  final List<BudgetTimelineEntry> timeline;
  final bool timelineTruncated;
  final List<BudgetAllocation> allocations;
  final List<BudgetAdjustment> adjustments;
  final int cycleTxCount;
  final List<BudgetSource> sources;
  final List<BudgetCycleSnapshot> cycles;
  final String lifetimeAllocated;
  final String lifetimeSpent;
  final int lifetimeTxCount;
  final int lifetimeCycleCount;
  final DateTime? firstTxAt;

  factory BudgetDetail.fromJson(Map<String, dynamic> j) {
    final lifetime = asMap(j['lifetime']);
    return BudgetDetail(
      row: BudgetRow.fromJson(j),
      timeline: mapList(j['timeline'], BudgetTimelineEntry.fromJson),
      timelineTruncated: asBool(j['timelineTruncated']),
      allocations: mapList(j['allocations'], BudgetAllocation.fromJson),
      adjustments: mapList(j['adjustments'], BudgetAdjustment.fromJson),
      cycleTxCount: asInt(j['cycleTxCount']),
      sources: mapList(j['sources'], BudgetSource.fromJson),
      cycles: mapList(j['cycles'], BudgetCycleSnapshot.fromJson),
      lifetimeAllocated: asStr(lifetime['allocated']),
      lifetimeSpent: asStr(lifetime['spent']),
      lifetimeTxCount: asInt(lifetime['txCount']),
      lifetimeCycleCount: asInt(lifetime['cycleCount']),
      firstTxAt: asDate(lifetime['firstTxAt']),
    );
  }
}

/// A plan offered as a "pay from" option on the transaction form.
class BudgetSpendSource {
  BudgetSpendSource({
    required this.id,
    required this.name,
    required this.currency,
    required this.balance,
    required this.isUnplanned,
    required this.sources,
    this.icon,
    this.color,
    this.categoryId,
    this.category,
  });

  final String id;
  final String name;
  final String currency;
  final String balance;
  final String? icon;
  final String? color;
  final String? categoryId;
  final Ref? category;

  /// Unplanned has no pot: the caller picks any account to draw on.
  final bool isUnplanned;
  final List<BudgetSource> sources;

  factory BudgetSpendSource.fromJson(Map<String, dynamic> j) => BudgetSpendSource(
        id: asStr(j['id'], ''),
        name: asStr(j['name'], ''),
        currency: asStr(j['currency'], 'ETB'),
        balance: asStr(j['balance']),
        icon: asStrOrNull(j['icon']),
        color: asStrOrNull(j['color']),
        categoryId: asStrOrNull(j['categoryId']),
        category: Ref.maybe(j['category']),
        isUnplanned: asBool(j['isUnplanned']),
        sources: mapList(j['sources'], BudgetSource.fromJson),
      );
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.type,
    required this.message,
    required this.readFlag,
    required this.createdAt,
    this.link,
  });

  final String id;
  final String type;
  final String message;
  final String? link;
  final bool readFlag;
  final DateTime createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: asStr(j['id'], ''),
        type: asStr(j['type'], ''),
        message: asStr(j['message'], ''),
        link: asStrOrNull(j['link']),
        readFlag: asBool(j['readFlag']),
        createdAt: asDate(j['createdAt']) ?? DateTime.now(),
      );
}

class MonthSummary {
  MonthSummary({
    required this.month,
    required this.income,
    required this.expense,
    required this.net,
    required this.avgDailySpend,
    this.currency,
    this.incomeDeltaPct,
    this.expenseDeltaPct,
    this.biggestExpense,
  });

  final String month;
  final String? currency;
  final String income;
  final String expense;
  final String net;
  final double? incomeDeltaPct;
  final double? expenseDeltaPct;
  final String avgDailySpend;
  final Transaction? biggestExpense;

  factory MonthSummary.fromJson(Map<String, dynamic> j) => MonthSummary(
        month: asStr(j['month'], ''),
        currency: asStrOrNull(j['currency']),
        income: asStr(j['income']),
        expense: asStr(j['expense']),
        net: asStr(j['net']),
        incomeDeltaPct: j['incomeDeltaPct'] == null ? null : asNum(j['incomeDeltaPct']),
        expenseDeltaPct: j['expenseDeltaPct'] == null ? null : asNum(j['expenseDeltaPct']),
        avgDailySpend: asStr(j['avgDailySpend']),
        biggestExpense: j['biggestExpense'] == null
            ? null
            : Transaction.fromJson({...asMap(j['biggestExpense']), 'kind': 'EXPENSE'}),
      );

  MonthSummary mergeWith(Map<String, dynamic> override) =>
      MonthSummary.fromJson({...toJson(), ...override});

  Map<String, dynamic> toJson() => {
        'month': month,
        'currency': currency,
        'income': income,
        'expense': expense,
        'net': net,
        'incomeDeltaPct': incomeDeltaPct,
        'expenseDeltaPct': expenseDeltaPct,
        'avgDailySpend': avgDailySpend,
      };
}

class CategoryBreakdownItem {
  CategoryBreakdownItem({
    required this.amount,
    required this.count,
    required this.pct,
    this.category,
  });

  final Ref? category;
  final String amount;
  final int count;
  final double pct;

  factory CategoryBreakdownItem.fromJson(Map<String, dynamic> j) => CategoryBreakdownItem(
        category: Ref.maybe(j['category']),
        amount: asStr(j['amount']),
        count: asInt(j['count']),
        pct: asNum(j['pct']),
      );
}

class UnnecessaryStats {
  UnnecessaryStats({
    required this.total,
    required this.prevTotal,
    required this.count,
    this.category,
    this.deltaPct,
  });

  final Ref? category;
  final String total;
  final String prevTotal;
  final double? deltaPct;
  final int count;

  factory UnnecessaryStats.fromJson(Map<String, dynamic> j) => UnnecessaryStats(
        category: Ref.maybe(j['category']),
        total: asStr(j['total']),
        prevTotal: asStr(j['prevTotal']),
        deltaPct: j['deltaPct'] == null ? null : asNum(j['deltaPct']),
        count: asInt(j['count']),
      );
}

class WeekTotals {
  WeekTotals({
    required this.weekStart,
    required this.weekEnd,
    required this.income,
    required this.expense,
    required this.net,
    required this.avgDailySpend,
    required this.txCount,
    required this.sealed,
    this.topCategory,
    this.topCategoryAmount,
  });

  final DateTime weekStart;
  final DateTime weekEnd;
  final String income;
  final String expense;
  final String net;
  final String avgDailySpend;
  final int txCount;
  final String? topCategory;
  final String? topCategoryAmount;

  /// False while the week is still running.
  final bool sealed;

  factory WeekTotals.fromJson(Map<String, dynamic> j) => WeekTotals(
        weekStart: asDate(j['weekStart']) ?? DateTime.now(),
        weekEnd: asDate(j['weekEnd']) ?? DateTime.now(),
        income: asStr(j['income']),
        expense: asStr(j['expense']),
        net: asStr(j['net']),
        avgDailySpend: asStr(j['avgDailySpend']),
        txCount: asInt(j['txCount']),
        topCategory: asStrOrNull(j['topCategory']),
        topCategoryAmount: asStrOrNull(j['topCategoryAmount']),
        sealed: asBool(j['sealed']),
      );
}

class WeeklySnapshot {
  WeeklySnapshot({
    required this.currency,
    required this.current,
    required this.previous,
    required this.netAmount,
    required this.expenseAmount,
    this.incomeDelta,
    this.expenseDelta,
    this.netDelta,
  });

  final String currency;
  final WeekTotals current;
  final WeekTotals previous;
  final double? incomeDelta;
  final double? expenseDelta;
  final double? netDelta;
  final String netAmount;
  final String expenseAmount;

  factory WeeklySnapshot.fromJson(Map<String, dynamic> j) {
    final d = asMap(j['delta']);
    return WeeklySnapshot(
      currency: asStr(j['currency'], 'ETB'),
      current: WeekTotals.fromJson(asMap(j['current'])),
      previous: WeekTotals.fromJson(asMap(j['previous'])),
      incomeDelta: d['income'] == null ? null : asNum(d['income']),
      expenseDelta: d['expense'] == null ? null : asNum(d['expense']),
      netDelta: d['net'] == null ? null : asNum(d['net']),
      netAmount: asStr(d['netAmount']),
      expenseAmount: asStr(d['expenseAmount']),
    );
  }
}

class SpendDay {
  SpendDay({
    required this.date,
    required this.amount,
    required this.spent,
    required this.under,
  });

  final DateTime date;
  final String amount;
  final bool spent;
  final bool under;

  factory SpendDay.fromJson(Map<String, dynamic> j) => SpendDay(
        date: asDate(j['date']) ?? DateTime.now(),
        amount: asStr(j['amount']),
        spent: asBool(j['spent']),
        under: asBool(j['under']),
      );
}

class SpendingStreak {
  SpendingStreak({
    required this.currency,
    required this.label,
    required this.avgDailySpend,
    required this.currentDays,
    required this.bestStreak,
    required this.daysUnder,
    required this.dayCount,
    required this.total,
    required this.days,
  });

  final String currency;
  final String label;

  /// Average daily spend across the window — the pace to stay under.
  final String avgDailySpend;
  final int currentDays;
  final int bestStreak;
  final int daysUnder;
  final int dayCount;
  final String total;
  final List<SpendDay> days;

  factory SpendingStreak.fromJson(Map<String, dynamic> j) => SpendingStreak(
        currency: asStr(j['currency'], 'ETB'),
        label: asStr(j['label'], ''),
        avgDailySpend: asStr(j['avgDailySpend']),
        currentDays: asInt(j['currentDays']),
        bestStreak: asInt(j['bestStreak']),
        daysUnder: asInt(j['daysUnder']),
        dayCount: asInt(j['dayCount']),
        total: asStr(j['total']),
        days: mapList(j['days'], SpendDay.fromJson),
      );
}

class CategoryHeatAlert {
  CategoryHeatAlert({
    required this.amount,
    required this.prevAmount,
    required this.deltaPct,
    required this.severity,
    this.category,
  });

  final Ref? category;
  final String amount;
  final String prevAmount;
  final double deltaPct;

  /// 'low' | 'medium' | 'high'
  final String severity;

  factory CategoryHeatAlert.fromJson(Map<String, dynamic> j) => CategoryHeatAlert(
        category: Ref.maybe(j['category']),
        amount: asStr(j['amount']),
        prevAmount: asStr(j['prevAmount']),
        deltaPct: asNum(j['deltaPct']),
        severity: asStr(j['severity'], 'low'),
      );
}

class FamilySupportStats {
  FamilySupportStats({
    required this.total,
    required this.prevTotal,
    required this.count,
    required this.recent,
    this.category,
    this.deltaPct,
  });

  final Ref? category;
  final String total;
  final String prevTotal;
  final double? deltaPct;
  final int count;
  final List<Transaction> recent;

  factory FamilySupportStats.fromJson(Map<String, dynamic> j) => FamilySupportStats(
        category: Ref.maybe(j['category']),
        total: asStr(j['total']),
        prevTotal: asStr(j['prevTotal']),
        deltaPct: j['deltaPct'] == null ? null : asNum(j['deltaPct']),
        count: asInt(j['count']),
        recent: mapList(j['recent'], (m) => Transaction.fromJson({...m, 'kind': 'EXPENSE'})),
      );
}

class HouseholdMember {
  HouseholdMember({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isYou,
    this.avatarId,
  });

  final String id;
  final String name;
  final String email;
  final String? avatarId;

  /// 'OWNER' | 'PARTNER'
  final String role;
  final bool isYou;

  factory HouseholdMember.fromJson(Map<String, dynamic> j) => HouseholdMember(
        id: asStr(j['id'], ''),
        name: asStr(j['name'], ''),
        email: asStr(j['email'], ''),
        avatarId: asStrOrNull(j['avatarId']),
        role: asStr(j['role'], 'PARTNER'),
        isYou: asBool(j['isYou']),
      );
}

class HouseholdOverview {
  HouseholdOverview({
    required this.id,
    required this.name,
    required this.role,
    required this.members,
    required this.sharedAccounts,
    required this.sharedBalance,
    required this.pendingInvites,
  });

  final String id;
  final String name;
  final String role;
  final List<HouseholdMember> members;
  final List<Account> sharedAccounts;
  final String sharedBalance;
  final int pendingInvites;

  factory HouseholdOverview.fromJson(Map<String, dynamic> j) => HouseholdOverview(
        id: asStr(j['id'], ''),
        name: asStr(j['name'], ''),
        role: asStr(j['role'], 'PARTNER'),
        members: mapList(j['members'], HouseholdMember.fromJson),
        sharedAccounts: mapList(j['sharedAccounts'], Account.fromJson),
        sharedBalance: asStr(j['sharedBalance']),
        pendingInvites: asInt(j['pendingInvites']),
      );
}

class LedgerPayment {
  LedgerPayment({required this.id, required this.amount, required this.date, this.note, this.transactionId});

  final String id;
  final String amount;
  final DateTime date;
  final String? note;
  final String? transactionId;

  factory LedgerPayment.fromJson(Map<String, dynamic> j) => LedgerPayment(
        id: asStr(j['id'], ''),
        amount: asStr(j['amount']),
        date: asDate(j['date']) ?? DateTime.now(),
        note: asStrOrNull(j['note']),
        transactionId: asStrOrNull(j['transactionId']),
      );
}

class LedgerEntry {
  LedgerEntry({
    required this.id,
    required this.kind,
    required this.counterparty,
    required this.totalAmount,
    required this.paid,
    required this.remaining,
    required this.pct,
    required this.currency,
    required this.status,
    required this.isOverdue,
    required this.payments,
    required this.createdAt,
    this.title,
    this.dueDate,
    this.note,
    this.settledAt,
    this.category,
  });

  final String id;
  final LedgerKind kind;
  final String counterparty;
  final String? title;
  final String totalAmount;
  final String paid;
  final String remaining;
  final double pct;
  final String currency;
  final DateTime? dueDate;
  final String? note;

  /// 'OPEN' | 'SETTLED' | 'CANCELLED'
  final String status;
  final DateTime? settledAt;
  final bool isOverdue;
  final Ref? category;
  final List<LedgerPayment> payments;
  final DateTime createdAt;

  bool get isOpen => status == 'OPEN';

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
        id: asStr(j['id'], ''),
        kind: LedgerKind.parse(j['kind']),
        counterparty: asStr(j['counterparty'], ''),
        title: asStrOrNull(j['title']),
        totalAmount: asStr(j['totalAmount']),
        paid: asStr(j['paid']),
        remaining: asStr(j['remaining']),
        pct: asNum(j['pct']),
        currency: asStr(j['currency'], 'ETB'),
        dueDate: asDate(j['dueDate']),
        note: asStrOrNull(j['note']),
        status: asStr(j['status'], 'OPEN'),
        settledAt: asDate(j['settledAt']),
        isOverdue: asBool(j['isOverdue']),
        category: Ref.maybe(j['category']),
        payments: mapList(j['payments'], LedgerPayment.fromJson),
        createdAt: asDate(j['createdAt']) ?? DateTime.now(),
      );
}

class LedgerSummary {
  LedgerSummary({
    required this.receivable,
    required this.payable,
    required this.expectedIn,
    required this.expectedOut,
    required this.netPosition,
    required this.openCount,
    required this.overdueCount,
    required this.highlights,
    required this.overdue,
    required this.dueSoon,
    required this.forecastMonth,
    required this.forecastIn,
    required this.forecastOut,
    required this.netIfOnTime,
    required this.allOpenNet,
    this.currency,
  });

  final String? currency;
  final String receivable;
  final String payable;
  final String expectedIn;
  final String expectedOut;
  final String netPosition;
  final int openCount;
  final int overdueCount;
  final List<LedgerEntry> highlights;
  final List<LedgerEntry> overdue;
  final List<LedgerEntry> dueSoon;
  final String forecastMonth;
  final String forecastIn;
  final String forecastOut;
  final String netIfOnTime;
  final String allOpenNet;

  factory LedgerSummary.fromJson(Map<String, dynamic> j) {
    final f = asMap(j['forecast']);
    return LedgerSummary(
      currency: asStrOrNull(j['currency']),
      receivable: asStr(j['receivable']),
      payable: asStr(j['payable']),
      expectedIn: asStr(j['expectedIn']),
      expectedOut: asStr(j['expectedOut']),
      netPosition: asStr(j['netPosition']),
      openCount: asInt(j['openCount']),
      overdueCount: asInt(j['overdueCount']),
      highlights: mapList(j['highlights'], LedgerEntry.fromJson),
      overdue: mapList(j['overdue'], LedgerEntry.fromJson),
      dueSoon: mapList(j['dueSoon'], LedgerEntry.fromJson),
      forecastMonth: asStr(f['month'], ''),
      forecastIn: asStr(f['expectedIn']),
      forecastOut: asStr(f['expectedOut']),
      netIfOnTime: asStr(f['netIfOnTime']),
      allOpenNet: asStr(f['allOpenNet']),
    );
  }
}

class LedgerPersonGroup {
  LedgerPersonGroup({
    required this.counterparty,
    required this.openCount,
    required this.receivable,
    required this.expectedIn,
    required this.payable,
    required this.expectedOut,
    required this.netRemaining,
    required this.netDirection,
    required this.entries,
  });

  final String counterparty;
  final int openCount;
  final String receivable;
  final String expectedIn;
  final String payable;
  final String expectedOut;
  final String netRemaining;

  /// 'in' | 'out'
  final String netDirection;
  final List<LedgerEntry> entries;

  factory LedgerPersonGroup.fromJson(Map<String, dynamic> j) => LedgerPersonGroup(
        counterparty: asStr(j['counterparty'], ''),
        openCount: asInt(j['openCount']),
        receivable: asStr(j['receivable']),
        expectedIn: asStr(j['expectedIn']),
        payable: asStr(j['payable']),
        expectedOut: asStr(j['expectedOut']),
        netRemaining: asStr(j['netRemaining']),
        netDirection: asStr(j['netDirection'], 'in'),
        entries: mapList(j['entries'], LedgerEntry.fromJson),
      );
}

/// The plan a want was turned into, if it has been planned.
class WishPlanRef {
  WishPlanRef({
    required this.id,
    required this.name,
    required this.currency,
    required this.state,
    required this.kind,
    required this.plannedAmount,
    this.icon,
    this.color,
  });

  final String id;
  final String name;
  final String? icon;
  final String? color;
  final String currency;
  final String state;
  final BudgetKind kind;
  final String plannedAmount;

  static WishPlanRef? maybe(dynamic v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    if (j['id'] == null) return null;
    return WishPlanRef(
      id: asStr(j['id'], ''),
      name: asStr(j['name'], ''),
      icon: asStrOrNull(j['icon']),
      color: asStrOrNull(j['color']),
      currency: asStr(j['currency'], 'ETB'),
      state: asStr(j['state'], 'ACTIVE'),
      kind: BudgetKind.parse(j['kind']),
      plannedAmount: asStr(j['plannedAmount']),
    );
  }
}

/// A want is just the idea of a thing: no cost, no savings.
class WishlistItem {
  WishlistItem({
    required this.id,
    required this.name,
    required this.priority,
    required this.status,
    required this.createdAt,
    this.note,
    this.link,
    this.emoji,
    this.budgetId,
    this.plan,
    this.plannedAt,
    this.boughtAt,
  });

  final String id;
  final String name;
  final int priority;
  final WishlistStatus status;
  final String? note;
  final String? link;
  final String? emoji;
  final String? budgetId;
  final WishPlanRef? plan;
  final DateTime? plannedAt;
  final DateTime? boughtAt;
  final DateTime createdAt;

  factory WishlistItem.fromJson(Map<String, dynamic> j) => WishlistItem(
        id: asStr(j['id'], ''),
        name: asStr(j['name'], ''),
        priority: asInt(j['priority'], 3),
        status: WishlistStatus.parse(j['status']),
        note: asStrOrNull(j['note']),
        link: asStrOrNull(j['link']),
        emoji: asStrOrNull(j['emoji']),
        budgetId: asStrOrNull(j['budgetId']),
        plan: WishPlanRef.maybe(j['plan']),
        plannedAt: asDate(j['plannedAt']),
        boughtAt: asDate(j['boughtAt']),
        createdAt: asDate(j['createdAt']) ?? DateTime.now(),
      );
}

class WishlistResponse {
  WishlistResponse({
    required this.items,
    required this.wanting,
    required this.planned,
    required this.bought,
    required this.dropped,
    required this.total,
  });

  final List<WishlistItem> items;
  final int wanting;
  final int planned;
  final int bought;
  final int dropped;
  final int total;

  factory WishlistResponse.fromJson(Map<String, dynamic> j) {
    final s = asMap(j['stats']);
    return WishlistResponse(
      items: mapList(j['items'], WishlistItem.fromJson),
      wanting: asInt(s['wanting']),
      planned: asInt(s['planned']),
      bought: asInt(s['bought']),
      dropped: asInt(s['dropped']),
      total: asInt(s['total']),
    );
  }
}

class WishlistDigest {
  WishlistDigest({required this.activeCount, required this.plannedCount, required this.top});

  final int activeCount;
  final int plannedCount;
  final List<WishlistItem> top;

  factory WishlistDigest.fromJson(Map<String, dynamic> j) => WishlistDigest(
        activeCount: asInt(j['activeCount']),
        plannedCount: asInt(j['plannedCount']),
        top: mapList(j['top'], WishlistItem.fromJson),
      );
}

class GuideSection {
  GuideSection({required this.heading, required this.body});
  final String heading;
  final String body;

  factory GuideSection.fromJson(Map<String, dynamic> j) => GuideSection(
        heading: asStr(j['heading'], ''),
        body: asStr(j['body'], ''),
      );
}

class Guide {
  Guide({
    required this.id,
    required this.title,
    required this.emoji,
    required this.category,
    required this.readMins,
    required this.tagline,
    required this.sections,
    this.href,
  });

  final String id;
  final String title;
  final String emoji;

  /// 'getting-started' | 'saving' | 'spending' | 'debt'
  final String category;
  final int readMins;
  final String tagline;
  final String? href;
  final List<GuideSection> sections;

  factory Guide.fromJson(Map<String, dynamic> j) => Guide(
        id: asStr(j['id'], ''),
        title: asStr(j['title'], ''),
        emoji: asStr(j['emoji'], '📘'),
        category: asStr(j['category'], 'getting-started'),
        readMins: asInt(j['readMins'], 3),
        tagline: asStr(j['tagline'], ''),
        href: asStrOrNull(j['href']),
        sections: mapList(j['sections'], GuideSection.fromJson),
      );
}

class GuideSuggestion {
  GuideSuggestion({
    required this.id,
    required this.title,
    required this.body,
    required this.tone,
    this.guideId,
    this.href,
    this.cta,
  });

  final String id;
  final String title;
  final String body;

  /// 'tip' | 'success' | 'warning'
  final String tone;
  final String? guideId;
  final String? href;
  final String? cta;

  factory GuideSuggestion.fromJson(Map<String, dynamic> j) => GuideSuggestion(
        id: asStr(j['id'], ''),
        title: asStr(j['title'], ''),
        body: asStr(j['body'], ''),
        tone: asStr(j['tone'], 'tip'),
        guideId: asStrOrNull(j['guideId']),
        href: asStrOrNull(j['href']),
        cta: asStrOrNull(j['cta']),
      );
}

class GuidesOverview {
  GuidesOverview({required this.guides, required this.suggestions});
  final List<Guide> guides;
  final List<GuideSuggestion> suggestions;

  factory GuidesOverview.fromJson(Map<String, dynamic> j) => GuidesOverview(
        guides: mapList(j['guides'], Guide.fromJson),
        suggestions: mapList(j['suggestions'], GuideSuggestion.fromJson),
      );
}

/// Per-currency slice of the dashboard, so switching currency never refetches.
class CurrencyBreakdown {
  CurrencyBreakdown({
    required this.currency,
    required this.totalBalance,
    required this.realBalance,
    required this.budgetLocked,
    required this.accountCount,
    required this.month,
  });

  final String currency;
  final String totalBalance;
  final String realBalance;
  final String budgetLocked;
  final int accountCount;
  final MonthSummary month;

  factory CurrencyBreakdown.fromJson(Map<String, dynamic> j) => CurrencyBreakdown(
        currency: asStr(j['currency'], 'ETB'),
        totalBalance: asStr(j['totalBalance']),
        realBalance: asStr(j['realBalance']),
        budgetLocked: asStr(j['budgetLocked']),
        accountCount: asInt(j['accountCount']),
        month: MonthSummary.fromJson(asMap(j['month'])),
      );
}

class ConvertedTotal {
  ConvertedTotal({
    required this.amount,
    required this.baseCurrency,
    required this.complete,
    required this.missingRates,
  });

  final String amount;
  final String baseCurrency;
  final bool complete;
  final List<String> missingRates;

  static ConvertedTotal? maybe(dynamic v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    return ConvertedTotal(
      amount: asStr(j['amount']),
      baseCurrency: asStr(j['baseCurrency'], 'ETB'),
      complete: asBool(j['complete'], true),
      missingRates: asStrList(j['missingRates']),
    );
  }
}

class DashboardData {
  DashboardData({
    required this.totalBalance,
    required this.accounts,
    required this.month,
    required this.budgetTotals,
    required this.budgetsAtRisk,
    required this.budgets,
    required this.recentTransactions,
    required this.topCategories,
    required this.upcomingRecurring,
    required this.unnecessary,
    required this.weeklySnapshot,
    required this.spendingStreak,
    required this.categoryHeatAlerts,
    required this.familySupport,
    required this.tab,
    required this.wishlist,
    required this.currencies,
    required this.currencyBreakdown,
    this.displayCurrency,
    this.realBalance,
    this.budgetLocked,
    this.convertedTotal,
    this.household,
  });

  final String totalBalance;
  final String? displayCurrency;
  final List<String> currencies;
  final String? realBalance;
  final String? budgetLocked;
  final List<CurrencyBreakdown> currencyBreakdown;
  final ConvertedTotal? convertedTotal;
  final List<Account> accounts;
  final MonthSummary month;
  final BudgetTotals budgetTotals;
  final List<BudgetRow> budgetsAtRisk;
  final List<BudgetRow> budgets;
  final List<Transaction> recentTransactions;
  final List<CategoryBreakdownItem> topCategories;
  final List<RecurringRule> upcomingRecurring;
  final UnnecessaryStats unnecessary;
  final WeeklySnapshot weeklySnapshot;
  final SpendingStreak spendingStreak;
  final List<CategoryHeatAlert> categoryHeatAlerts;
  final FamilySupportStats familySupport;
  final HouseholdOverview? household;
  final LedgerSummary tab;
  final WishlistDigest wishlist;

  factory DashboardData.fromJson(Map<String, dynamic> j) => DashboardData(
        totalBalance: asStr(j['totalBalance']),
        displayCurrency: asStrOrNull(j['displayCurrency']),
        currencies: asStrList(j['currencies']),
        realBalance: asStrOrNull(j['realBalance']),
        budgetLocked: asStrOrNull(j['budgetLocked']),
        currencyBreakdown: mapList(j['currencyBreakdown'], CurrencyBreakdown.fromJson),
        convertedTotal: ConvertedTotal.maybe(j['convertedTotal']),
        accounts: mapList(j['accounts'], Account.fromJson),
        month: MonthSummary.fromJson(asMap(j['month'])),
        budgetTotals: BudgetTotals.fromJson(asMap(j['budgetTotals'])),
        budgetsAtRisk: mapList(j['budgetsAtRisk'], BudgetRow.fromJson),
        budgets: mapList(j['budgets'], BudgetRow.fromJson),
        recentTransactions: mapList(j['recentTransactions'], Transaction.fromJson),
        topCategories: mapList(j['topCategories'], CategoryBreakdownItem.fromJson),
        upcomingRecurring: mapList(j['upcomingRecurring'], RecurringRule.fromJson),
        unnecessary: UnnecessaryStats.fromJson(asMap(j['unnecessary'])),
        weeklySnapshot: WeeklySnapshot.fromJson(asMap(j['weeklySnapshot'])),
        spendingStreak: SpendingStreak.fromJson(asMap(j['spendingStreak'])),
        categoryHeatAlerts: mapList(j['categoryHeatAlerts'], CategoryHeatAlert.fromJson),
        familySupport: FamilySupportStats.fromJson(asMap(j['familySupport'])),
        household: j['household'] == null ? null : HouseholdOverview.fromJson(asMap(j['household'])),
        tab: LedgerSummary.fromJson(asMap(j['tab'])),
        wishlist: WishlistDigest.fromJson(asMap(j['wishlist'])),
      );
}
