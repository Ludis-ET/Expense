import { z } from 'zod';
import { TxKind } from '../../core/prisma.js';

const money = z.coerce.number().positive().max(1_000_000_000);

/**
 * The client's own id for this write. A queued transaction whose reply was lost
 * on the way back gets retried by the outbox; without this, the retry books the
 * money a second time. Sending it makes the retry return the row that already
 * exists.
 */
const clientOpId = z.string().min(1).max(80).nullish();

/** Where the money comes from when a plan cannot cover a spend on its own. */
const coverSchema = z
  .discriminatedUnion('from', [
    z.object({ from: z.literal('BUDGET'), budgetId: z.string().min(1) }),
    z.object({ from: z.literal('ACCOUNT'), accountId: z.string().min(1) }),
  ])
  .nullish();

const baseTx = {
  amount: money,
  /** Must match the wallet's currency. Defaults to it when omitted. */
  currency: z.string().length(3).toUpperCase().optional(),
  date: z.coerce.date(),
  accountId: z.string().min(1),
  note: z.string().max(2000).optional(),
  payee: z.string().max(200).optional(),
  tags: z.array(z.string().min(1).max(40)).max(10).default([]),
  receiptUrl: z.string().url().optional(),
  clientOpId,
};

/** INCOME and EXPENSE need a category; TRANSFER needs a distinct destination account. */
export const createTransactionSchema = z
  .discriminatedUnion('kind', [
    z.object({
      kind: z.literal(TxKind.INCOME),
      categoryId: z.string().min(1),
      ...baseTx,
    }),
    z.object({
      kind: z.literal(TxKind.EXPENSE),
      categoryId: z.string().min(1),
      /**
       * The plan this comes out of. Omit it - or send "unplanned" - for spending
       * you never set money aside for; that is stored as no plan at all, which
       * is the single representation of it.
       */
      budgetId: z.string().min(1).nullish(),
      /**
       * Which wallet's reservation to free. Only meaningful with a plan, and only
       * worth saying when the plan holds money in more than one wallet.
       */
      budgetSourceAccountId: z.string().min(1).optional(),
      /** Where to take the shortfall from when the plan cannot cover this. */
      cover: coverSchema,
      ...baseTx,
    }),
    z.object({
      kind: z.literal(TxKind.TRANSFER),
      transferAccountId: z.string().min(1),
      /**
       * What actually arrived, in the destination's currency. Required when the
       * two wallets hold different currencies - crediting the source amount
       * across a currency boundary invents money.
       */
      transferAmount: money.optional(),
      ...baseTx,
    }),
  ])
  .refine((d) => d.kind !== TxKind.TRANSFER || d.transferAccountId !== d.accountId, {
    message: 'A transfer needs two different wallets',
    path: ['transferAccountId'],
  });

export const updateTransactionSchema = z.object({
  amount: money.optional(),
  currency: z.string().length(3).toUpperCase().optional(),
  date: z.coerce.date().optional(),
  accountId: z.string().min(1).optional(),
  transferAccountId: z.string().min(1).optional(),
  transferAmount: money.optional(),
  /** Which wallet's reservation a plan expense frees. */
  budgetSourceAccountId: z.string().min(1).optional(),
  categoryId: z.string().min(1).optional(),
  note: z.string().max(2000).nullable().optional(),
  payee: z.string().max(200).nullable().optional(),
  tags: z.array(z.string().min(1).max(40)).max(10).optional(),
  receiptUrl: z.string().url().nullable().optional(),
});

export const listTransactionsQuery = z.object({
  currency: z.string().length(3).toUpperCase().optional(),
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
  kind: z.nativeEnum(TxKind).optional(),
  categoryId: z.string().optional(),
  accountId: z.string().optional(),
  budgetId: z.string().optional(),
  budgetCycle: z.coerce.number().int().min(0).optional(),
  tag: z.string().optional(),
  q: z.string().max(200).optional(),
  min: z.coerce.number().optional(),
  max: z.coerce.number().optional(),
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(25),
  sort: z.enum(['date_desc', 'date_asc', 'amount_desc', 'amount_asc']).default('date_desc'),
});

export const transactionIdParam = z.object({ id: z.string().min(1) });

export type CreateTransactionInput = z.infer<typeof createTransactionSchema>;
export type UpdateTransactionInput = z.infer<typeof updateTransactionSchema>;
export type ListTransactionsQuery = z.infer<typeof listTransactionsQuery>;
