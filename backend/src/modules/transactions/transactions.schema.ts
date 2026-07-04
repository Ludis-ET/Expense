import { z } from 'zod';
import { TxKind } from '../../core/prisma.js';

const money = z.coerce.number().positive().max(1_000_000_000);

const baseTx = {
  amount: money,
  currency: z.string().length(3).toUpperCase().default('ETB'),
  date: z.coerce.date(),
  accountId: z.string().min(1),
  note: z.string().max(2000).optional(),
  payee: z.string().max(200).optional(),
  tags: z.array(z.string().min(1).max(40)).max(10).default([]),
  receiptUrl: z.string().url().optional(),
};

/** INCOME and EXPENSE need a category; TRANSFER needs a distinct destination account. */
export const createTransactionSchema = z
  .discriminatedUnion('kind', [
    z.object({ kind: z.literal(TxKind.INCOME), categoryId: z.string().min(1), ...baseTx }),
    z.object({ kind: z.literal(TxKind.EXPENSE), categoryId: z.string().min(1), ...baseTx }),
    z.object({ kind: z.literal(TxKind.TRANSFER), transferAccountId: z.string().min(1), ...baseTx }),
  ])
  .refine((d) => d.kind !== TxKind.TRANSFER || d.transferAccountId !== d.accountId, {
    message: 'Transfer destination must be a different account',
    path: ['transferAccountId'],
  });

export const updateTransactionSchema = z.object({
  amount: money.optional(),
  currency: z.string().length(3).toUpperCase().optional(),
  date: z.coerce.date().optional(),
  accountId: z.string().min(1).optional(),
  transferAccountId: z.string().min(1).optional(),
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
