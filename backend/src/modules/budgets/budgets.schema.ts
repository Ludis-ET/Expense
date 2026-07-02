import { z } from 'zod';

const money = z.coerce.number().positive().max(1_000_000_000);

export const upsertBudgetSchema = z.object({
  amount: money,
  alertThreshold: z.coerce.number().int().min(1).max(100).default(80),
});

export const budgetsMonthQuery = z.object({
  month: z
    .string()
    .regex(/^\d{4}-\d{2}$/, 'Expected YYYY-MM')
    .optional(),
});

export const budgetCategoryParam = z.object({ categoryId: z.string().min(1) });

export type UpsertBudgetInput = z.infer<typeof upsertBudgetSchema>;
