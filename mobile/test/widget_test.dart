import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/formatting.dart';
import 'package:mobile/models/finance.dart';
import 'package:mobile/models/ingest.dart';
import 'package:mobile/offline/sync_engine.dart';

// These cover the parts of the client that quietly corrupt money if they are
// wrong: decimal-string handling, and the field mapping between the API's
// balance vocabulary and ours.

void main() {
  group('Money', () {
    test('parses the decimal strings the API sends', () {
      expect(Money.parse('1234.56'), 1234.56);
      expect(Money.parse('0.00'), 0);
      expect(Money.parse(null), 0);
    });

    test('formats birr with a thousands separator', () {
      expect(Money.format('1234.56'), 'Br 1,234.56');
    });

    test('signs by transaction kind', () {
      expect(Money.signed('50.00', 'INCOME'), '+Br 50.00');
      expect(Money.signed('50.00', 'EXPENSE'), '-Br 50.00');
      expect(Money.signed('50.00', 'TRANSFER'), 'Br 50.00');
    });
  });

  group('Account.fromJson', () {
    // The API calls the post-reservation figure `balance`; getting this
    // backwards would show reserved money as spendable.
    test('maps balance to available and realBalance to the raw total', () {
      final account = Account.fromJson({
        'id': 'a1',
        'name': 'CBE',
        'type': 'BANK',
        'currency': 'ETB',
        'realBalance': '1000.00',
        'balance': '600.00',
        'lockedAmount': '400.00',
      });

      expect(account.available, '600.00');
      expect(account.realBalance, '1000.00');
      expect(account.locked, '400.00');
      expect(account.hasReservation, isTrue);
    });
  });

  group('InboxMessage', () {
    test('prefers the timestamp inside the message over arrival time', () {
      final message = InboxMessage.fromJson({
        'id': 'm1',
        'sender': 'CBE',
        'body': 'test',
        'receivedAt': '2026-08-08T10:00:00.000Z',
        'occurredAt': '2026-08-07T18:30:00.000Z',
        'status': 'PENDING',
        'confidence': 90,
      });

      expect(message.effectiveDate, DateTime.parse('2026-08-07T18:30:00.000Z').toLocal());
    });

    test('falls back to arrival time when the body carried no date', () {
      final message = InboxMessage.fromJson({
        'id': 'm2',
        'sender': 'CBE',
        'body': 'test',
        'receivedAt': '2026-08-08T10:00:00.000Z',
        'status': 'PENDING',
        'confidence': 65,
      });

      expect(message.effectiveDate, DateTime.parse('2026-08-08T10:00:00.000Z').toLocal());
    });

    test('an unparsed message still needs review', () {
      final message = InboxMessage.fromJson({
        'id': 'm3',
        'sender': '8080',
        'body': 'something odd',
        'receivedAt': '2026-08-08T10:00:00.000Z',
        'status': 'UNPARSED',
        'confidence': 0,
      });

      expect(message.isParsed, isFalse);
      expect(message.needsReview, isTrue);
    });
  });

  group('SenderRule', () {
    test('cannot auto-commit without both an account and a category', () {
      SenderRule rule(Map<String, dynamic> extra) => SenderRule.fromJson({
            'id': 'r1',
            'sender': 'CBE',
            'bankKey': 'cbe',
            'enabled': true,
            'autoCommit': true,
            ...extra,
          });

      expect(rule({'accountId': 'a1'}).canAutoCommit, isFalse);
      expect(rule({'defaultCategoryId': 'c1'}).canAutoCommit, isFalse);
      expect(rule({'accountId': 'a1', 'defaultCategoryId': 'c1'}).canAutoCommit, isTrue);
    });
  });

  group('InboxStats', () {
    test('optimistic confirm decrements the review badge', () {
      const stats = InboxStats(counts: {'PENDING': 3}, needsReview: 3);
      expect(stats.withOneFewerToReview().needsReview, 2);
      expect(const InboxStats.empty().withOneFewerToReview().needsReview, 0);
    });
  });

  group('OutboxKind', () {
    test('keeps stable string ids for replay across upgrades', () {
      expect(OutboxKind.transactionCreate, 'transaction.create');
      expect(OutboxKind.inboxConfirm, 'inbox.confirm');
      expect(OutboxKind.senderUpsert, 'sender.upsert');
    });
  });
}
