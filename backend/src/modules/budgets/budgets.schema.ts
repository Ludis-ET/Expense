import { z } from 'zod';
import { BudgetKind, BudgetPeriod, BudgetState } from '../../core/prisma.js';

const money = z.coerce.number().positive().max(1_000_000_000);

export const createBudgetSchema = z
  .object({
    name: z.string().trim().min(1, 'Give the plan a name').max(80),
    /** Optional - only pre-selects itself when you spend from the plan. */
    categoryId: z.string().min(1).nullish(),
    kind: z.nativeEnum(BudgetKind).default(BudgetKind.ONE_TIME),
    period: z.nativeEnum(BudgetPeriod).nullish(),
    plannedAmount: money,
    currency: z.string().length(3).default('ETB'),
    icon: z.string().max(40).nullish(),
    color: z.string().max(20).nullish(),
    note: z.string().max(500).nullish(),
    alertThreshold: z.coerce.number().int().min(1).max(100).default(80),
    startDate: z.coerce.date().optional(),
    endDate: z.coerce.date().nullish(),
  })
  .refine((d) => d.kind !== BudgetKind.RECURRING || !!d.period, {
    message: 'Pick how often this plan repeats',
    path: ['period'],
  })
  .refine((d) => !(d.startDate && d.endDate) || d.endDate >= d.startDate, {
    message: 'End date must be on or after the start date',
    path: ['endDate'],
  });

export const updateBudgetSchema = z.object({
  name: z.string().trim().min(1).max(80).optional(),
  categoryId: z.string().min(1).nullish(),
  kind: z.nativeEnum(BudgetKind).optional(),
  period: z.nativeEnum(BudgetPeriod).nullish(),
  plannedAmount: money.optional(),
  icon: z.string().max(40).nullish(),
  color: z.string().max(20).nullish(),
  note: z.string().max(500).nullish(),
  alertThreshold: z.coerce.number().int().min(1).max(100).optional(),
  endDate: z.coerce.date().nullish(),
});

export const fundBudgetSchema = z.object({
  accountId: z.string().min(1, 'Pick an account'),
  amount: money,
  date: z.coerce.date().optional(),
  note: z.string().max(200).nullish(),
});

export const releaseBudgetSchema = z.object({
  /** Defaults to the account with the largest share of the pot. */
  accountId: z.string().min(1).optional(),
  amount: money,
  date: z.coerce.date().optional(),
  note: z.string().max(200).nullish(),
});

export const listBudgetsQuery = z.object({
  state: z.nativeEnum(BudgetState).optional(),
  currency: z.string().length(3).optional(),
});

export const budgetSourcesQuery = z.object({
  currency: z.string().length(3).optional(),
});

export const budgetIdParam = z.object({ id: z.string().min(1) });

export type CreateBudgetInput = z.infer<typeof createBudgetSchema>;
export type UpdateBudgetInput = z.infer<typeof updateBudgetSchema>;
export type FundBudgetInput = z.infer<typeof fundBudgetSchema>;
export type ReleaseBudgetInput = z.infer<typeof releaseBudgetSchema>;
export type ListBudgetsQuery = z.infer<typeof listBudgetsQuery>;
