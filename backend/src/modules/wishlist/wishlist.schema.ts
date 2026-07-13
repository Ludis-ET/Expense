import { z } from 'zod';
import { WishlistStatus } from '../../core/prisma.js';

const money = z.coerce.number().min(0).max(1_000_000_000);
const currency = z.string().length(3).toUpperCase();

export const createWishlistSchema = z.object({
  name: z.string().min(1).max(120),
  estimatedCost: money.refine((n) => n > 0, 'Cost must be positive'),
  currency: currency.default('ETB'),
  priority: z.coerce.number().int().min(1).max(5).default(3),
  note: z.string().max(2000).optional(),
  link: z.string().url().max(500).optional().or(z.literal('')),
  emoji: z.string().max(8).optional(),
  goalId: z.string().min(1).optional(),
  status: z.nativeEnum(WishlistStatus).optional(),
  savedAmount: money.optional(),
});

export const updateWishlistSchema = createWishlistSchema.partial();

export const listWishlistQuery = z.object({
  currency: currency.optional(),
  status: z.nativeEnum(WishlistStatus).optional(),
});

export const fundWishlistSchema = z.object({
  amount: money.refine((n) => n > 0, 'Amount must be positive'),
});

export const promoteWishlistSchema = z.object({
  deadline: z.coerce.date().optional(),
  createLock: z.boolean().default(false),
});

export const purchaseWishlistSchema = z.object({
  accountId: z.string().min(1),
  categoryId: z.string().min(1),
  amount: money.optional(), // defaults to estimatedCost
  date: z.coerce.date().optional(),
  note: z.string().max(2000).optional(),
});

export const wishlistIdParam = z.object({ id: z.string().min(1) });

export type CreateWishlistInput = z.infer<typeof createWishlistSchema>;
export type UpdateWishlistInput = z.infer<typeof updateWishlistSchema>;
export type ListWishlistQuery = z.infer<typeof listWishlistQuery>;
export type FundWishlistInput = z.infer<typeof fundWishlistSchema>;
export type PromoteWishlistInput = z.infer<typeof promoteWishlistSchema>;
export type PurchaseWishlistInput = z.infer<typeof purchaseWishlistSchema>;
