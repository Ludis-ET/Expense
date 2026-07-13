import { z } from 'zod';
import { SpendLockKind } from '../../core/prisma.js';

const money = z.coerce.number().positive().max(1_000_000_000);
const currency = z.string().length(3).toUpperCase();

export const createSpendLockSchema = z
  .object({
    kind: z.nativeEnum(SpendLockKind),
    name: z.string().min(1).max(100),
    amount: money,
    currency: currency.default('ETB'),
    note: z.string().max(2000).optional(),
    goalId: z.string().min(1).optional(),
    active: z.boolean().optional(),
  })
  .refine((d) => d.kind !== SpendLockKind.GOAL || !!d.goalId, {
    message: 'Goal locks need a savings goal',
    path: ['goalId'],
  });

export const updateSpendLockSchema = z.object({
  name: z.string().min(1).max(100).optional(),
  amount: money.optional(),
  note: z.string().max(2000).nullable().optional(),
  active: z.boolean().optional(),
  goalId: z.string().min(1).nullable().optional(),
});

export const listSpendLocksQuery = z.object({
  currency: currency.optional(),
  active: z.enum(['true', 'false', 'all']).optional(),
});

export const spendLockIdParam = z.object({ id: z.string().min(1) });

export type CreateSpendLockInput = z.infer<typeof createSpendLockSchema>;
export type UpdateSpendLockInput = z.infer<typeof updateSpendLockSchema>;
export type ListSpendLocksQuery = z.infer<typeof listSpendLocksQuery>;
