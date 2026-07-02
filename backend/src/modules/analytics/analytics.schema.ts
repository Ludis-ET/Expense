import { z } from 'zod';
import { CategoryKind } from '@prisma/client';

const monthStr = z.string().regex(/^\d{4}-\d{2}$/, 'Expected YYYY-MM');

export const summaryQuery = z.object({ month: monthStr.optional() });

export const seriesQuery = z.object({
  granularity: z.enum(['day', 'week', 'month']).default('day'),
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
});

export const categoriesQuery = z.object({
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
  kind: z.nativeEnum(CategoryKind).default(CategoryKind.EXPENSE),
});

export const incomeVsExpenseQuery = z.object({
  months: z.coerce.number().int().min(1).max(36).default(12),
});

export const heatmapQuery = z.object({
  year: z.coerce.number().int().min(2000).max(2100).optional(),
});

export const payeesQuery = z.object({
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
  limit: z.coerce.number().int().min(1).max(50).default(10),
});

export const unnecessaryQuery = z.object({ month: monthStr.optional() });
