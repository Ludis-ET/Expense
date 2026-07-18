import { z } from 'zod';
import { BudgetPeriod } from '../../core/prisma.js';

const money = z.coerce.number().positive().max(1_000_000_000);

export const upsertBudgetSchema = z
  .object({
    amount: money,
    alertThreshold: z.coerce.number().int().min(1).max(100).default(80),
    period: z.nativeEnum(BudgetPeriod).default(BudgetPeriod.MONTHLY),
    rollover: z.boolean().default(false),
    startDate: z.coerce.date().optional(),
    endDate: z.coerce.date().optional(),
  })
  .refine((d) => !(d.startDate && d.endDate) || d.endDate >= d.startDate, {
    message: 'End date must be on or after the start date',
    path: ['endDate'],
  });

export const budgetsMonthQuery = z.object({
  // Reference month; each budget is shown for the period that contains this month.
  month: z
    .string()
    .regex(/^\d{4}-\d{2}$/, 'Expected YYYY-MM')
    .optional(),
});

export const budgetHistoryQuery = z.object({
  periods: z.coerce.number().int().min(1).max(24).default(6),
});

export const budgetCategoryParam = z.object({ categoryId: z.string().min(1) });

export type UpsertBudgetInput = z.infer<typeof upsertBudgetSchema>;
