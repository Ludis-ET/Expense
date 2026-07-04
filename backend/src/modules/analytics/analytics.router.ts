import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import { recurringCatchUp } from '../recurring/recurring.middleware.js';
import {
  burnRateQuery,
  categoriesQuery,
  heatmapQuery,
  incomeVsExpenseQuery,
  payeesQuery,
  seriesQuery,
  summaryQuery,
  unnecessaryQuery,
} from './analytics.schema.js';
import * as analytics from './analytics.service.js';

export const analyticsRouter = Router();

analyticsRouter.use(requireAuth, recurringCatchUp);

analyticsRouter.get(
  '/summary',
  validate({ query: summaryQuery }),
  asyncHandler(async (req, res) => {
    const q = req.query as { month?: string; currency?: string };
    res.json(await analytics.summary(req.user!, q.month, q.currency));
  }),
);

analyticsRouter.get(
  '/series',
  validate({ query: seriesQuery }),
  asyncHandler(async (req, res) => {
    const q = req.query as unknown as { granularity: 'day' | 'week' | 'month'; from?: Date; to?: Date; currency?: string };
    res.json(await analytics.series(req.user!, q.granularity, q.from, q.to, q.currency));
  }),
);

analyticsRouter.get(
  '/categories',
  validate({ query: categoriesQuery }),
  asyncHandler(async (req, res) => {
    const q = req.query as unknown as { kind: 'INCOME' | 'EXPENSE'; from?: Date; to?: Date; currency?: string };
    res.json(await analytics.byCategory(req.user!, q.kind, q.from, q.to, q.currency));
  }),
);

analyticsRouter.get(
  '/income-vs-expense',
  validate({ query: incomeVsExpenseQuery }),
  asyncHandler(async (req, res) => {
    const q = req.query as unknown as { months: number; currency?: string };
    res.json(await analytics.incomeVsExpense(req.user!, q.months, q.currency));
  }),
);

analyticsRouter.get(
  '/heatmap',
  validate({ query: heatmapQuery }),
  asyncHandler(async (req, res) => {
    const q = req.query as { year?: number; currency?: string };
    res.json(await analytics.heatmap(req.user!, q.year, q.currency));
  }),
);

analyticsRouter.get(
  '/payees',
  validate({ query: payeesQuery }),
  asyncHandler(async (req, res) => {
    const q = req.query as unknown as { limit: number; from?: Date; to?: Date; currency?: string };
    res.json(await analytics.topPayees(req.user!, q.limit, q.from, q.to, q.currency));
  }),
);

analyticsRouter.get(
  '/unnecessary',
  validate({ query: unnecessaryQuery }),
  asyncHandler(async (req, res) => {
    const q = req.query as { month?: string; currency?: string };
    res.json(await analytics.unnecessary(req.user!, q.month, q.currency));
  }),
);

analyticsRouter.get(
  '/burn-rate',
  validate({ query: burnRateQuery }),
  asyncHandler(async (req, res) => {
    const q = req.query as { currency?: string };
    res.json(await analytics.burnRate(req.user!, q.currency));
  }),
);
