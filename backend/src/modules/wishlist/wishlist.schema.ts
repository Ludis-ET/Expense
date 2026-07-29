import { z } from 'zod';
import { BudgetKind, RecurrenceUnit, WishlistStatus } from '../../core/prisma.js';

const money = z.coerce.number().positive().max(1_000_000_000);

/** A want is just an idea: no cost, no savings, no currency. */
export const createWishlistSchema = z.object({
  name: z.string().trim().min(1, 'Give it a name').max(120),
  priority: z.coerce.number().int().min(1).max(5).default(3),
  note: z.string().max(2000).nullish(),
  link: z.string().url().max(500).nullish().or(z.literal('')),
  emoji: z.string().max(8).nullish(),
  status: z.nativeEnum(WishlistStatus).optional(),
});

export const updateWishlistSchema = createWishlistSchema.partial();

export const listWishlistQuery = z.object({
  status: z.nativeEnum(WishlistStatus).optional(),
  priority: z.coerce.number().int().min(1).max(5).optional(),
  q: z.string().max(200).optional(),
  sort: z
    .enum(['priority', 'newest', 'oldest', 'name'])
    .default('priority'),
});

/**
 * Turning a want into a plan. Everything a Budget needs that a want does not
 * already carry; the name and icon default to the want's own.
 */
export const planWishlistSchema = z
  .object({
    name: z.string().trim().min(1).max(80).optional(),
    plannedAmount: money,
    currency: z.string().length(3).default('ETB'),
    kind: z.enum([BudgetKind.ONE_TIME, BudgetKind.RECURRING]).default(BudgetKind.ONE_TIME),
    recurrenceUnit: z.nativeEnum(RecurrenceUnit).nullish(),
    recurrenceInterval: z.coerce.number().int().min(1).max(365).default(1),
    categoryId: z.string().min(1).nullish(),
    color: z.string().max(20).nullish(),
    alertThreshold: z.coerce.number().int().min(1).max(100).default(80),
    startsAt: z.coerce.date().optional(),
    endDate: z.coerce.date().nullish(),
  })
  .refine((d) => d.kind !== BudgetKind.RECURRING || !!d.recurrenceUnit, {
    message: 'Pick how often this plan repeats',
    path: ['recurrenceUnit'],
  })
  .refine((d) => !(d.startsAt && d.endDate) || d.endDate >= d.startsAt, {
    message: 'End date must be on or after the start date',
    path: ['endDate'],
  });

export const wishlistIdParam = z.object({ id: z.string().min(1) });

export type CreateWishlistInput = z.infer<typeof createWishlistSchema>;
export type UpdateWishlistInput = z.infer<typeof updateWishlistSchema>;
export type ListWishlistQuery = z.infer<typeof listWishlistQuery>;
export type PlanWishlistInput = z.infer<typeof planWishlistSchema>;
