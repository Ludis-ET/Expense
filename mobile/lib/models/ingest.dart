import 'common.dart';

/// Lightweight account/category ref for inbox payloads (avoids circular imports).
class InboxRef {
  InboxRef({required this.id, required this.name, this.type});

  final String id;
  final String name;
  final String? type;

  factory InboxRef.fromJson(Map<String, dynamic> j) => InboxRef(
        id: asStr(j['id'], ''),
        name: asStr(j['name'], ''),
        type: asStrOrNull(j['type']),
      );

  static InboxRef? maybe(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    if (m['id'] == null) return null;
    return InboxRef.fromJson(m);
  }
}

/// One bank SMS sitting in the server review inbox.
class InboxMessage {
  InboxMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.status,
    required this.confidence,
    required this.movement,
    this.source = 'SMS',
    this.bankKey,
    this.bankLabel,
    this.parsedKind,
    this.parsedAmount,
    this.parsedCurrency,
    this.parsedBalance,
    this.parsedPayee,
    this.parsedRef,
    this.occurredAt,
    this.counterpartyAccount,
    this.atmLocation,
    this.account,
    this.suggestion,
    this.error,
    this.transactionId,
  });

  final String id;
  final String source;
  final String sender;
  final String body;
  final DateTime receivedAt;
  final String status;
  final String? bankKey;
  final String? bankLabel;
  final TxKind? parsedKind;
  final String? parsedAmount;
  final String? parsedCurrency;
  final String? parsedBalance;
  final String? parsedPayee;
  final String? parsedRef;
  final DateTime? occurredAt;
  final String movement;
  final String? counterpartyAccount;
  final String? atmLocation;
  final int confidence;
  final InboxRef? account;
  final InboxSuggestion? suggestion;
  final String? error;
  final String? transactionId;

  bool get needsReview => status == 'PENDING' || status == 'UNPARSED';

  bool get isCredit {
    final kind = suggestion?.kind ?? parsedKind;
    return kind == TxKind.income;
  }

  factory InboxMessage.fromJson(Map<String, dynamic> j) {
    final tx = j['transaction'];
    return InboxMessage(
      id: asStr(j['id'], ''),
      source: asStr(j['source'], 'SMS'),
      sender: asStr(j['sender'], ''),
      body: asStr(j['body'], ''),
      receivedAt: asDate(j['receivedAt']) ?? DateTime.now(),
      status: asStr(j['status'], 'PENDING'),
      bankKey: asStrOrNull(j['bankKey']),
      bankLabel: asStrOrNull(j['bankLabel']),
      parsedKind: j['parsedKind'] == null ? null : TxKind.parse(j['parsedKind']),
      parsedAmount: asStrOrNull(j['parsedAmount']),
      parsedCurrency: asStrOrNull(j['parsedCurrency']),
      parsedBalance: asStrOrNull(j['parsedBalance']),
      parsedPayee: asStrOrNull(j['parsedPayee']),
      parsedRef: asStrOrNull(j['parsedRef']),
      occurredAt: asDate(j['occurredAt']),
      movement: asStr(j['movement'], 'PLAIN'),
      counterpartyAccount: asStrOrNull(j['counterpartyAccount']),
      atmLocation: asStrOrNull(j['atmLocation']),
      confidence: asInt(j['confidence']),
      account: InboxRef.maybe(j['account']),
      suggestion: j['suggestion'] == null
          ? null
          : InboxSuggestion.fromJson(asMap(j['suggestion'])),
      error: asStrOrNull(j['error']),
      transactionId: tx is Map ? asStrOrNull(tx['id']) : null,
    );
  }
}

class InboxSuggestion {
  InboxSuggestion({
    this.kind,
    this.transferAccountId,
    this.reason,
    this.needsSetup,
  });

  final TxKind? kind;
  final String? transferAccountId;
  final String? reason;
  final String? needsSetup;

  factory InboxSuggestion.fromJson(Map<String, dynamic> j) => InboxSuggestion(
        kind: j['kind'] == null ? null : TxKind.parse(j['kind']),
        transferAccountId: asStrOrNull(j['transferAccountId']),
        reason: asStrOrNull(j['reason']),
        needsSetup: asStrOrNull(j['needsSetup']),
      );
}

class InboxStats {
  InboxStats({required this.needsReview, required this.counts});

  final int needsReview;
  final Map<String, int> counts;

  factory InboxStats.fromJson(Map<String, dynamic> j) {
    final raw = asMap(j['counts']);
    return InboxStats(
      needsReview: asInt(j['needsReview']),
      counts: raw.map((k, v) => MapEntry(k, asInt(v))),
    );
  }

  static InboxStats empty() => InboxStats(needsReview: 0, counts: const {});
}

class BankCatalogItem {
  BankCatalogItem({
    required this.key,
    required this.label,
    required this.senders,
  });

  final String key;
  final String label;
  final List<String> senders;

  factory BankCatalogItem.fromJson(Map<String, dynamic> j) => BankCatalogItem(
        key: asStr(j['key'], ''),
        label: asStr(j['label'], ''),
        senders: asStrList(j['senders']),
      );
}

class SenderRule {
  SenderRule({
    required this.id,
    required this.sender,
    required this.bankKey,
    required this.enabled,
    required this.autoCommit,
    this.bankLabel,
    this.accountId,
    this.defaultCategoryId,
    this.account,
  });

  final String id;
  final String sender;
  final String bankKey;
  final String? bankLabel;
  final String? accountId;
  final String? defaultCategoryId;
  final bool enabled;
  final bool autoCommit;
  final InboxRef? account;

  factory SenderRule.fromJson(Map<String, dynamic> j) => SenderRule(
        id: asStr(j['id'], ''),
        sender: asStr(j['sender'], ''),
        bankKey: asStr(j['bankKey'], ''),
        bankLabel: asStrOrNull(j['bankLabel']),
        accountId: asStrOrNull(j['accountId']),
        defaultCategoryId: asStrOrNull(j['defaultCategoryId']),
        enabled: asBool(j['enabled'], true),
        autoCommit: asBool(j['autoCommit']),
        account: InboxRef.maybe(j['account']),
      );
}

class PairedDevice {
  PairedDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.revoked,
    required this.messageCount,
    this.appVersion,
    this.lastSeenAt,
    this.lastIngestAt,
    this.createdAt,
  });

  final String id;
  final String name;
  final String platform;
  final String? appVersion;
  final DateTime? lastSeenAt;
  final DateTime? lastIngestAt;
  final int messageCount;
  final bool revoked;
  final DateTime? createdAt;

  factory PairedDevice.fromJson(Map<String, dynamic> j) => PairedDevice(
        id: asStr(j['id'], ''),
        name: asStr(j['name'], ''),
        platform: asStr(j['platform'], 'android'),
        appVersion: asStrOrNull(j['appVersion']),
        lastSeenAt: asDate(j['lastSeenAt']),
        lastIngestAt: asDate(j['lastIngestAt']),
        messageCount: asInt(j['messageCount']),
        revoked: asBool(j['revoked']),
        createdAt: asDate(j['createdAt']),
      );
}

class CapturedSms {
  CapturedSms({
    required this.sender,
    required this.body,
    required this.receivedAt,
  });

  final String sender;
  final String body;
  final DateTime receivedAt;

  Map<String, dynamic> toIngestJson() => {
        'sender': sender,
        'body': body,
        'receivedAt': receivedAt.toUtc().toIso8601String(),
        'source': 'SMS',
      };
}

/// Local fingerprint so re-imports collapse before upload.
String smsLocalFingerprint(String sender, String body, DateTime receivedAt) {
  final minute = receivedAt.millisecondsSinceEpoch ~/ 60000;
  final normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  return '$sender|$minute|$normalized'.hashCode.toRadixString(16);
}
