import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import { recurringCatchUp } from '../recurring/recurring.middleware.js';
import {
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
    res.json(await analytics.summary(req.user!, req.query.month as string | undefined));
  }),
);

analyticsRouter.get(
  '/series',
  validate({ query: seriesQuery }),
  asyncHandler(async (req, res) => {
    const q = req.query as never as { granularity: 'day' | 'week' | 'month'; from?: Date; to?: Date };
    res.json(await analytics.series(req.user!, q.granularity, q.from, q.to));
  }),
);

analyticsRouter.get(
  '/categories',
  validate({ query: categoriesQuery }),
  asyncHandler(async (req, res) => {
    const q = req.query as never as { kind: 'INCOME' | 'EXPENSE'; from?: Date; to?: Date };
    res.json(await analytics.byCategory(req.user!, q.kind, q.from, q.to));
  }),
);

analyticsRouter.get(
  '/income-vs-expense',
  validate({ query: incomeVsExpenseQuery }),
  asyncHandler(async (req, res) => {
    res.json(await analytics.incomeVsExpense(req.user!, (req.query as never as { months: number }).months));
  }),
);

analyticsRouter.get(
  '/heatmap',
  validate({ query: heatmapQuery }),
  asyncHandler(async (req, res) => {
    res.json(await analytics.heatmap(req.user!, (req.query as never as { year?: number }).year));
  }),
);

analyticsRouter.get(
  '/payees',
  validate({ query: payeesQuery }),
  asyncHandler(async (req, res) => {
    const q = req.query as never as { limit: number; from?: Date; to?: Date };
    res.json(await analytics.topPayees(req.user!, q.limit, q.from, q.to));
  }),
);

analyticsRouter.get(
  '/unnecessary',
  validate({ query: unnecessaryQuery }),
  asyncHandler(async (req, res) => {
    res.json(await analytics.unnecessary(req.user!, req.query.month as string | undefined));
  }),
);

analyticsRouter.get(
  '/burn-rate',
  asyncHandler(async (req, res) => {
    res.json(await analytics.burnRate(req.user!));
  }),
);
