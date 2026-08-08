import type { BankDefinition } from './types.js';

// Catalog of Ethiopian banks and wallets.
//
// A caveat worth stating plainly: SMS sender IDs vary by carrier and change
// without notice, and the exact wording of each bank's template is not
// something to take on faith. Treat `senders` as a starting shortlist, not
// gospel. The app's sender picker reads the real originating addresses off the
// phone, and `POST /ingest/preview` replays a pasted message through this
// registry - between them you can confirm or correct any entry here in a
// minute. Anything unmatched still lands in the inbox via the generic parser.

export const BANKS: BankDefinition[] = [
  {
    key: 'cbe',
    label: 'Commercial Bank of Ethiopia',
    senders: ['cbe', 'cbeinfo', 'commercialbank', '127'],
    bodyHints: [/commercial bank of ethiopia/i, /apps\.cbe\.com\.et/i],
    patterns: {
      // CBE puts the receipt id in a lookup link; prefer it over any loose
      // alphanumeric run elsewhere in the text.
      ref: [/apps\.cbe\.com\.et[^\s]*[?&]id=([A-Za-z0-9]+)/i, /\b(FT[A-Za-z0-9]{6,})\b/],
    },
  },
  {
    key: 'cbebirr',
    label: 'CBE Birr',
    senders: ['cbebirr', 'cbe-birr'],
    bodyHints: [/cbe\s*birr/i],
  },
  {
    key: 'telebirr',
    label: 'telebirr',
    senders: ['telebirr', 'ethiotelecom', 'ethio telecom'],
    bodyHints: [/telebirr/i],
    patterns: {
      // telebirr's receipts are a distinctive uppercase/digit run.
      ref: [
        /\btransaction number\s*[:.]?\s*([A-Za-z0-9]{6,})/i,
        /\b([A-Z]{3}[A-Za-z0-9]{7,})\b/,
      ],
    },
  },
  {
    key: 'mpesa',
    label: 'M-PESA Ethiopia',
    senders: ['m-pesa', 'mpesa', 'safaricom'],
    bodyHints: [/m-?pesa/i],
    patterns: {
      ref: [/\b([A-Z0-9]{10})\b/],
    },
  },
  {
    key: 'awash',
    label: 'Awash Bank',
    senders: ['awash', 'awashbank', 'awash bank', 'awashsms'],
    bodyHints: [/awash (?:international )?bank/i],
  },
  {
    key: 'dashen',
    label: 'Dashen Bank',
    senders: ['dashen', 'dashenbank', 'dashen bank'],
    bodyHints: [/dashen bank/i],
  },
  {
    key: 'abyssinia',
    label: 'Bank of Abyssinia',
    senders: ['boa', 'abyssinia', 'bankofabyssinia', 'boainfo'],
    bodyHints: [/bank of abyssinia/i],
  },
  {
    key: 'coopbank',
    label: 'Cooperative Bank of Oromia',
    senders: ['coopbank', 'cbo', 'coop', 'coopbankoromia'],
    bodyHints: [/cooperative bank of oromia/i, /coopbank/i],
  },
  {
    key: 'wegagen',
    label: 'Wegagen Bank',
    senders: ['wegagen', 'wegagenbank'],
    bodyHints: [/wegagen bank/i],
  },
  {
    key: 'nib',
    label: 'Nib International Bank',
    senders: ['nib', 'nibbank', 'nibinternational'],
    bodyHints: [/nib international bank/i],
  },
  {
    key: 'hibret',
    label: 'Hibret Bank',
    senders: ['hibret', 'hibretbank', 'unitedbank'],
    bodyHints: [/hibret bank/i, /united bank/i],
  },
  {
    key: 'oromia',
    label: 'Oromia Bank',
    senders: ['oromiabank', 'obank', 'oromia'],
    bodyHints: [/oromia (?:international )?bank/i],
  },
  {
    key: 'amhara',
    label: 'Amhara Bank',
    senders: ['amharabank', 'amhara'],
    bodyHints: [/amhara bank/i],
  },
  {
    key: 'zemen',
    label: 'Zemen Bank',
    senders: ['zemen', 'zemenbank'],
    bodyHints: [/zemen bank/i],
  },
  {
    key: 'abay',
    label: 'Abay Bank',
    senders: ['abay', 'abaybank'],
    bodyHints: [/abay bank/i],
  },
  {
    key: 'berhan',
    label: 'Berhan Bank',
    senders: ['berhan', 'berhanbank'],
    bodyHints: [/berhan (?:international )?bank/i],
  },
  {
    key: 'bunna',
    label: 'Bunna Bank',
    senders: ['bunna', 'bunnabank'],
    bodyHints: [/bunna (?:international )?bank/i],
  },
  {
    key: 'enat',
    label: 'Enat Bank',
    senders: ['enat', 'enatbank'],
    bodyHints: [/enat bank/i],
  },
  {
    key: 'lion',
    label: 'Lion International Bank',
    senders: ['lion', 'lionbank', 'anbessa'],
    bodyHints: [/lion international bank/i, /anbessa/i],
  },
  {
    key: 'siinqee',
    label: 'Siinqee Bank',
    senders: ['siinqee', 'siinqeebank'],
    bodyHints: [/siinqee bank/i],
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

export function findBank(sender: string, body: string): BankDefinition | undefined {
  const direct = BY_SENDER.get(normalizeSender(sender));
  if (direct) return direct;

  // Shortcodes get recycled between services, so fall back to what the message
  // says about itself.
  return BANKS.find((b) => b.bodyHints?.some((re) => re.test(body)));
}

export function findBankByKey(key: string): BankDefinition | undefined {
  return BANKS.find((b) => b.key === key);
}
