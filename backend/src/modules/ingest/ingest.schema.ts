import { z } from 'zod';
import { InboxStatus, MessageSource, TxKind } from '../../core/prisma.js';

/** One captured message as the phone sends it. */
const capturedMessage = z.object({
  sender: z.string().min(1).max(64),
  body: z.string().min(1).max(4000),
  receivedAt: z.coerce.date(),
  source: z.nativeEnum(MessageSource).default(MessageSource.SMS),
});

/**
 * The phone uploads in batches and retries until the server acknowledges, so
 * this endpoint has to be idempotent. It is: fingerprints collide on re-send
 * and the duplicate is reported rather than re-created.
 */
export const ingestBatchSchema = z.object({
  messages: z.array(capturedMessage).min(1).max(100),
});

export const listInboxQuery = z.object({
  status: z.nativeEnum(InboxStatus).optional(),
  /** Convenience for the app's main tab: everything still needing a decision. */
  unresolved: z.coerce.boolean().optional(),
  bankKey: z.string().max(40).optional(),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(25),
});

/**
 * Confirming can correct anything the parser got wrong; every field falls back
 * to what was parsed. Only the account is truly required, and only when no
 * sender rule has already nominated one.
 */
export const confirmInboxSchema = z.object({
  accountId: z.string().min(1).optional(),
  categoryId: z.string().min(1).optional(),
  /**
   * Destination wallet, for `kind: TRANSFER`. Left off for an ATM withdrawal
   * the server falls back to the user's nominated cash wallet.
   */
  transferAccountId: z.string().min(1).optional(),
  budgetId: z.string().min(1).optional(),
  budgetSourceAccountId: z.string().min(1).optional(),
  kind: z.nativeEnum(TxKind).optional(),
  amount: z.coerce.number().positive().max(1_000_000_000).optional(),
  currency: z.string().length(3).toUpperCase().optional(),
  date: z.coerce.date().optional(),
  payee: z.string().max(200).optional(),
  note: z.string().max(2000).optional(),
  tags: z.array(z.string().min(1).max(40)).max(10).default([]),
  /** Remember this account/category pairing for future messages from this sender. */
  rememberMapping: z.coerce.boolean().default(false),
});

export const previewSchema = z.object({
  sender: z.string().min(1).max(64),
  body: z.string().min(1).max(4000),
});

export const upsertSenderRuleSchema = z.object({
  sender: z.string().min(1).max(64),
  bankKey: z.string().min(1).max(40),
  accountId: z.string().min(1).nullable().optional(),
  defaultCategoryId: z.string().min(1).nullable().optional(),
  enabled: z.coerce.boolean().default(true),
  autoCommit: z.coerce.boolean().default(false),
});

export const inboxIdParam = z.object({ id: z.string().min(1) });
export const senderRuleIdParam = z.object({ id: z.string().min(1) });

export type IngestBatchInput = z.infer<typeof ingestBatchSchema>;
export type ListInboxQuery = z.infer<typeof listInboxQuery>;
export type ConfirmInboxInput = z.infer<typeof confirmInboxSchema>;
export type UpsertSenderRuleInput = z.infer<typeof upsertSenderRuleSchema>;
