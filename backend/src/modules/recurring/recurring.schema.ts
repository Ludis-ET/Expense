import { z } from 'zod';
import { Frequency, TxKind } from '../../core/prisma.js';

const money = z.coerce.number().positive().max(1_000_000_000);

export const createRecurringSchema = z
  .object({
    name: z.string().min(1).max(100),
    kind: z.enum([TxKind.INCOME, TxKind.EXPENSE]).default(TxKind.EXPENSE),
    amount: money,
    currency: z.string().length(3).toUpperCase().default('ETB'),
    accountId: z.string().min(1),
    categoryId: z.string().min(1).optional(),
    // Savings-plan targets (mutually exclusive). When set, the rule auto-saves
    // instead of posting a transaction, and a category is not required.
    goalId: z.string().min(1).optional(),
    wishlistItemId: z.string().min(1).optional(),
    payee: z.string().max(200).optional(),
    note: z.string().max(2000).optional(),
    frequency: z.nativeEnum(Frequency),
    interval: z.coerce.number().int().min(1).max(52).default(1),
    dayOfMonth: z.coerce.number().int().min(1).max(31).optional(),
    nextRun: z.coerce.date(),
    endDate: z.coerce.date().optional(),
    autoPost: z.boolean().default(true),
  })
  .refine((d) => !(d.goalId && d.wishlistItemId), {
    message: 'A plan can target a goal or a wishlist item, not both',
    path: ['wishlistItemId'],
  })
  .refine((d) => !!d.goalId || !!d.wishlistItemId || !!d.categoryId, {
    message: 'Pick a category, or target a goal or wishlist item',
    path: ['categoryId'],
  });

export const updateRecurringSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  kind: z.enum([TxKind.INCOME, TxKind.EXPENSE]).optional(),
  amount: money.optional(),
  currency: z.string().length(3).toUpperCase().optional(),
  accountId: z.string().min(1).optional(),
  categoryId: z.string().min(1).nullable().optional(),
  goalId: z.string().min(1).nullable().optional(),
  wishlistItemId: z.string().min(1).nullable().optional(),
  payee: z.string().max(200).nullable().optional(),
  note: z.string().max(2000).nullable().optional(),
  frequency: z.nativeEnum(Frequency).optional(),
  interval: z.coerce.number().int().min(1).max(52).optional(),
  dayOfMonth: z.coerce.number().int().min(1).max(31).nullable().optional(),
  nextRun: z.coerce.date().optional(),
  endDate: z.coerce.date().nullable().optional(),
  autoPost: z.boolean().optional(),
  active: z.boolean().optional(),
});

export const recurringIdParam = z.object({ id: z.string().min(1) });

export type CreateRecurringInput = z.infer<typeof createRecurringSchema>;
export type UpdateRecurringInput = z.infer<typeof updateRecurringSchema>;
