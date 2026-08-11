/// Decoding helpers shared by every model. The API sends money as strings to
/// avoid float drift, so everything numeric goes through [asNum] / [asStr].
library;

String asStr(dynamic v, [String fallback = '0']) {
  if (v == null) return fallback;
  if (v is String) return v;
  return '$v';
}

String? asStrOrNull(dynamic v) {
  if (v == null) return null;
  if (v is String) return v.isEmpty ? null : v;
  return '$v';
}

double asNum(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

int asInt(dynamic v, [int fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

bool asBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == 'true' || v == '1';
  return fallback;
}

DateTime? asDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  return DateTime.tryParse('$v')?.toLocal();
}

Map<String, dynamic> asMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> asList(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

List<String> asStrList(dynamic v) =>
    v is List ? v.map((e) => '$e').toList() : const [];

List<T> mapList<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
    asList(v).map(f).toList();

/// Many list endpoints return `{ items: [...] }` instead of a bare array.
List<T> mapItemsList<T>(dynamic v, T Function(Map<String, dynamic>) f) {
  if (v is Map) return mapList(v['items'], f);
  return mapList(v, f);
}

/// `TxKind`
enum TxKind {
  income,
  expense,
  transfer;

  static TxKind parse(dynamic v) => switch ('$v') {
        'INCOME' => TxKind.income,
        'TRANSFER' => TxKind.transfer,
        _ => TxKind.expense,
      };

  String get wire => switch (this) {
        TxKind.income => 'INCOME',
        TxKind.expense => 'EXPENSE',
        TxKind.transfer => 'TRANSFER',
      };

  String get label => switch (this) {
        TxKind.income => 'Income',
        TxKind.expense => 'Expense',
        TxKind.transfer => 'Transfer',
      };
}

/// `AccountType`
enum AccountType {
  cash,
  bank,
  mobileMoney,
  card,
  other;

  static AccountType parse(dynamic v) => switch ('$v') {
        'CASH' => AccountType.cash,
        'BANK' => AccountType.bank,
        'MOBILE_MONEY' => AccountType.mobileMoney,
        'CARD' => AccountType.card,
        _ => AccountType.other,
      };

  String get wire => switch (this) {
        AccountType.cash => 'CASH',
        AccountType.bank => 'BANK',
        AccountType.mobileMoney => 'MOBILE_MONEY',
        AccountType.card => 'CARD',
        AccountType.other => 'OTHER',
      };

  String get label => switch (this) {
        AccountType.cash => 'Cash',
        AccountType.bank => 'Bank',
        AccountType.mobileMoney => 'Mobile money',
        AccountType.card => 'Card',
        AccountType.other => 'Other',
      };
}

/// `Frequency`
enum Frequency {
  daily,
  weekly,
  monthly,
  yearly;

  static Frequency parse(dynamic v) => switch ('$v') {
        'DAILY' => Frequency.daily,
        'WEEKLY' => Frequency.weekly,
        'YEARLY' => Frequency.yearly,
        _ => Frequency.monthly,
      };

  String get wire => name.toUpperCase();

  String get label => switch (this) {
        Frequency.daily => 'Daily',
        Frequency.weekly => 'Weekly',
        Frequency.monthly => 'Monthly',
        Frequency.yearly => 'Yearly',
      };
}

/// `RecurrenceUnit` — the step a budget cycle advances by.
enum RecurrenceUnit {
  hour,
  day,
  week,
  month,
  quarter,
  year;

  static RecurrenceUnit? parse(dynamic v) => switch ('$v') {
        'HOUR' => RecurrenceUnit.hour,
        'DAY' => RecurrenceUnit.day,
        'WEEK' => RecurrenceUnit.week,
        'MONTH' => RecurrenceUnit.month,
        'QUARTER' => RecurrenceUnit.quarter,
        'YEAR' => RecurrenceUnit.year,
        _ => null,
      };

  String get wire => name.toUpperCase();
  String get label => switch (this) {
        RecurrenceUnit.hour => 'Hour',
        RecurrenceUnit.day => 'Day',
        RecurrenceUnit.week => 'Week',
        RecurrenceUnit.month => 'Month',
        RecurrenceUnit.quarter => 'Quarter',
        RecurrenceUnit.year => 'Year',
      };
}

/// `LedgerKind`
enum LedgerKind {
  lent,
  borrowed,
  expectedIn,
  expectedOut;

  static LedgerKind parse(dynamic v) => switch ('$v') {
        'LENT' => LedgerKind.lent,
        'BORROWED' => LedgerKind.borrowed,
        'EXPECTED_IN' => LedgerKind.expectedIn,
        _ => LedgerKind.expectedOut,
      };

  String get wire => switch (this) {
        LedgerKind.lent => 'LENT',
        LedgerKind.borrowed => 'BORROWED',
        LedgerKind.expectedIn => 'EXPECTED_IN',
        LedgerKind.expectedOut => 'EXPECTED_OUT',
      };

  String get label => switch (this) {
        LedgerKind.lent => 'I lent',
        LedgerKind.borrowed => 'I borrowed',
        LedgerKind.expectedIn => 'Money coming in',
        LedgerKind.expectedOut => 'Money going out',
      };

  /// True when settling the entry brings money toward the user.
  bool get inbound => this == LedgerKind.lent || this == LedgerKind.expectedIn;
}

/// `WishlistStatus`
enum WishlistStatus {
  wanting,
  planned,
  bought,
  dropped;

  static WishlistStatus parse(dynamic v) => switch ('$v') {
        'PLANNED' => WishlistStatus.planned,
        'BOUGHT' => WishlistStatus.bought,
        'DROPPED' => WishlistStatus.dropped,
        _ => WishlistStatus.wanting,
      };

  String get wire => name.toUpperCase();
  String get label => switch (this) {
        WishlistStatus.wanting => 'Wanting',
        WishlistStatus.planned => 'Planned',
        WishlistStatus.bought => 'Bought',
        WishlistStatus.dropped => 'Dropped',
      };
}

/// `BudgetKind`
enum BudgetKind {
  oneTime,
  recurring,
  unplanned;

  static BudgetKind parse(dynamic v) => switch ('$v') {
        'RECURRING' => BudgetKind.recurring,
        'UNPLANNED' => BudgetKind.unplanned,
        _ => BudgetKind.oneTime,
      };

  String get wire => switch (this) {
        BudgetKind.oneTime => 'ONE_TIME',
        BudgetKind.recurring => 'RECURRING',
        BudgetKind.unplanned => 'UNPLANNED',
      };

  String get label => switch (this) {
        BudgetKind.oneTime => 'One-time',
        BudgetKind.recurring => 'Recurring',
        BudgetKind.unplanned => 'Unplanned',
      };
}
