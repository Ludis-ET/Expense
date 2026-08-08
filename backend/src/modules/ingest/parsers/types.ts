import type { TxKind } from '../../../core/prisma.js';

/**
 * What kind of movement the message describes, beyond income/expense.
 *
 * These are the cases where treating the message as a plain expense would be
 * actively wrong: cash withdrawn from an ATM has not left your net worth, it
 * has moved from a bank wallet to a cash wallet, and money sent between two
 * accounts you own is not spending at all.
 */
export type MovementKind =
  | 'PLAIN' // ordinary income or expense
  | 'ATM_WITHDRAWAL' // bank -> cash wallet
  | 'ACCOUNT_TRANSFER'; // bank -> another account, possibly your own

/** What a parser managed to pull out of one bank message. */
export interface ParsedMessage {
  bankKey: string;
  kind: TxKind;
  amount: number;
  currency: string;
  /** Balance the bank reported after the movement, when it said so. */
  balance?: number;
  /** Counterparty: merchant, person, or "ATM". Best-effort. */
  payee?: string;
  /** The bank's own receipt/reference number. Our strongest dedupe key. */
  ref?: string;
  /** Timestamp read out of the message body, if it carried one. */
  occurredAt?: Date;

  /** See [MovementKind]. Drives whether the app offers a transfer instead. */
  movement: MovementKind;
  /**
   * Masked or partial account number of the other side, when the message
   * names one ("...to 1000123456789"). Matched against the account numbers
   * the user has attached to their wallets to auto-pick a transfer target.
   */
  counterpartyAccount?: string;
  /** ATM name/location, when the message says where. */
  atmLocation?: string;

  /** 0-100. See `scoreConfidence`. */
  confidence: number;
  /** Which signals fired, so a low score can be explained in the UI. */
  signals: string[];
}

/**
 * A bank's SMS dialect.
 *
 * Every field is optional except `key` and `label`: the generic extractors in
 * `extract.ts` handle the common shapes, and a bank only declares what it does
 * differently. Adding a bank should mean adding a few regexes, not a parser.
 */
export interface BankDefinition {
  key: string;
  label: string;
  /**
   * SMS originating addresses this bank sends from, lowercased. Matching is
   * done on a normalized form, so "CBE", "cbe", and "+251CBE" all land here.
   */
  senders: string[];
  /** Extra phrases that identify the bank when the sender is a bare shortcode. */
  bodyHints?: RegExp[];
  /** Overrides for the generic patterns, merged over the defaults. */
  patterns?: {
    credit?: RegExp[];
    debit?: RegExp[];
    amount?: RegExp[];
    balance?: RegExp[];
    ref?: RegExp[];
    payee?: RegExp[];
    atm?: RegExp[];
    counterpartyAccount?: RegExp[];
  };
  /** Runs after generic extraction; last chance to fix up bank quirks. */
  refine?: (parsed: ParsedMessage, body: string) => ParsedMessage;
}
