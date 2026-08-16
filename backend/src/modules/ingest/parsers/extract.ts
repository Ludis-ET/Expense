// Generic field extraction for bank SMS.
//
// Ethiopian bank messages are templated but each bank words them slightly
// differently, so rather than a rigid per-bank regex we pull each field with a
// tolerant pattern set and score how much of the message we understood. A
// message we only half-read still reaches the user's inbox - it just never
// auto-commits.

/** Currency words seen in the wild, mapped to ISO codes. */
const CURRENCY_WORDS: Array<[RegExp, string]> = [
  [/\b(?:etb|birr|br)\b/i, 'ETB'],
  [/\b(?:usd|us\s*dollars?|\$)\b/i, 'USD'],
  [/\b(?:eur|euros?|€)\b/i, 'EUR'],
  [/\b(?:gbp|pounds?|£)\b/i, 'GBP'],
];

/** Prefer comma-grouped and decimal amounts so "2,000" is not read as "2". */
const MONEY = String.raw`\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+\.\d{1,2}|\d+`;

/** "ETB 1,234.56" / "1,234.56 ETB" / "Birr1234" */
const AMOUNT_PATTERNS: RegExp[] = [
  new RegExp(String.raw`(?:etb|birr|br|usd|eur|gbp)\s*[.:]?\s*(${MONEY})`, 'i'),
  new RegExp(String.raw`(${MONEY})\s*(?:etb|birr|br|usd|eur|gbp)\b`, 'i'),
];

/**
 * Balance clauses. These run FIRST and their span is masked out of the body
 * before the amount is read - otherwise "you spent ETB 50, balance ETB 4,000"
 * happily reports a 4,000 birr coffee.
 */
const BALANCE_PATTERNS: RegExp[] = [
  new RegExp(
    String.raw`(?:current|available|new|remaining|closing|ledger)?\s*balance\s*(?:is|of|:|=)?\s*(?:etb|birr|br|usd|eur|gbp)?\s*[.:]?\s*(${MONEY})`,
    'i',
  ),
  new RegExp(
    String.raw`bal(?:\.|ance)?\s*[:=]\s*(?:etb|birr|br)?\s*(${MONEY})`,
    'i',
  ),
];

/**
 * Direction. Weighted because messages often contain several verbs - "you have
 * transferred X to Y, your account is debited" - and the most specific wins.
 */
const CREDIT_PATTERNS: Array<[RegExp, number]> = [
  [/\bhas been credited\b/i, 100],
  [/\bcredited (?:with|by|for)?\b/i, 95],
  [/\byou(?:r account)? (?:have |has )?received\b/i, 90],
  [/\bsuccessfully deposited\b/i, 92],
  [/\bsuccessfully withdraw\b/i, 90],
  [/\bdeposited (?:to|into|in)\b/i, 90],
  [/\btransferred to your\b/i, 88],
  [/\bcredit(?:ed)?\b/i, 60],
  [/\breceived\b/i, 55],
  [/\bdeposit\b/i, 55],
  [/\brefund(?:ed)?\b/i, 70],
];

const DEBIT_PATTERNS: Array<[RegExp, number]> = [
  [/\bhas been debited\b/i, 100],
  [/\bdebited (?:with|by|for)?\b/i, 95],
  [/\ba debit transaction of\b/i, 96],
  [/\byou have (?:transferred|sent|paid)\b/i, 92],
  [/\bsuccessfully deposited .+ to your saving/i, 93],
  [/\bwithdraw(?:n|al)\b/i, 90],
  [/\bpurchase(?:d)? (?:of|at|for)\b/i, 88],
  [/\btransferred from your\b/i, 88],
  [/\bpayment (?:of|to|for)\b/i, 80],
  [/\bdebit(?:ed)?\b/i, 60],
  [/\bsent to\b/i, 60],
  [/\bpaid\b/i, 55],
  [/\bspent\b/i, 55],
];

/** Bank reference / receipt numbers. */
const REF_PATTERNS: RegExp[] = [
  // CBE and several others put the receipt id in a lookup URL.
  /[?&]id=([A-Za-z0-9]{6,})/,
  /\b(?:ref(?:erence)?|txn|trx|transaction|receipt|trace|voucher)\s*(?:no\.?|number|id|#)?\s*[:.#-]?\s*([A-Za-z0-9]{5,})/i,
  /\b(FT[A-Za-z0-9]{6,})\b/,
  /\b([A-Z]{2,4}\d{8,})\b/,
];

/** "to ACME PLC", "from ABEBE KEBEDE", "at SHOA SUPERMARKET". */
const PAYEE_PATTERNS: RegExp[] = [
  /\b(?:to|from|at)\s+([A-Z][A-Za-z0-9.'&/-]*(?:\s+[A-Z0-9][A-Za-z0-9.'&/-]*){0,4})/,
];

/**
 * Cash out of a machine. Worth its own detection because it is not spending:
 * the money moved from a bank wallet to a cash wallet and is still yours.
 * Recording it as an expense double-counts it the moment the cash gets spent.
 */
const ATM_PATTERNS: RegExp[] = [
  /\batm\b/i,
  /\bcash\s*(?:withdrawal|withdrawn|out)\b/i,
  /\bwithdrawal\s+at\b/i,
  /\bcash\s*point\b/i,
];

/** "at ADDIS ATM 04", "from ATM BOLE BRANCH". */
const ATM_LOCATION_PATTERNS: RegExp[] = [
  /\batm[\s:-]+([A-Za-z0-9][A-Za-z0-9 .'/-]{2,40})/i,
  /\b(?:at|from)\s+([A-Za-z0-9 .'/-]{2,40}?\s*atm[A-Za-z0-9 .'-]{0,20})/i,
];

/**
 * The other side's account number, usually masked. Banks write these several
 * ways; all we need is enough digits to match against an account number the
 * user has attached to one of their wallets.
 */
const COUNTERPARTY_ACCOUNT_PATTERNS: RegExp[] = [
  /\b(?:to|from|into|acc(?:oun)?t)\s*(?:no\.?|number|#)?\s*[:.]?\s*((?:\d|\*|x){2,}[\d*x]{2,})/i,
  /\b((?:\*{2,}|x{2,})\d{3,})\b/i,
  /\b(\d{4,}\*{2,}\d{2,})\b/i,
];

/** Money moving to another account rather than to a merchant. */
const TRANSFER_PATTERNS: RegExp[] = [
  /\btransferr?(?:ed|s)?\b/i,
  /\bsent to\b/i,
  /\bfunds? transfer\b/i,
  /\bto (?:your |the )?(?:own |other )?account\b/i,
];

/** Words that look like a payee but are just sentence furniture. */
const PAYEE_STOPWORDS = new Set([
  'your', 'you', 'account', 'the', 'a', 'an', 'this', 'that', 'our',
  'etb', 'birr', 'br', 'usd', 'balance', 'available', 'current', 'atm', 'pos',
  'date', 'time', 'on', 'at', 'ref', 'reference', 'thank', 'thanks', 'dear',
]);

export function toNumber(raw: string): number {
  return Number(raw.replace(/,/g, ''));
}

function firstMatch(body: string, patterns: RegExp[]): RegExpMatchArray | null {
  for (const re of patterns) {
    const m = body.match(re);
    if (m) return m;
  }
  return null;
}

/** Highest-weight direction hit, or null when the message says nothing either way. */
function bestWeighted(body: string, patterns: Array<[RegExp, number]>): number {
  let best = 0;
  for (const [re, weight] of patterns) {
    if (weight > best && re.test(body)) best = weight;
  }
  return best;
}

export interface Extracted {
  amount?: number;
  currency: string;
  balance?: number;
  direction?: 'credit' | 'debit';
  payee?: string;
  ref?: string;
  occurredAt?: Date;
  movement: import('./types.js').MovementKind;
  counterpartyAccount?: string;
  atmLocation?: string;
  signals: string[];
}

export function detectCurrency(body: string): string {
  for (const [re, code] of CURRENCY_WORDS) {
    if (re.test(body)) return code;
  }
  return 'ETB';
}

/**
 * Pulls every balance clause out and blanks them so amount matching cannot
 * see closing balances (telebirr often reports saving + e-money together).
 */
function extractBalance(
  body: string,
  patterns: RegExp[],
): { balance?: number; masked: string } {
  let masked = body;
  let balance: number | undefined;
  let guard = 0;
  while (guard++ < 8) {
    const m = firstMatch(masked, patterns);
    if (!m || m.index === undefined || !m[1]) break;
    // Prefer the e-money / telebirr / available balance when several exist.
    const clause = m[0].toLowerCase();
    const prefer =
      /telebirr|e-?money|available/.test(clause) || balance === undefined;
    if (prefer) balance = toNumber(m[1]);
    masked =
      masked.slice(0, m.index) +
      ' '.repeat(m[0].length) +
      masked.slice(m.index + m[0].length);
  }
  // Also blank fee lines so "VAT … ETB 0.39" does not become the amount.
  masked = masked.replace(
    /(?:service fee|vat|disaster recovery)[^.]*?ETB\s*[\d,]+(?:\.\d+)?/gi,
    (s) => ' '.repeat(s.length),
  );
  return { balance, masked };
}

function extractPayee(body: string, patterns: RegExp[]): string | undefined {
  for (const re of patterns) {
    const m = body.match(re);
    const candidate = m?.[1]?.trim();
    if (!candidate) continue;

    // Drop trailing connectives the greedy capture swept up.
    const cleaned = candidate
      .replace(/\s+(?:on|at|with|for|ref|reference|your|the)\b.*$/i, '')
      .replace(/[.,;:]+$/, '')
      .trim();

    if (cleaned.length < 2) continue;
    if (PAYEE_STOPWORDS.has(cleaned.toLowerCase())) continue;
    // A bare number is an account fragment, not a name.
    if (/^[\d*x.-]+$/i.test(cleaned)) continue;
    return cleaned.slice(0, 200);
  }
  return undefined;
}

/**
 * Date/time out of the body. Banks here use ISO, `dd/mm/yyyy`, and
 * `14-AUG-2026` styles.
 */
function extractDate(body: string): Date | undefined {
  const iso = body.match(
    /\b(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?/,
  );
  if (iso) {
    const [, y, mo, d, h = '0', mi = '0', s = '0'] = iso;
    const dt = new Date(Date.UTC(+y!, +mo! - 1, +d!, +h, +mi, +s));
    if (!Number.isNaN(dt.getTime())) return dt;
  }

  const mon = body.match(
    /\b(\d{1,2})[-/]([A-Za-z]{3})[-/](\d{4})(?:[ ,]+(\d{1,2}):(\d{2})(?::(\d{2}))?)?/i,
  );
  if (mon) {
    const months: Record<string, number> = {
      jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5,
      jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11,
    };
    const miIdx = months[mon[2]!.slice(0, 3).toLowerCase()];
    if (miIdx !== undefined) {
      const dt = new Date(
        Date.UTC(+mon[3]!, miIdx, +mon[1]!, +(mon[4] ?? 0), +(mon[5] ?? 0), +(mon[6] ?? 0)),
      );
      if (!Number.isNaN(dt.getTime())) return dt;
    }
  }

  const dmy = body.match(
    /\b(\d{1,2})[/-](\d{1,2})[/-](\d{4})(?:[ ,]+(\d{1,2}):(\d{2})(?::(\d{2}))?)?/,
  );
  if (dmy) {
    const [, a, b, y, h = '0', mi = '0', s = '0'] = dmy;
    const day = +a! > 12 ? +a! : +b! > 12 ? +b! : +a!;
    const month = +a! > 12 ? +b! : +b! > 12 ? +a! : +b!;
    const dt = new Date(Date.UTC(+y!, month - 1, day, +h, +mi, +s));
    if (!Number.isNaN(dt.getTime())) return dt;
  }

  return undefined;
}

/** Runs every generic extractor over one message body. */
export function extractFields(
  body: string,
  overrides: NonNullable<import('./types.js').BankDefinition['patterns']> = {},
): Extracted {
  const signals: string[] = [];

  const { balance, masked } = extractBalance(body, overrides.balance ?? BALANCE_PATTERNS);
  if (balance !== undefined) signals.push('balance');

  const amountMatch = firstMatch(masked, overrides.amount ?? AMOUNT_PATTERNS);
  const amount = amountMatch?.[1] ? toNumber(amountMatch[1]) : undefined;
  if (amount !== undefined && Number.isFinite(amount) && amount > 0) signals.push('amount');

  const creditScore = bestWeighted(body, [
    ...(overrides.credit?.map((re) => [re, 100] as [RegExp, number]) ?? []),
    ...CREDIT_PATTERNS,
  ]);
  const debitScore = bestWeighted(body, [
    ...(overrides.debit?.map((re) => [re, 100] as [RegExp, number]) ?? []),
    ...DEBIT_PATTERNS,
  ]);

  let direction: 'credit' | 'debit' | undefined;
  if (creditScore > debitScore) direction = 'credit';
  else if (debitScore > creditScore) direction = 'debit';
  if (direction) signals.push(`direction:${direction}`);

  const ref = firstMatch(body, [...(overrides.ref ?? []), ...REF_PATTERNS])?.[1];
  if (ref) signals.push('ref');

  const payee = extractPayee(body, [...(overrides.payee ?? []), ...PAYEE_PATTERNS]);
  if (payee) signals.push('payee');

  const occurredAt = extractDate(body);
  if (occurredAt) signals.push('date');

  // Classify the movement. Only outflows can be an ATM withdrawal or a
  // transfer out; an incoming credit that happens to say "transfer" is just
  // money arriving, and offering to move it to cash would be nonsense.
  const isAtm = (overrides.atm ?? ATM_PATTERNS).some((re) => re.test(body));
  const isTransfer = TRANSFER_PATTERNS.some((re) => re.test(body));

  let movement: import('./types.js').MovementKind = 'PLAIN';
  if (direction === 'debit' && isAtm) movement = 'ATM_WITHDRAWAL';
  else if (direction === 'debit' && isTransfer) movement = 'ACCOUNT_TRANSFER';
  if (movement !== 'PLAIN') signals.push(`movement:${movement}`);

  const counterpartyAccount = firstMatch(
    body,
    overrides.counterpartyAccount ?? COUNTERPARTY_ACCOUNT_PATTERNS,
  )?.[1];
  if (counterpartyAccount) signals.push('counterparty-account');

  const atmLocation = isAtm ? firstMatch(body, ATM_LOCATION_PATTERNS)?.[1]?.trim() : undefined;

  return {
    amount: amount !== undefined && Number.isFinite(amount) && amount > 0 ? amount : undefined,
    currency: detectCurrency(body),
    balance,
    direction,
    payee,
    ref,
    occurredAt,
    movement,
    counterpartyAccount,
    atmLocation,
    signals,
  };
}

/**
 * How much of the message we actually understood.
 *
 * Amount and direction are the two fields a transaction cannot exist without,
 * so they carry most of the weight; the rest are corroboration. A message
 * missing either scores 0 and is filed UNPARSED rather than guessed at.
 */
export function scoreConfidence(e: Extracted): number {
  if (e.amount === undefined || !e.direction) return 0;

  let score = 65;
  if (e.ref) score += 15;
  if (e.balance !== undefined) score += 10;
  if (e.payee) score += 10;
  return Math.min(score, 100);
}
