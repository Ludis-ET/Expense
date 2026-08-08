import '../core/formatting.dart';

class WishlistItem {
  const WishlistItem({
    required this.id,
    required this.name,
    required this.priority,
    required this.status,
    this.note,
    this.link,
    this.emoji,
    this.budgetId,
    this.planName,
    this.createdAt,
  });

  final String id;
  final String name;
  final int priority;
  final String status;
  final String? note;
  final String? link;
  final String? emoji;
  final String? budgetId;
  final String? planName;
  final DateTime? createdAt;

  factory WishlistItem.fromJson(Map<String, dynamic> json) {
    final plan = json['plan'] as Map<String, dynamic>?;
    return WishlistItem(
      id: json['id'] as String,
      name: json['name'] as String,
      priority: (json['priority'] as num?)?.toInt() ?? 3,
      status: json['status'] as String? ?? 'WANTING',
      note: json['note'] as String?,
      link: json['link'] as String?,
      emoji: json['emoji'] as String?,
      budgetId: json['budgetId'] as String?,
      planName: plan?['name'] as String?,
      createdAt: Dates.tryParse(json['createdAt']),
    );
  }
}

class WishlistStats {
  const WishlistStats({
    this.wanting = 0,
    this.planned = 0,
    this.bought = 0,
    this.dropped = 0,
    this.total = 0,
  });

  final int wanting;
  final int planned;
  final int bought;
  final int dropped;
  final int total;

  factory WishlistStats.fromJson(Map<String, dynamic>? json) => WishlistStats(
        wanting: (json?['wanting'] as num?)?.toInt() ?? 0,
        planned: (json?['planned'] as num?)?.toInt() ?? 0,
        bought: (json?['bought'] as num?)?.toInt() ?? 0,
        dropped: (json?['dropped'] as num?)?.toInt() ?? 0,
        total: (json?['total'] as num?)?.toInt() ?? 0,
      );
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.kind,
    required this.counterparty,
    required this.totalAmount,
    required this.remaining,
    required this.currency,
    required this.status,
    this.title,
    this.dueDate,
    this.note,
    this.isOverdue = false,
    this.pct = 0,
  });

  final String id;
  final String kind;
  final String counterparty;
  final String totalAmount;
  final String remaining;
  final String currency;
  final String status;
  final String? title;
  final DateTime? dueDate;
  final String? note;
  final bool isOverdue;
  final int pct;

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
        id: json['id'] as String,
        kind: json['kind'] as String,
        counterparty: json['counterparty'] as String,
        totalAmount: json['totalAmount']?.toString() ?? '0',
        remaining: json['remaining']?.toString() ?? '0',
        currency: json['currency'] as String? ?? 'ETB',
        status: json['status'] as String? ?? 'OPEN',
        title: json['title'] as String?,
        dueDate: Dates.tryParse(json['dueDate']),
        note: json['note'] as String?,
        isOverdue: json['isOverdue'] as bool? ?? false,
        pct: (json['pct'] as num?)?.round() ?? 0,
      );
}

class LedgerSummary {
  const LedgerSummary({
    this.receivable = '0',
    this.payable = '0',
    this.expectedIn = '0',
    this.expectedOut = '0',
    this.netPosition = '0',
    this.openCount = 0,
    this.overdueCount = 0,
    this.forecastNet,
    this.forecastMonth,
  });

  final String receivable;
  final String payable;
  final String expectedIn;
  final String expectedOut;
  final String netPosition;
  final int openCount;
  final int overdueCount;
  final String? forecastNet;
  final String? forecastMonth;

  factory LedgerSummary.fromJson(Map<String, dynamic> json) {
    final forecast = json['forecast'] as Map<String, dynamic>?;
    return LedgerSummary(
      receivable: json['receivable']?.toString() ?? '0',
      payable: json['payable']?.toString() ?? '0',
      expectedIn: json['expectedIn']?.toString() ?? '0',
      expectedOut: json['expectedOut']?.toString() ?? '0',
      netPosition: json['netPosition']?.toString() ?? '0',
      openCount: (json['openCount'] as num?)?.toInt() ?? 0,
      overdueCount: (json['overdueCount'] as num?)?.toInt() ?? 0,
      forecastNet: forecast?['netIfOnTime']?.toString(),
      forecastMonth: forecast?['month'] as String?,
    );
  }
}
