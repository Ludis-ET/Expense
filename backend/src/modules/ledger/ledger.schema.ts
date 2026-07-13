import { z } from 'zod';

const money = z.coerce.number().positive().max(1_000_000_000);

export const ledgerKindSchema = z.enum(['LENT', 'BORROWED', 'EXPECTED_IN', 'EXPECTED_OUT']);

export const createLedgerSchema = z.object({
  kind: ledgerKindSchema,
  counterparty: z.string().min(1).max(100),
  title: z.string().max(200).optional(),
  totalAmount: money,
  currency: z.string().length(3).toUpperCase().optional(),
  dueDate: z.coerce.date().optional(),
  note: z.string().max(2000).optional(),
  categoryId: z.string().min(1).optional(),
  /** When true, records cash leaving (LENT) or arriving (BORROWED) in the chosen account. */
  recordMovement: z.boolean().optional(),
  sourceAccountId: z.string().min(1).optional(),
});

export const updateLedgerSchema = z.object({
  counterparty: z.string().min(1).max(100).optional(),
  title: z.string().max(200).optional().nullable(),
  totalAmount: money.optional(),
  dueDate: z.coerce.date().optional().nullable(),
  note: z.string().max(2000).optional().nullable(),
  categoryId: z.string().min(1).optional().nullable(),
});

export const recordPaymentSchema = z.object({
  amount: money,
  date: z.coerce.date().optional(),
  note: z.string().max(500).optional(),
  accountId: z.string().min(1).optional(),
  categoryId: z.string().min(1).optional(),
  /** Create a matching income/expense in the ledger (default true when accountId is set). */
  recordTransaction: z.boolean().optional(),
});

export const ledgerIdParam = z.object({ id: z.string().min(1) });

export const listLedgerQuery = z.object({
  status: z.enum(['open', 'settled', 'all']).optional(),
  kind: ledgerKindSchema.optional(),
  currency: z.string().length(3).toUpperCase().optional(),
});

export type CreateLedgerInput = z.infer<typeof createLedgerSchema>;
export type UpdateLedgerInput = z.infer<typeof updateLedgerSchema>;
export type RecordPaymentInput = z.infer<typeof recordPaymentSchema>;
export type ListLedgerQuery = z.infer<typeof listLedgerQuery>;
