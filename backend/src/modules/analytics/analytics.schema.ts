import { z } from 'zod';
import { CategoryKind } from '../../core/prisma.js';

const monthStr = z.string().regex(/^\d{4}-\d{2}$/, 'Expected YYYY-MM');
const currencyStr = z.string().length(3).toUpperCase().optional();

export const summaryQuery = z.object({ month: monthStr.optional(), currency: currencyStr });

export const seriesQuery = z.object({
  granularity: z.enum(['day', 'week', 'month']).default('day'),
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
  currency: currencyStr,
});

export const categoriesQuery = z.object({
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
  kind: z.nativeEnum(CategoryKind).default(CategoryKind.EXPENSE),
  currency: currencyStr,
});

export const incomeVsExpenseQuery = z.object({
  months: z.coerce.number().int().min(1).max(36).default(12),
  currency: currencyStr,
});

export const heatmapQuery = z.object({
  year: z.coerce.number().int().min(2000).max(2100).optional(),
  currency: currencyStr,
});

export const payeesQuery = z.object({
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
  limit: z.coerce.number().int().min(1).max(50).default(10),
  currency: currencyStr,
});

export const unnecessaryQuery = z.object({ month: monthStr.optional(), currency: currencyStr });

export const burnRateQuery = z.object({ currency: currencyStr });
