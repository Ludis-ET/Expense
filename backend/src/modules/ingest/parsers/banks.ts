import type { BankDefinition, ParsedMessage } from './types.js';
import { TxKind } from '../../../core/prisma.js';

// Catalog of Ethiopian banks and wallets.
//
// SMS sender IDs vary by carrier. `senders` is a shortlist; body signatures are
// scored so a telebirr SMS that *mentions* CBE as the destination is never
// mislabelled as Commercial Bank of Ethiopia.

function cleanPayee(raw: string | undefined): string | undefined {
  if (!raw) return undefined;
  const cleaned = raw
    .replace(/\s+/g, ' ')
    .replace(/[.,;:]+$/g, '')
    .trim()
    .slice(0, 160);
  return cleaned.length >= 2 ? cleaned : undefined;
}

/** telebirr templates: transfer / receive / pay / saving ↔ e-money. */
function refineTelebirr(parsed: ParsedMessage, body: string): ParsedMessage {
  const text = body;

  const tbRef =
    text.match(/telebirr transaction number is\s*([A-Z0-9]+)/i)?.[1] ??
    text.match(/Your transaction number is\s*([A-Z0-9]+)/i)?.[1] ??
    text.match(/\b(DH[A-Z0-9]{8,})\b/)?.[1] ??
    parsed.ref;

  // Saving ↔ e-money is an internal move, not income/spend.
  if (/successfully deposited .+ to your saving/i.test(text)) {
    return {
      ...parsed,
      kind: TxKind.EXPENSE,
      movement: 'ACCOUNT_TRANSFER',
      payee: 'telebirr Saving',
      ref: tbRef,
      signals: [...parsed.signals, 'telebirr:saving-deposit'],
    };
  }
  if (/successfully withdraw .+ from your saving/i.test(text)) {
    return {
      ...parsed,
      kind: TxKind.INCOME,
      movement: 'ACCOUNT_TRANSFER',
      payee: 'telebirr Saving',
      ref: tbRef,
      signals: [...parsed.signals, 'telebirr:saving-withdraw'],
    };
  }

  // Transfer to a bank account (often CBE) — still a telebirr debit.
  const toBank = text.match(
    /transferred ETB .+ to ([A-Za-z][A-Za-z .]+?) account number\s*([\d*x]+)/i,
  );
  if (toBank) {
    return {
      ...parsed,
      kind: TxKind.EXPENSE,
      movement: 'ACCOUNT_TRANSFER',
      payee: cleanPayee(toBank[1]) ?? parsed.payee,
      counterpartyAccount: toBank[2] ?? parsed.counterpartyAccount,
      ref: tbRef,
      signals: [...parsed.signals, 'telebirr:bank-transfer'],
    };
  }

  // P2P to a person / masked phone.
  const toPerson = text.match(
    /transferred ETB [\d,.]+ to ([A-Za-z][A-Za-z .'-]{1,60}?)\s*(?:\(|on )/i,
  );
  if (/you have transferred/i.test(text) && toPerson) {
    return {
      ...parsed,
      kind: TxKind.EXPENSE,
      movement: 'PLAIN',
      payee: cleanPayee(toPerson[1]) ?? parsed.payee,
      ref: tbRef,
      signals: [...parsed.signals, 'telebirr:p2p'],
    };
  }

  // Inbound from another bank or person.
  const fromBank = text.match(
    /received\s+ETB [\d,.]+ .+ from ([A-Za-z0-9][A-Za-z0-9 .&-]{1,60}?) to your telebirr/i,
  );
  if (/you have received/i.test(text) && fromBank) {
    return {
      ...parsed,
      kind: TxKind.INCOME,
      movement: 'PLAIN',
      payee: cleanPayee(fromBank[1]) ?? parsed.payee,
      ref: tbRef,
      signals: [...parsed.signals, 'telebirr:receive'],
    };
  }

  // Merchant / package / service fee payment.
  const paid = text.match(
    /paid ETB [\d,.]+ for (.+?)(?:\s+on |\s+from |\.|$)/i,
  );
  if (/you have paid/i.test(text) && paid) {
    return {
      ...parsed,
      kind: TxKind.EXPENSE,
      movement: 'PLAIN',
      payee: cleanPayee(paid[1]) ?? parsed.payee,
      ref: tbRef,
      signals: [...parsed.signals, 'telebirr:pay'],
    };
  }

  return { ...parsed, ref: tbRef ?? parsed.ref };
}

/** CBE mobile banking: receive / debit with fees / Amharic noise ignored upstream. */
function refineCbe(parsed: ParsedMessage, body: string): ParsedMessage {
  const text = body;

  const urlRef =
    text.match(/mbreciept\.cbe\.com\.et\/([A-Za-z0-9_-]+)/i)?.[1] ??
    text.match(/apps\.cbe\.com\.et[^\s]*[?&]id=([A-Za-z0-9]+)/i)?.[1] ??
    parsed.ref;

  const fromNamed = text.match(
    /from account\s+([\d*x]+)\s*\(([^)]+)\)/i,
  );
  if (/you have received/i.test(text) && fromNamed) {
    return {
      ...parsed,
      kind: TxKind.INCOME,
      movement: 'PLAIN',
      payee: cleanPayee(fromNamed[2]) ?? parsed.payee,
      counterpartyAccount: fromNamed[1] ?? parsed.counterpartyAccount,
      ref: urlRef,
      signals: [...parsed.signals, 'cbe:receive'],
    };
  }

  // Prefer the principal, not fee lines.
  const debitPrincipal = text.match(
    /debit transaction of ETB\s*([\d,]+(?:\.\d+)?)/i,
  );
  if (debitPrincipal) {
    const amount = Number(debitPrincipal[1]!.replace(/,/g, ''));
    if (Number.isFinite(amount) && amount > 0) {
      return {
        ...parsed,
        kind: TxKind.EXPENSE,
        amount,
        movement: 'PLAIN',
        ref: urlRef,
        signals: [...parsed.signals, 'cbe:debit'],
      };
    }
  }

  return { ...parsed, ref: urlRef ?? parsed.ref };
}

function refineSiinqee(parsed: ParsedMessage, body: string): ParsedMessage {
  const ref =
    body.match(/\bRef:\s*([A-Za-z0-9]+)/i)?.[1] ??
    body.match(/generate\/([A-Za-z0-9]+)/i)?.[1] ??
    parsed.ref;
  return { ...parsed, ref: ref ?? parsed.ref };
}

export const BANKS: BankDefinition[] = [
  {
    key: 'telebirr',
    label: 'telebirr',
    senders: ['telebirr', 'ethiotelecom', 'ethio telecom', 'ethiotelecom'],
    // Strong signatures — must beat destination-bank name drops.
    bodyHints: [
      { re: /\bthank you for using telebirr\b/i, weight: 100 },
      { re: /\btelebirr\b/i, weight: 90 },
      { re: /\bethio\s*telecom\b/i, weight: 80 },
      { re: /transactioninfo\.ethiotelecom\.et/i, weight: 95 },
    ],
    patterns: {
      credit: [
        /\byou have received\b/i,
        /\bsuccessfully withdraw\b/i,
      ],
      debit: [
        /\byou have transferred\b/i,
        /\byou have paid\b/i,
        /\bsuccessfully deposited .+ to your saving/i,
      ],
      ref: [
        /\btelebirr transaction number is\s*([A-Z0-9]+)/i,
        /\bYour transaction number is\s*([A-Z0-9]+)/i,
        /\b(DH[A-Z0-9]{8,})\b/,
      ],
      balance: [
        /(?:current|available)?\s*(?:telebirr|e-?money)?\s*account\s*balance\s*is\s*ETB\s*([\d,]+(?:\.\d+)?)/i,
        /(?:current|available)?\s*saving(?:s)?\s*balance\s*is\s*ETB\s*([\d,]+(?:\.\d+)?)/i,
        /(?:current|available)\s*balance\s*is\s*ETB\s*([\d,]+(?:\.\d+)?)/i,
      ],
    },
    refine: refineTelebirr,
  },
  {
    key: 'cbe',
    label: 'Commercial Bank of Ethiopia',
    senders: ['cbe', 'cbeinfo', 'commercialbank', '127'],
    // Never match bare "Commercial Bank of Ethiopia" — telebirr transfers say that.
    bodyHints: [
      { re: /\bthanks for banking with cbe\b/i, weight: 100 },
      { re: /mbreciept\.cbe\.com\.et/i, weight: 100 },
      { re: /apps\.cbe\.com\.et/i, weight: 90 },
      { re: /\bbanking with cbe\b/i, weight: 85 },
    ],
    patterns: {
      ref: [
        /mbreciept\.cbe\.com\.et\/([A-Za-z0-9_-]+)/i,
        /apps\.cbe\.com\.et[^\s]*[?&]id=([A-Za-z0-9]+)/i,
        /\b(FT[A-Za-z0-9]{6,})\b/,
      ],
      payee: [
        /\(([^)]{2,80})\)\s*to your account/i,
        /\bfrom account\s+[\d*x]+\s*\(([^)]+)\)/i,
      ],
    },
    refine: refineCbe,
  },
  {
    key: 'cbebirr',
    label: 'CBE Birr',
    senders: ['cbebirr', 'cbe-birr'],
    bodyHints: [{ re: /\bcbe\s*birr\b/i, weight: 80 }],
  },
  {
    key: 'mpesa',
    label: 'M-PESA Ethiopia',
    senders: ['m-pesa', 'mpesa', 'safaricom'],
    bodyHints: [{ re: /\bm-?pesa\b/i, weight: 80 }],
    patterns: {
      ref: [/\b([A-Z0-9]{10})\b/],
    },
  },
  {
    key: 'awash',
    label: 'Awash Bank',
    senders: ['awash', 'awashbank', 'awash bank', 'awashsms'],
    bodyHints: [{ re: /\bawash (?:international )?bank\b/i, weight: 70 }],
  },
  {
    key: 'dashen',
    label: 'Dashen Bank',
    senders: ['dashen', 'dashenbank', 'dashen bank'],
    bodyHints: [{ re: /\bdashen bank\b/i, weight: 70 }],
  },
  {
    key: 'abyssinia',
    label: 'Bank of Abyssinia',
    senders: ['boa', 'abyssinia', 'bankofabyssinia', 'boainfo'],
    // Prefer BoA-owned SMS, not telebirr "from Bank of Abyssinia".
    bodyHints: [
      { re: /\bt\.me\/BoAEth\b/i, weight: 90 },
      { re: /\byour selected banking partner\b/i, weight: 70 },
      { re: /\bbank of abyssinia\b/i, weight: 40 },
    ],
  },
  {
    key: 'coopbank',
    label: 'Cooperative Bank of Oromia',
    senders: ['coopbank', 'cbo', 'coop', 'coopbankoromia'],
    bodyHints: [
      { re: /\bcooperative bank of oromia\b/i, weight: 70 },
      { re: /\bcoopbank\b/i, weight: 60 },
    ],
  },
  {
    key: 'wegagen',
    label: 'Wegagen Bank',
    senders: ['wegagen', 'wegagenbank'],
    bodyHints: [{ re: /\bwegagen bank\b/i, weight: 70 }],
  },
  {
    key: 'nib',
    label: 'Nib International Bank',
    senders: ['nib', 'nibbank', 'nibinternational'],
    bodyHints: [{ re: /\bnib international bank\b/i, weight: 70 }],
  },
  {
    key: 'hibret',
    label: 'Hibret Bank',
    senders: ['hibret', 'hibretbank', 'unitedbank'],
    bodyHints: [
      { re: /\bhibret bank\b/i, weight: 70 },
      { re: /\bunited bank\b/i, weight: 50 },
    ],
  },
  {
    key: 'oromia',
    label: 'Oromia Bank',
    senders: ['oromiabank', 'obank', 'oromia'],
    bodyHints: [{ re: /\boromia (?:international )?bank\b/i, weight: 70 }],
  },
  {
    key: 'amhara',
    label: 'Amhara Bank',
    senders: ['amharabank', 'amhara'],
    bodyHints: [{ re: /\bamhara bank\b/i, weight: 70 }],
  },
  {
    key: 'zemen',
    label: 'Zemen Bank',
    senders: ['zemen', 'zemenbank'],
    bodyHints: [{ re: /\bzemen bank\b/i, weight: 70 }],
  },
  {
    key: 'abay',
    label: 'Abay Bank',
    senders: ['abay', 'abaybank'],
    bodyHints: [{ re: /\babay bank\b/i, weight: 70 }],
  },
  {
    key: 'berhan',
    label: 'Berhan Bank',
    senders: ['berhan', 'berhanbank'],
    bodyHints: [{ re: /\bberhan (?:international )?bank\b/i, weight: 70 }],
  },
  {
    key: 'bunna',
    label: 'Bunna Bank',
    senders: ['bunna', 'bunnabank'],
    bodyHints: [{ re: /\bbunna (?:international )?bank\b/i, weight: 70 }],
  },
  {
    key: 'enat',
    label: 'Enat Bank',
    senders: ['enat', 'enatbank'],
    bodyHints: [{ re: /\benat bank\b/i, weight: 70 }],
  },
  {
    key: 'lion',
    label: 'Lion International Bank',
    senders: ['lion', 'lionbank', 'anbessa'],
    bodyHints: [
      { re: /\blion international bank\b/i, weight: 70 },
      { re: /\banbessa\b/i, weight: 50 },
    ],
  },
  {
    key: 'siinqee',
    label: 'Siinqee Bank',
    senders: ['siinqee', 'siinqeebank', '871'],
    bodyHints: [
      { re: /\bsiinqee bank\b/i, weight: 90 },
      { re: /receipts\.siinqeebank\.com/i, weight: 100 },
      { re: /\bthank you for banking with siinqee\b/i, weight: 95 },
    ],
    patterns: {
      credit: [/\bhas been credited\b/i, /\bcredited with\b/i],
      debit: [/\bhas been debited\b/i, /\bdebited with\b/i],
      ref: [/\bRef:\s*([A-Za-z0-9]+)/i, /generate\/([A-Za-z0-9]+)/i],
      balance: [/Available Balance is ETB\s*([\d,]+(?:\.\d+)?)/i],
    },
    refine: refineSiinqee,
  },
];

/** Sender ids are compared in this normalized form. */
export function normalizeSender(raw: string): string {
  return raw.trim().toLowerCase().replace(/^\+?251/, '').replace(/[\s_-]+/g, '');
}

const BY_SENDER = new Map<string, BankDefinition>();
for (const bank of BANKS) {
  for (const sender of bank.senders) {
    BY_SENDER.set(normalizeSender(sender), bank);
  }
}

function hintScore(bank: BankDefinition, body: string): number {
  let best = 0;
  for (const hint of bank.bodyHints ?? []) {
    if (hint.re.test(body) && hint.weight > best) best = hint.weight;
  }
  return best;
}

export function findBank(sender: string, body: string): BankDefinition | undefined {
  const direct = BY_SENDER.get(normalizeSender(sender));
  if (direct) return direct;

  let best: { bank: BankDefinition; score: number } | undefined;
  for (const bank of BANKS) {
    const score = hintScore(bank, body);
    if (score <= 0) continue;
    if (!best || score > best.score) best = { bank, score };
  }
  return best?.bank;
}

export function findBankByKey(key: string): BankDefinition | undefined {
  return BANKS.find((b) => b.key === key);
}
