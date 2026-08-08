import '../core/formatting.dart';

/// Amounts are kept as the decimal strings the API sends. Parsing happens at
/// the point of display only - see the note in `Money`.

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    this.name,
    this.currency = 'ETB',
    this.locale = 'en',
    this.calendar = 'gregorian',
    this.firstDayOfWeek = 1,
    this.avatarId,
    this.bannerId,
  });

  final String id;
  final String email;
  final String? name;
  final String currency;
  final String locale;
  final String calendar;
  final int firstDayOfWeek;
  final String? avatarId;
  final String? bannerId;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        email: json['email'] as String,
        name: json['name'] as String?,
        currency: json['currency'] as String? ?? 'ETB',
        locale: json['locale'] as String? ?? 'en',
        calendar: json['calendar'] as String? ?? 'gregorian',
        firstDayOfWeek: (json['firstDayOfWeek'] as num?)?.toInt() ?? 1,
        avatarId: json['avatarId'] as String?,
        bannerId: json['bannerId'] as String?,
      );

  AppUser copyWith({
    String? name,
    String? currency,
    String? locale,
    String? calendar,
    int? firstDayOfWeek,
    String? avatarId,
    String? bannerId,
  }) =>
      AppUser(
        id: id,
        email: email,
        name: name ?? this.name,
        currency: currency ?? this.currency,
        locale: locale ?? this.locale,
        calendar: calendar ?? this.calendar,
        firstDayOfWeek: firstDayOfWeek ?? this.firstDayOfWeek,
        avatarId: avatarId ?? this.avatarId,
        bannerId: bannerId ?? this.bannerId,
      );
}

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    this.realBalance,
    this.available,
    this.locked,
    this.accountNumber,
    this.archived = false,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final String type;
  final String currency;

  /// The bank's own number for this wallet, usually masked ("****4821").
  /// Lets a transfer message be recognised as a move between the user's own
  /// accounts instead of being recorded as spending.
  final String? accountNumber;

  /// Money physically in the account.
  final String? realBalance;

  /// Real balance minus what budget plans have reserved - the API calls this
  /// field `balance`. It is what the overdraw guard actually enforces against,
  /// so it is the figure to show wherever "can I spend this?" is the question.
  final String? available;

  /// The slice reserved by budget plans.
  final String? locked;

  final bool archived;
  final bool isDefault;

  bool get hasReservation => Money.parse(locked) > 0;

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String,
        name: json['name'] as String,
        type: json['type'] as String? ?? 'CASH',
        currency: json['currency'] as String? ?? 'ETB',
        realBalance: json['realBalance']?.toString(),
        available: json['balance']?.toString(),
        locked: json['lockedAmount']?.toString(),
        accountNumber: json['accountNumber'] as String?,
        archived: json['archived'] as bool? ?? false,
        isDefault: json['isDefault'] as bool? ?? false,
      );
}

/// Named `TxCategory` rather than `Category` because Flutter's foundation
/// library exports an annotation class by that name, and the collision would
/// otherwise force a prefixed import in every file that renders a picker.
class TxCategory {
  const TxCategory({
    required this.id,
    required this.name,
    required this.kind,
    this.icon,
    this.color,
    this.archived = false,
  });

  final String id;
  final String name;

  /// `INCOME` or `EXPENSE`. The API refuses a category whose kind does not
  /// match the transaction, so pickers must filter on this.
  final String kind;
  final String? icon;
  final String? color;
  final bool archived;

  factory TxCategory.fromJson(Map<String, dynamic> json) => TxCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: json['kind'] as String,
        icon: json['icon'] as String?,
        color: json['color'] as String?,
        archived: json['archived'] as bool? ?? false,
      );
}

class Budget {
  const Budget({
    required this.id,
    required this.name,
    required this.kind,
    required this.currency,
    this.plannedAmount,
    this.fundedAmount,
    this.spentAmount,
    this.potBalance,
    this.pctSpentOfFunded = 0,
    this.isUnplanned = false,
    this.started = true,
    this.icon,
    this.color,
    this.state = 'ACTIVE',
    this.health = 'ok',
    this.fillable,
    this.carriedIn,
    this.recurrenceLabel,
    this.cycleLabel,
    this.startsAt,
    this.note,
    this.categoryName,
  });

  final String id;
  final String name;

  /// `ONE_TIME`, `RECURRING`, or the single built-in `UNPLANNED` catch-all.
  final String kind;
  final String currency;
  final String? plannedAmount;

  /// Filled into the pot this cycle, carried-over money included.
  final String? fundedAmount;
  final String? spentAmount;

  /// What is left in the pot to spend right now - the API calls this `balance`.
  final String? potBalance;

  /// Server-computed, and already clamped to 100 there.
  final int pctSpentOfFunded;

  /// The Unplanned catch-all holds no pot; it labels spending rather than
  /// reserving for it, so pot figures are meaningless for it.
  final bool isUnplanned;

  /// A plan is not spendable before its start date.
  final bool started;

  final String? icon;
  final String? color;
  final String state;
  final String health;
  final String? fillable;
  final String? carriedIn;
  final String? recurrenceLabel;
  final String? cycleLabel;
  final DateTime? startsAt;
  final String? note;
  final String? categoryName;

  double get progress => (pctSpentOfFunded / 100).clamp(0, 1).toDouble();

  factory Budget.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as Map<String, dynamic>?;
    return Budget(
      id: json['id'] as String,
      name: json['name'] as String,
      kind: json['kind'] as String? ?? 'ONE_TIME',
      currency: json['currency'] as String? ?? 'ETB',
      plannedAmount: json['plannedAmount']?.toString(),
      fundedAmount: json['fundedAmount']?.toString(),
      spentAmount: json['spentAmount']?.toString(),
      potBalance: json['balance']?.toString(),
      pctSpentOfFunded: (json['pctSpentOfFunded'] as num?)?.round() ?? 0,
      isUnplanned: json['isUnplanned'] as bool? ?? json['kind'] == 'UNPLANNED',
      started: json['started'] as bool? ?? true,
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      state: json['state'] as String? ?? 'ACTIVE',
      health: json['health'] as String? ?? 'ok',
      fillable: json['fillable']?.toString(),
      carriedIn: json['carriedIn']?.toString(),
      recurrenceLabel: json['recurrenceLabel'] as String?,
      cycleLabel: json['cycleLabel'] as String?,
      startsAt: Dates.tryParse(json['startsAt']),
      note: json['note'] as String?,
      categoryName: category?['name'] as String?,
    );
  }
}

class BudgetSourceHold {
  const BudgetSourceHold({required this.accountId, required this.accountName, required this.available});
  final String accountId;
  final String accountName;
  final String available;

  factory BudgetSourceHold.fromJson(Map<String, dynamic> json) {
    final account = json['account'] as Map<String, dynamic>?;
    return BudgetSourceHold(
      accountId: account?['id'] as String? ?? '',
      accountName: account?['name'] as String? ?? 'Account',
      available: json['available']?.toString() ?? '0',
    );
  }
}

class BudgetTimelineEntry {
  const BudgetTimelineEntry({
    required this.id,
    required this.kind,
    required this.amount,
    required this.date,
    this.note,
    this.accountName,
  });

  final String id;
  final String kind;
  final String amount;
  final DateTime? date;
  final String? note;
  final String? accountName;

  factory BudgetTimelineEntry.fromJson(Map<String, dynamic> json) {
    final account = json['account'] as Map<String, dynamic>?;
    return BudgetTimelineEntry(
      id: json['id'] as String? ?? json['allocationId']?.toString() ?? 'entry-${json.hashCode}',
      kind: json['kind'] as String? ?? json['type'] as String? ?? 'ALLOCATION',
      amount: json['amount']?.toString() ?? '0',
      date: Dates.tryParse(json['date'] ?? json['createdAt']),
      note: json['note'] as String?,
      accountName: account?['name'] as String?,
    );
  }
}

class BudgetDetail {
  const BudgetDetail({
    required this.plan,
    this.sources = const [],
    this.timeline = const [],
    this.lifetimeSpent,
    this.lifetimeTxCount = 0,
    this.lifetimeCycleCount = 0,
    this.lifetimeFirstTxAt,
  });

  final Budget plan;
  final List<BudgetSourceHold> sources;
  final List<BudgetTimelineEntry> timeline;
  final String? lifetimeSpent;
  final int lifetimeTxCount;
  final int lifetimeCycleCount;
  final DateTime? lifetimeFirstTxAt;

  factory BudgetDetail.fromJson(Map<String, dynamic> json) {
    final lifetime = json['lifetime'] as Map<String, dynamic>?;
    return BudgetDetail(
      plan: Budget.fromJson(json),
      sources: ((json['sources'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BudgetSourceHold.fromJson)
          .toList(),
      timeline: ((json['timeline'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BudgetTimelineEntry.fromJson)
          .toList(),
      lifetimeSpent: lifetime?['spent']?.toString(),
      lifetimeTxCount: (lifetime?['txCount'] as num?)?.toInt() ?? 0,
      lifetimeCycleCount: (lifetime?['cycleCount'] as num?)?.toInt() ?? 0,
      lifetimeFirstTxAt: Dates.tryParse(lifetime?['firstTxAt']),
    );
  }
}

class Transaction {
  const Transaction({
    required this.id,
    required this.kind,
    required this.amount,
    required this.currency,
    required this.date,
    this.payee,
    this.note,
    this.accountName,
    this.transferAccountName,
    this.categoryName,
    this.categoryColor,
    this.categoryIcon,
    this.budgetName,
    this.budgetColor,
    this.budgetCycle,
    this.recurringRuleId,
    this.tags = const [],
    this.pendingSync = false,
  });

  final String id;
  final String kind;
  final String amount;
  final String currency;
  final DateTime? date;
  final String? payee;
  final String? note;
  final String? accountName;
  final String? transferAccountName;
  final String? categoryName;
  final String? categoryColor;
  final String? categoryIcon;
  final String? budgetName;
  final String? budgetColor;
  final int? budgetCycle;
  final String? recurringRuleId;
  final List<String> tags;

  /// An optimistic row: saved on this phone, not yet accepted by the server.
  /// Rendered dimmed with a cloud icon so the ledger never implies a write
  /// landed when it is still sitting in the outbox.
  final bool pendingSync;

  /// True for rows the SMS pipeline created, which are tagged on the way in.
  bool get fromBankMessage => tags.contains('auto');

  bool get isTransfer => kind == 'TRANSFER';

  String get title {
    if (isTransfer) {
      return '${accountName ?? '?'} → ${transferAccountName ?? '?'}';
    }
    return payee?.trim().isNotEmpty == true
        ? payee!
        : (categoryName ?? (kind == 'INCOME' ? 'Income' : 'Expense'));
  }

  factory Transaction.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as Map<String, dynamic>?;
    final account = json['account'] as Map<String, dynamic>?;
    final transfer = json['transferAccount'] as Map<String, dynamic>?;
    final budget = json['budget'] as Map<String, dynamic>?;

    return Transaction(
      id: json['id'] as String,
      kind: json['kind'] as String,
      amount: json['amount']?.toString() ?? '0',
      currency: json['currency'] as String? ?? 'ETB',
      date: Dates.tryParse(json['date']),
      payee: json['payee'] as String?,
      note: json['note'] as String?,
      accountName: account?['name'] as String?,
      transferAccountName: transfer?['name'] as String?,
      categoryName: category?['name'] as String?,
      categoryColor: category?['color'] as String?,
      categoryIcon: category?['icon'] as String?,
      budgetName: budget?['name'] as String?,
      budgetColor: budget?['color'] as String?,
      budgetCycle: (json['budgetCycle'] as num?)?.toInt(),
      recurringRuleId: json['recurringRuleId'] as String?,
      tags: ((json['tags'] as List?) ?? const []).map((e) => '$e').toList(),
    );
  }
}
