import { z } from 'zod';

const money = z.coerce.number().positive().max(1_000_000_000);

export const createBudgetItemSchema = z.object({
  category: z.string().min(1).max(100),
  plannedAmount: money,
  currency: z.string().length(3).toUpperCase().default('USD'),
  exchangeRate: z.coerce.number().positive().optional(),
  notes: z.string().max(2000).optional(),
});

export const updateBudgetItemSchema = createBudgetItemSchema.partial();

export const createExpenseSchema = z.object({
  amount: money,
  currency: z.string().length(3).toUpperCase().default('USD'),
  date: z.coerce.date().optional(),
  description: z.string().max(2000).optional(),
  receiptUrl: z.string().url().optional(),
});

export const expenseDecisionSchema = z.object({
  decision: z.enum(['APPROVED', 'REJECTED']),
});

export const projectIdParam = z.object({ projectId: z.string().min(1) });
export const budgetItemIdParam = z.object({ budgetItemId: z.string().min(1) });
export const expenseIdParam = z.object({ expenseId: z.string().min(1) });

export type CreateBudgetItemInput = z.infer<typeof createBudgetItemSchema>;
export type UpdateBudgetItemInput = z.infer<typeof updateBudgetItemSchema>;
export type CreateExpenseInput = z.infer<typeof createExpenseSchema>;
