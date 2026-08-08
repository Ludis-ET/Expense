import { describe, expect, it } from 'vitest';
import { TxKind } from '../src/core/prisma.js';
import {
  AUTO_COMMIT_MIN_CONFIDENCE,
  findBank,
  normalizeSender,
  parseMessage,
} from '../src/modules/ingest/parsers/index.js';

// The message bodies below are representative of the shapes these banks send -
// they are not transcriptions of real texts. That is the point of the preview
// endpoint: paste an actual message, see what comes out, tighten the pattern.
// What these tests pin down is the parser's behaviour, especially the traps
// that silently corrupt amounts.

describe('normalizeSender', () => {
  it('folds case, spacing and the country prefix', () => {
    expect(normalizeSender('CBE')).toBe('cbe');
    expect(normalizeSender('  Awash Bank ')).toBe('awashbank');
    expect(normalizeSender('+251CBE')).toBe('cbe');
    expect(normalizeSender('CBE-Birr')).toBe('cbebirr');
  });
});

describe('findBank', () => {
  it('matches on the sender id', () => {
    expect(findBank('CBE', 'anything')?.key).toBe('cbe');
    expect(findBank('telebirr', 'anything')?.key).toBe('telebirr');
  });

  it('falls back to body hints when the sender is an unknown shortcode', () => {
    expect(findBank('8080', 'Dashen Bank: your account was credited')?.key).toBe('dashen');
  });

  it('returns undefined when nothing identifies the bank', () => {
    expect(findBank('99123', 'Some unrelated message')).toBeUndefined();
  });
});

describe('parseMessage - direction', () => {
  it('reads a credit as income', () => {
    const r = parseMessage('CBE', 'Dear customer, your account has been credited with ETB 5,000.00.');
    expect(r?.kind).toBe(TxKind.INCOME);
    expect(r?.amount).toBe(5000);
  });

  it('reads a debit as an expense', () => {
    const r = parseMessage('CBE', 'Your account has been debited with ETB 250.75.');
    expect(r?.kind).toBe(TxKind.EXPENSE);
    expect(r?.amount).toBe(250.75);
  });

  it('prefers the most specific verb when a message contains several', () => {
    // "received" would say credit; "has been debited" is the authoritative line.
    const r = parseMessage(
      'CBE',
      'You have transferred ETB 100.00 to ABEBE KEBEDE who received it. Your account has been debited.',
    );
    expect(r?.kind).toBe(TxKind.EXPENSE);
  });
});

describe('parseMessage - the balance trap', () => {
  it('does not mistake the closing balance for the transaction amount', () => {
    const r = parseMessage(
      'CBE',
      'Your account has been debited with ETB 50.00. Your current balance is ETB 4,000.00.',
    );
    expect(r?.amount).toBe(50);
    expect(r?.balance).toBe(4000);
  });

  it('handles the balance appearing before the amount', () => {
    const r = parseMessage(
      'AwashBank',
      'Available balance ETB 12,300.45 after a purchase of ETB 899.99 at SHOA SUPERMARKET.',
    );
    expect(r?.amount).toBe(899.99);
    expect(r?.balance).toBe(12300.45);
  });

  it('reads amounts written with the currency trailing', () => {
    const r = parseMessage('DashenBank', 'Dashen Bank: 1,500.00 ETB has been credited to your account.');
    expect(r?.amount).toBe(1500);
    expect(r?.kind).toBe(TxKind.INCOME);
  });
});

describe('parseMessage - references', () => {
  it('pulls the receipt id out of a CBE lookup link', () => {
    const r = parseMessage(
      'CBE',
      'You have transferred ETB 300.00. Ref: https://apps.cbe.com.et:100/?id=FT25123ABCD9',
    );
    expect(r?.ref).toBe('FT25123ABCD9');
  });

  it('reads a labelled reference number', () => {
    const r = parseMessage('AwashBank', 'ETB 75.00 debited. Reference No: TRX99881122');
    expect(r?.ref).toBe('TRX99881122');
  });
});

describe('parseMessage - rejections', () => {
  it('ignores OTP messages', () => {
    expect(parseMessage('CBE', 'Your OTP is 123456. Do not share this code with anyone.')).toBeNull();
  });

  it('ignores promotional blasts', () => {
    expect(
      parseMessage('CBE', 'Congratulations! Get a 20% discount on ETB 1,000 of airtime bundle.'),
    ).toBeNull();
  });

  it('returns null when no amount is present', () => {
    expect(parseMessage('CBE', 'Your account has been credited. Thank you for banking with us.')).toBeNull();
  });

  it('returns null when direction is unknowable', () => {
    expect(parseMessage('CBE', 'Transaction of ETB 40.00 processed.')).toBeNull();
  });
});

describe('parseMessage - confidence', () => {
  it('scores a fully-read message high enough to auto-commit', () => {
    const r = parseMessage(
      'CBE',
      'Your account has been debited with ETB 250.00 at SHOA SUPERMARKET. Ref No: FT25ABCD1234. Current balance is ETB 9,750.00.',
    );
    expect(r!.confidence).toBeGreaterThanOrEqual(AUTO_COMMIT_MIN_CONFIDENCE);
  });

  it('holds an unrecognised sender below the auto-commit floor', () => {
    const r = parseMessage(
      '55512',
      'Your account has been debited with ETB 250.00 at SHOA SUPERMARKET. Ref No: FT25ABCD1234. Current balance is ETB 9,750.00.',
    );
    expect(r?.bankKey).toBe('generic');
    expect(r!.confidence).toBeLessThan(AUTO_COMMIT_MIN_CONFIDENCE);
  });

  it('scores a bare amount-and-direction message below the floor', () => {
    const r = parseMessage('CBE', 'ETB 60.00 has been debited.');
    expect(r!.confidence).toBeLessThan(AUTO_COMMIT_MIN_CONFIDENCE);
  });
});

describe('parseMessage - ATM withdrawals', () => {
  // Booking a withdrawal as an expense double-counts it: once at the machine,
  // again when the cash is actually spent. It is a wallet-to-wallet move.
  it('flags cash out of an ATM as a withdrawal, not spending', () => {
    const r = parseMessage('CBE', 'ETB 2,000.00 has been withdrawn from ATM BOLE BRANCH. Balance ETB 8,000.00');
    expect(r?.movement).toBe('ATM_WITHDRAWAL');
    expect(r?.amount).toBe(2000);
  });

  it('picks up the machine location when the message names one', () => {
    const r = parseMessage('AwashBank', 'Cash withdrawal of ETB 500.00 at ATM MEGENAGNA 02.');
    expect(r?.movement).toBe('ATM_WITHDRAWAL');
    expect(r?.atmLocation).toContain('MEGENAGNA');
  });

  it('never treats an incoming credit as a withdrawal', () => {
    const r = parseMessage('CBE', 'Your account has been credited with ETB 900.00 via ATM deposit.');
    expect(r?.kind).toBe(TxKind.INCOME);
    expect(r?.movement).toBe('PLAIN');
  });

  it('holds withdrawals below the auto-post floor - they need a destination wallet', () => {
    const r = parseMessage(
      'CBE',
      'ETB 2,000.00 withdrawn at ATM BOLE. Ref No: FT25ABCD1234. Current balance is ETB 8,000.00.',
    );
    expect(r!.confidence).toBeLessThan(AUTO_COMMIT_MIN_CONFIDENCE);
  });
});

describe('parseMessage - account transfers', () => {
  it('flags an outgoing transfer and reads the destination account', () => {
    const r = parseMessage('CBE', 'You have transferred ETB 1,000.00 to 1000****4821. Ref FT25XYZ99');
    expect(r?.movement).toBe('ACCOUNT_TRANSFER');
    expect(r?.counterpartyAccount).toBe('1000****4821');
  });

  it('leaves an ordinary purchase as a plain expense', () => {
    const r = parseMessage('CBE', 'Purchase of ETB 120.00 at TOTAL GAS STATION was successful.');
    expect(r?.movement).toBe('PLAIN');
  });

  it('does not flag incoming transfers - money arriving is just income', () => {
    const r = parseMessage('CBE', 'ETB 3,000.00 has been transferred to your account from ABEBE.');
    expect(r?.kind).toBe(TxKind.INCOME);
    expect(r?.movement).toBe('PLAIN');
  });
});

describe('parseMessage - payee and date', () => {
  it('picks up a merchant name', () => {
    const r = parseMessage('CBE', 'Purchase of ETB 120.00 at TOTAL GAS STATION was successful.');
    expect(r?.payee).toBe('TOTAL GAS STATION');
  });

  it('does not treat sentence furniture as a payee', () => {
    const r = parseMessage('CBE', 'ETB 120.00 has been debited from your account.');
    expect(r?.payee).toBeUndefined();
  });

  it('reads an unambiguous dd/mm/yyyy date', () => {
    const r = parseMessage('CBE', 'ETB 90.00 debited on 28/07/2026 14:05.');
    expect(r?.occurredAt?.toISOString()).toBe('2026-07-28T14:05:00.000Z');
  });
});
