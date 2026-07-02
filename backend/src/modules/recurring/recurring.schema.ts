import { z } from 'zod';
import { Frequency, TxKind } from '@prisma/client';

const money = z.coerce.number().positive().max(1_000_000_000);

export const createRecurringSchema = z.object({
  name: z.string().min(1).max(100),
  kind: z.enum([TxKind.INCOME, TxKind.EXPENSE]),
  amount: money,
  currency: z.string().length(3).toUpperCase().default('ETB'),
  accountId: z.string().min(1),
  categoryId: z.string().min(1),
  payee: z.string().max(200).optional(),
  note: z.string().max(2000).optional(),
  frequency: z.nativeEnum(Frequency),
  interval: z.coerce.number().int().min(1).max(52).default(1),
  dayOfMonth: z.coerce.number().int().min(1).max(31).optional(),
  nextRun: z.coerce.date(),
  endDate: z.coerce.date().optional(),
  autoPost: z.boolean().default(true),
});

export const updateRecurringSchema = createRecurringSchema.partial().extend({
  active: z.boolean().optional(),
});

export const recurringIdParam = z.object({ id: z.string().min(1) });

export type CreateRecurringInput = z.infer<typeof createRecurringSchema>;
export type UpdateRecurringInput = z.infer<typeof updateRecurringSchema>;
