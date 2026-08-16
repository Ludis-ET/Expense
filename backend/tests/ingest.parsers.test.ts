import { describe, expect, it } from 'vitest';
import { TxKind } from '../src/core/prisma.js';
import {
  AUTO_COMMIT_MIN_CONFIDENCE,
  findBank,
  normalizeSender,
  parseMessage,
} from '../src/modules/ingest/parsers/index.js';

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

  it('does not label telebirr as CBE just because CBE is the destination', () => {
    const body =
      'You have transferred ETB 130.00 successfully from your telebirr account to Commercial Bank of Ethiopia account number 1000618180647. Thank you for using telebirr Ethio telecom';
    expect(findBank('8080', body)?.key).toBe('telebirr');
  });

  it('recognises real CBE receipts', () => {
    const body =
      'Dear Leulseged Melaku Damota You have received ETB 50.00 from account 1**2704 (Natnael Tesfaye Ahmed) to your account 1**0439. Thanks for Banking with CBE. https://mbreciept.cbe.com.et/v2-hfHCxG7CZqzgKrwUDVEU';
    expect(findBank('127', body)?.key).toBe('cbe');
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

describe('parseMessage - telebirr corpus', () => {
  const transferToCbe =
    'Dear Leulseged You have transferred ETB 130.00 successfully from your telebirr account 251991173792 to Commercial Bank of Ethiopia account number 1000618180647 on 15/08/2026 20:06:37. Your telebirr transaction number is DHF8TENY9Y and your bank transaction number is FT26228W3N08. The service fee is ETB 2.61 and 15% VAT on the service fee is ETB 0.39. Your current balance is ETB 3,866.16. Thank you for using telebirr Ethio telecom';

  it('keeps telebirr identity when transferring to CBE', () => {
    const r = parseMessage('telebirr', transferToCbe);
    expect(r?.bankKey).toBe('telebirr');
    expect(r?.amount).toBe(130);
    expect(r?.kind).toBe(TxKind.EXPENSE);
    expect(r?.movement).toBe('ACCOUNT_TRANSFER');
    expect(r?.payee).toMatch(/Commercial Bank/i);
    expect(r?.ref).toBe('DHF8TENY9Y');
    expect(r?.balance).toBe(3866.16);
  });

  it('treats saving deposit as an internal transfer, not income', () => {
    const r = parseMessage(
      'telebirr',
      'Dear Leulseged You have successfully deposited ETB 20000.00 to your Saving Account on 15/08/2026 19:41:30. Your telebirr transaction number is DHF0TDM2XG. Your current Saving balance is ETB 80265.61 and Your current telebirr Account balance is ETB 3,999.16. Thank you for using telebirr Ethio telecom',
    );
    expect(r?.bankKey).toBe('telebirr');
    expect(r?.amount).toBe(20000);
    expect(r?.movement).toBe('ACCOUNT_TRANSFER');
    expect(r?.kind).toBe(TxKind.EXPENSE);
    expect(r?.balance).toBe(3999.16);
  });

  it('treats saving withdraw as money into e-money', () => {
    const r = parseMessage(
      'telebirr',
      'Dear Leulseged, You have successfully Withdraw ETB 10000.00 from your saving account on 15/08/2026 19:41:05. Your transaction number is DHF4TDLISU. Your current saving balance is ETB 60265.61 and Your current e-money account balance is ETB 23,999.16. Thank you for using telebirr Ethio telecom',
    );
    expect(r?.amount).toBe(10000);
    expect(r?.kind).toBe(TxKind.INCOME);
    expect(r?.movement).toBe('ACCOUNT_TRANSFER');
    expect(r?.ref).toBe('DHF4TDLISU');
  });

  it('reads inbound bank → telebirr with the source bank as payee', () => {
    const r = parseMessage(
      'telebirr',
      'Dear Leulseged, You have received ETB 10,800.00 by transaction number DHF2T040YU on 2026-08-15 13:39:02 from Bank of Abyssinia to your telebirr Account 251991173792 - Leulseged Melaku Damota. Your current balance is ETB 14,249.08. Thank you for using telebirr Ethio telecom',
    );
    expect(r?.bankKey).toBe('telebirr');
    expect(r?.kind).toBe(TxKind.INCOME);
    expect(r?.amount).toBe(10800);
    expect(r?.payee).toMatch(/Bank of Abyssinia/i);
    expect(r?.ref).toBe('DHF2T040YU');
  });

  it('reads package / merchant payments', () => {
    const r = parseMessage(
      'telebirr',
      'Dear Leulseged You have paid ETB 100.00 for package Voice Monthly for 324 Min +162 Min night package bonus purchase made for 991173792 on 15/08/2026 07:09:37. Your transaction number is DHF2SORAS0. Your current balance is ETB 3,449.08. Thank you for using telebirr Ethio telecom',
    );
    expect(r?.kind).toBe(TxKind.EXPENSE);
    expect(r?.amount).toBe(100);
    expect(r?.payee?.toLowerCase()).toContain('package');
  });

  it('reads P2P transfers to a person', () => {
    const r = parseMessage(
      'telebirr',
      'Dear Leulseged You have transferred ETB 460.00 to MILEN TESFAYE (2519****8988) on 14/08/2026 14:18:10. Your transaction number is DHE8S24W16. The service fee is ETB 1.74 and 15% VAT on the service fee is ETB 0.26. Your current E-Money Account balance is ETB 4,219.08. Thank you for using telebirr Ethio telecom',
    );
    expect(r?.amount).toBe(460);
    expect(r?.kind).toBe(TxKind.EXPENSE);
    expect(r?.movement).toBe('PLAIN');
    expect(r?.payee).toMatch(/MILEN TESFAYE/i);
  });
});

describe('parseMessage - CBE corpus', () => {
  it('reads receive with named counterparty', () => {
    const r = parseMessage(
      'CBE',
      'Dear Leulseged Melaku Damota You have received ETB 50.00 from account 1**2704 (Natnael Tesfaye Ahmed) to your account 1**0439. Your current balance is ETB682.24. Thanks for Banking with CBE. https://mbreciept.cbe.com.et/v2-hfHCxG7CZqzgKrwUDVEU',
    );
    expect(r?.bankKey).toBe('cbe');
    expect(r?.kind).toBe(TxKind.INCOME);
    expect(r?.amount).toBe(50);
    expect(r?.payee).toMatch(/Natnael/i);
  });

  it('reads debit principal not fee lines', () => {
    const r = parseMessage(
      'CBE',
      'Dear Leulseged Melaku Damota A debit transaction of ETB 5000.0. has occurred on your account 1****0439. Service charge of ETB 10.00 and VAT(15%) of ETB1.50 and Disaster Recovery(5%) of 0.50 with total of ETB5012.00 .Your current balance is ETB2,184.68. Thanks for Banking with CBE. https://mbreciept.cbe.com.et/v2-hfHCxFSKfkfrql86uzoo',
    );
    expect(r?.kind).toBe(TxKind.EXPENSE);
    expect(r?.amount).toBe(5000);
  });

  it('ignores Amharic security advisories', () => {
    expect(
      parseMessage(
        'CBE',
        'ለውድ ደንበኛችን፡ የጥንቃቄ መልዕክት አለን። ከሞባይል ባንኪንግ አገልግሎት ጋር በተያያዘ የይለፍ ቃልዎን ለሌላ ሶስተኛ ወገን ተጋላጭ ባለማድረግ።',
      ),
    ).toBeNull();
  });
});

describe('parseMessage - Siinqee corpus', () => {
  it('reads debit and credit with Ref', () => {
    const debit = parseMessage(
      'SIINQEE',
      'Dear LEULSEGED MELAKU DAMOTA, Your account XXXXXX99970114 has been debited with ETB 13,048 Ref: A35U2TB262260014 on 14-AUG-2026 13:08:51. Available Balance is ETB 51.55. Thank you for banking with SIINQEE BANK. https://receipts.siinqeebank.com:871/generate/A35U2TB262260014',
    );
    expect(debit?.bankKey).toBe('siinqee');
    expect(debit?.kind).toBe(TxKind.EXPENSE);
    expect(debit?.amount).toBe(13048);
    expect(debit?.ref).toBe('A35U2TB262260014');
    expect(debit?.balance).toBe(51.55);

    const credit = parseMessage(
      'SIINQEE',
      'Dear LEULSEGED MELAKU DAMOTA, Your account XXXXXX99970114 has been credited with ETB 13,100 Ref: A350ay5262240001 on 12-AUG-2026 17:08:04. Available Balance is ETB 13,100.00. Thank you for banking with SIINQEE BANK.',
    );
    expect(credit?.kind).toBe(TxKind.INCOME);
    expect(credit?.amount).toBe(13100);
  });

  it('ignores PIN registration SMS', () => {
    expect(
      parseMessage(
        'SIINQEE',
        'Dear Customer, Your Initial PIN is: 6969 Dial *871# to complete registration. Change it and Keep it confidential. Thank you for choosing Siinqee Bank.',
      ),
    ).toBeNull();
  });
});

describe('parseMessage - BoA noise', () => {
  it('ignores account-open and OTP blasts', () => {
    expect(
      parseMessage(
        'BOA',
        'Welcome! We are delighted to be your selected banking partner. Your Saving FCY Account for Resident and Non-Resident ET 265121004 is successfully opened with the PRODUCTION-HEAD OFFICE Branch. Your Customer id is 10830858Join our telegram channel for latest updates https://t.me/BoAEth',
      ),
    ).toBeNull();
    expect(parseMessage('BOA', 'Your otp is : 443150')).toBeNull();
  });
});

describe('parseMessage - references', () => {
  it('pulls the receipt id out of a CBE lookup link', () => {
    const r = parseMessage(
      'CBE',
      'You have transferred ETB 300.00. Ref: https://apps.cbe.com.et:100/?id=FT25123ABCD9 Thanks for Banking with CBE.',
    );
    expect(r?.ref).toBe('FT25123ABCD9');
  });

  it('reads a labelled reference number', () => {
    const r = parseMessage('AwashBank', 'Awash Bank: ETB 75.00 debited. Reference No: TRX99881122');
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
      'Your account has been debited with ETB 250.00 at SHOA SUPERMARKET. Ref No: FT25ABCD1234. Current balance is ETB 9,750.00. Thanks for Banking with CBE.',
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
    const r = parseMessage('CBE', 'ETB 60.00 has been debited. Thanks for Banking with CBE.');
    expect(r!.confidence).toBeLessThan(AUTO_COMMIT_MIN_CONFIDENCE);
  });
});

describe('parseMessage - ATM withdrawals', () => {
  it('flags cash out of an ATM as a withdrawal, not spending', () => {
    const r = parseMessage(
      'CBE',
      'ETB 2,000.00 has been withdrawn from ATM BOLE BRANCH. Balance ETB 8,000.00 Thanks for Banking with CBE.',
    );
    expect(r?.movement).toBe('ATM_WITHDRAWAL');
    expect(r?.amount).toBe(2000);
  });

  it('picks up the machine location when the message names one', () => {
    const r = parseMessage('AwashBank', 'Awash Bank: Cash withdrawal of ETB 500.00 at ATM MEGENAGNA 02.');
    expect(r?.movement).toBe('ATM_WITHDRAWAL');
    expect(r?.atmLocation).toContain('MEGENAGNA');
  });

  it('never treats an incoming credit as a withdrawal', () => {
    const r = parseMessage(
      'CBE',
      'Your account has been credited with ETB 900.00 via ATM deposit. Thanks for Banking with CBE.',
    );
    expect(r?.kind).toBe(TxKind.INCOME);
    expect(r?.movement).toBe('PLAIN');
  });

  it('holds withdrawals below the auto-post floor - they need a destination wallet', () => {
    const r = parseMessage(
      'CBE',
      'ETB 2,000.00 withdrawn at ATM BOLE. Ref No: FT25ABCD1234. Current balance is ETB 8,000.00. Thanks for Banking with CBE.',
    );
    expect(r!.confidence).toBeLessThan(AUTO_COMMIT_MIN_CONFIDENCE);
  });
});

describe('parseMessage - account transfers', () => {
  it('flags an outgoing transfer and reads the destination account', () => {
    const r = parseMessage(
      'CBE',
      'You have transferred ETB 1,000.00 to 1000****4821. Ref FT25XYZ99 Thanks for Banking with CBE.',
    );
    expect(r?.movement).toBe('ACCOUNT_TRANSFER');
    expect(r?.counterpartyAccount).toBe('1000****4821');
  });

  it('leaves an ordinary purchase as a plain expense', () => {
    const r = parseMessage(
      'CBE',
      'Purchase of ETB 120.00 at TOTAL GAS STATION was successful. Thanks for Banking with CBE.',
    );
    expect(r?.movement).toBe('PLAIN');
  });

  it('does not flag incoming transfers - money arriving is just income', () => {
    const r = parseMessage(
      'CBE',
      'ETB 3,000.00 has been transferred to your account from ABEBE. Thanks for Banking with CBE.',
    );
    expect(r?.kind).toBe(TxKind.INCOME);
    expect(r?.movement).toBe('PLAIN');
  });
});

describe('parseMessage - payee and date', () => {
  it('picks up a merchant name', () => {
    const r = parseMessage(
      'CBE',
      'Purchase of ETB 120.00 at TOTAL GAS STATION was successful. Thanks for Banking with CBE.',
    );
    expect(r?.payee).toBe('TOTAL GAS STATION');
  });

  it('does not treat sentence furniture as a payee', () => {
    const r = parseMessage(
      'CBE',
      'ETB 120.00 has been debited from your account. Thanks for Banking with CBE.',
    );
    expect(r?.payee).toBeUndefined();
  });

  it('reads an unambiguous dd/mm/yyyy date', () => {
    const r = parseMessage(
      'CBE',
      'ETB 90.00 debited on 28/07/2026 14:05. Thanks for Banking with CBE.',
    );
    expect(r?.occurredAt?.toISOString()).toBe('2026-07-28T14:05:00.000Z');
  });
});
