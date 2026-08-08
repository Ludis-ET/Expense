import { TxKind } from '../../../core/prisma.js';
import { BANKS, findBank, findBankByKey, normalizeSender } from './banks.js';
import { extractFields, scoreConfidence } from './extract.js';
import type { ParsedMessage } from './types.js';

export { BANKS, findBank, findBankByKey, normalizeSender };
export type { ParsedMessage } from './types.js';
export type { BankDefinition } from './types.js';

/**
 * Below this, a message always waits for a human even when its sender rule says
 * auto-commit. 80 means amount + direction + at least one corroborating field:
 * enough that we are reading a real transaction line and not a promo blast.
 */
export const AUTO_COMMIT_MIN_CONFIDENCE = 80;

/** Marketing, OTPs, and balance-enquiry replies that are not transactions. */
const NON_TRANSACTION_PATTERNS: RegExp[] = [
  /\b(?:otp|one[- ]time password|verification code|passcode)\b/i,
  /\bdo not share\b.*\b(?:code|pin)\b/i,
  /\b(?:dear customer,?\s*)?(?:your )?(?:account )?balance (?:enquiry|inquiry)\b/i,
  /\b(?:congratulations|win|offer|promo(?:tion)?|discount|dear valued)\b/i,
  /\bairtime\b.*\bbundle\b/i,
];

export function looksTransactional(body: string): boolean {
  return !NON_TRANSACTION_PATTERNS.some((re) => re.test(body));
}

/**
 * Parse one bank message.
 *
 * Returns null when nothing usable came out - no amount, no direction, or the
 * text is clearly not a transaction. Callers file those as UNPARSED rather than
 * dropping them, because a message we failed on today is the test case for the
 * pattern we add tomorrow.
 */
export function parseMessage(sender: string, body: string): ParsedMessage | null {
  const text = body.replace(/\s+/g, ' ').trim();
  if (!text) return null;
  if (!looksTransactional(text)) return null;

  const bank = findBank(sender, text);
  const extracted = extractFields(text, bank?.patterns ?? {});
  const confidence = scoreConfidence(extracted);

  if (confidence === 0 || extracted.amount === undefined || !extracted.direction) return null;

  // A withdrawal or an own-account transfer is never a plain expense, and
  // auto-posting it as one would quietly overstate spending. Both need a
  // destination wallet the parser cannot know, so they are held below the
  // auto-post floor and always reach a human.
  const needsDestination = extracted.movement !== 'PLAIN';

  const parsed: ParsedMessage = {
    bankKey: bank?.key ?? 'generic',
    kind: extracted.direction === 'credit' ? TxKind.INCOME : TxKind.EXPENSE,
    amount: extracted.amount,
    currency: extracted.currency,
    balance: extracted.balance,
    payee: extracted.payee,
    ref: extracted.ref,
    occurredAt: extracted.occurredAt,
    movement: extracted.movement,
    counterpartyAccount: extracted.counterpartyAccount,
    atmLocation: extracted.atmLocation,
    confidence:
      // An unrecognised sender is still worth reading, but never worth
      // auto-posting - hold it just under the floor.
      bank && !needsDestination
        ? confidence
        : Math.min(confidence, AUTO_COMMIT_MIN_CONFIDENCE - 1),
    signals: extracted.signals,
  };

  return bank?.refine ? bank.refine(parsed, text) : parsed;
}
