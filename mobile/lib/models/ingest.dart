import '../core/formatting.dart';

/// What the server thinks should happen to a message before the user touches it.
///
/// The two cases that matter are the ones a naive reading gets wrong: cash out
/// of an ATM has moved wallets rather than been spent, and money sent to an
/// account you also own is a transfer, not spending. Both would otherwise
/// inflate your spending for money that never left.
class MessageSuggestion {
  const MessageSuggestion({this.kind, this.transferAccountId, this.reason, this.needsSetup});

  /// `INCOME` | `EXPENSE` | `TRANSFER`
  final String? kind;
  final String? transferAccountId;

  /// Plain-language explanation to show above the confirm controls.
  final String? reason;

  /// `cashAccount` when the user has not yet said which wallet holds cash,
  /// which blocks recording an ATM withdrawal.
  final String? needsSetup;

  bool get isTransfer => kind == 'TRANSFER';
  bool get needsCashAccount => needsSetup == 'cashAccount';

  factory MessageSuggestion.fromJson(Map<String, dynamic> json) => MessageSuggestion(
        kind: json['kind'] as String?,
        transferAccountId: json['transferAccountId'] as String?,
        reason: json['reason'] as String?,
        needsSetup: json['needsSetup'] as String?,
      );
}

/// A captured bank message and what the server's parsers made of it.
class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.status,
    required this.confidence,
    this.bankKey,
    this.bankLabel,
    this.parsedKind,
    this.parsedAmount,
    this.parsedCurrency,
    this.parsedBalance,
    this.parsedPayee,
    this.parsedRef,
    this.occurredAt,
    this.accountId,
    this.accountName,
    this.transactionId,
    this.error,
    this.movement = 'PLAIN',
    this.counterpartyAccount,
    this.atmLocation,
    this.suggestion,
  });

  final String id;
  final String sender;
  final String body;
  final DateTime? receivedAt;

  /// `PENDING` | `CONFIRMED` | `REJECTED` | `UNPARSED` | `DUPLICATE`
  final String status;

  /// 0-100. Anything under the server's floor never auto-posts.
  final int confidence;

  final String? bankKey;
  final String? bankLabel;
  final String? parsedKind;
  final String? parsedAmount;
  final String? parsedCurrency;

  /// What the bank said the balance was afterwards. Not written anywhere -
  /// shown during review so a drifted account balance is visible.
  final String? parsedBalance;

  final String? parsedPayee;
  final String? parsedRef;

  /// Timestamp from inside the message, which can differ from when the SMS
  /// actually arrived if the network delayed it.
  final DateTime? occurredAt;

  final String? accountId;
  final String? accountName;
  final String? transactionId;

  /// Why an auto-post did not happen - often the overdraw guard refusing.
  final String? error;

  /// `PLAIN` | `ATM_WITHDRAWAL` | `ACCOUNT_TRANSFER`
  final String movement;

  /// Masked account number of the other side, when the message named one.
  final String? counterpartyAccount;
  final String? atmLocation;

  /// The server's read on what this should become. See [MessageSuggestion].
  final MessageSuggestion? suggestion;

  bool get isAtmWithdrawal => movement == 'ATM_WITHDRAWAL';
  bool get isAccountTransfer => movement == 'ACCOUNT_TRANSFER';

  /// True when the app should offer a transfer instead of income/expense.
  bool get suggestsTransfer => suggestion?.isTransfer ?? false;

  bool get needsReview => status == 'PENDING' || status == 'UNPARSED';
  bool get isParsed => parsedAmount != null && parsedKind != null;

  /// When the transaction should be dated: what the bank said, else arrival.
  DateTime get effectiveDate => occurredAt ?? receivedAt ?? DateTime.now();

  String get displayTitle =>
      parsedPayee?.trim().isNotEmpty == true ? parsedPayee! : (bankLabel ?? sender);

  factory InboxMessage.fromJson(Map<String, dynamic> json) {
    final account = json['account'] as Map<String, dynamic>?;
    return InboxMessage(
      id: json['id'] as String,
      sender: json['sender'] as String? ?? '',
      body: json['body'] as String? ?? '',
      receivedAt: Dates.tryParse(json['receivedAt']),
      status: json['status'] as String? ?? 'PENDING',
      confidence: (json['confidence'] as num?)?.round() ?? 0,
      bankKey: json['bankKey'] as String?,
      bankLabel: json['bankLabel'] as String?,
      parsedKind: json['parsedKind'] as String?,
      parsedAmount: json['parsedAmount']?.toString(),
      parsedCurrency: json['parsedCurrency'] as String?,
      parsedBalance: json['parsedBalance']?.toString(),
      parsedPayee: json['parsedPayee'] as String?,
      parsedRef: json['parsedRef'] as String?,
      occurredAt: Dates.tryParse(json['occurredAt']),
      accountId: account?['id'] as String? ?? json['accountId'] as String?,
      accountName: account?['name'] as String?,
      transactionId: (json['transaction'] as Map<String, dynamic>?)?['id'] as String?,
      error: json['error'] as String?,
      movement: json['movement'] as String? ?? 'PLAIN',
      counterpartyAccount: json['counterpartyAccount'] as String?,
      atmLocation: json['atmLocation'] as String?,
      suggestion: json['suggestion'] is Map<String, dynamic>
          ? MessageSuggestion.fromJson(json['suggestion'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// How many messages sit in each state, for the inbox badge.
class InboxStats {
  const InboxStats({required this.counts, required this.needsReview});

  final Map<String, int> counts;
  final int needsReview;

  const InboxStats.empty() : counts = const {}, needsReview = 0;

  int operator [](String status) => counts[status] ?? 0;

  /// Optimistic badge update after confirming or dismissing one message.
  InboxStats withOneFewerToReview() => InboxStats(
        counts: counts,
        needsReview: needsReview > 0 ? needsReview - 1 : 0,
      );

  factory InboxStats.fromJson(Map<String, dynamic> json) => InboxStats(
        counts: ((json['counts'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', (v as num?)?.toInt() ?? 0)),
        needsReview: (json['needsReview'] as num?)?.toInt() ?? 0,
      );
}

/// A sender the user has approved, plus what to do with its messages.
class SenderRule {
  const SenderRule({
    required this.id,
    required this.sender,
    required this.bankKey,
    required this.bankLabel,
    required this.enabled,
    required this.autoCommit,
    this.accountId,
    this.accountName,
    this.defaultCategoryId,
  });

  final String id;
  final String sender;
  final String bankKey;
  final String bankLabel;
  final bool enabled;

  /// Skip review and post straight to the ledger. Requires both an account and
  /// a default category, and a parse confident enough to clear the server floor.
  final bool autoCommit;

  final String? accountId;
  final String? accountName;
  final String? defaultCategoryId;

  bool get canAutoCommit => accountId != null && defaultCategoryId != null;

  factory SenderRule.fromJson(Map<String, dynamic> json) {
    final account = json['account'] as Map<String, dynamic>?;
    return SenderRule(
      id: json['id'] as String,
      sender: json['sender'] as String,
      bankKey: json['bankKey'] as String? ?? 'generic',
      bankLabel: json['bankLabel'] as String? ?? json['bankKey'] as String? ?? 'Unknown',
      enabled: json['enabled'] as bool? ?? true,
      autoCommit: json['autoCommit'] as bool? ?? false,
      accountId: json['accountId'] as String?,
      accountName: account?['name'] as String?,
      defaultCategoryId: json['defaultCategoryId'] as String?,
    );
  }
}

/// An entry in the server's bank catalog.
class BankInfo {
  const BankInfo({required this.key, required this.label, required this.senders});

  final String key;
  final String label;
  final List<String> senders;

  factory BankInfo.fromJson(Map<String, dynamic> json) => BankInfo(
        key: json['key'] as String,
        label: json['label'] as String,
        senders: ((json['senders'] as List?) ?? const []).map((e) => '$e').toList(),
      );
}

/// A phone paired to this account.
class PairedDevice {
  const PairedDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.messageCount,
    required this.revoked,
    this.lastSeenAt,
    this.lastIngestAt,
  });

  final String id;
  final String name;
  final String platform;
  final int messageCount;
  final bool revoked;
  final DateTime? lastSeenAt;
  final DateTime? lastIngestAt;

  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Phone',
        platform: json['platform'] as String? ?? 'android',
        messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
        revoked: json['revoked'] as bool? ?? false,
        lastSeenAt: Dates.tryParse(json['lastSeenAt']),
        lastIngestAt: Dates.tryParse(json['lastIngestAt']),
      );
}

/// Result of running a message through the parsers without saving it.
class ParsePreview {
  const ParsePreview({
    required this.matched,
    required this.autoCommitEligible,
    required this.autoCommitFloor,
    this.bankLabel,
    this.kind,
    this.amount,
    this.currency,
    this.balance,
    this.payee,
    this.ref,
    this.confidence = 0,
    this.signals = const [],
  });

  final bool matched;
  final bool autoCommitEligible;
  final int autoCommitFloor;
  final String? bankLabel;
  final String? kind;
  final double? amount;
  final String? currency;
  final double? balance;
  final String? payee;
  final String? ref;
  final int confidence;

  /// Which fields the parser actually found - the explanation for a low score.
  final List<String> signals;

  factory ParsePreview.fromJson(Map<String, dynamic> json) {
    final p = json['parsed'] as Map<String, dynamic>?;
    return ParsePreview(
      matched: json['matched'] as bool? ?? false,
      autoCommitEligible: json['autoCommitEligible'] as bool? ?? false,
      autoCommitFloor: (json['autoCommitFloor'] as num?)?.toInt() ?? 80,
      bankLabel: p?['bankLabel'] as String?,
      kind: p?['kind'] as String?,
      amount: (p?['amount'] as num?)?.toDouble(),
      currency: p?['currency'] as String?,
      balance: (p?['balance'] as num?)?.toDouble(),
      payee: p?['payee'] as String?,
      ref: p?['ref'] as String?,
      confidence: (p?['confidence'] as num?)?.toInt() ?? 0,
      signals: ((p?['signals'] as List?) ?? const []).map((e) => '$e').toList(),
    );
  }
}
