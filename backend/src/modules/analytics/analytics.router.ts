import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import { recurringCatchUp } from '../recurring/recurring.middleware.js';
import {
  burnRateQuery,
  categoriesQuery,
  dailySpendQuery,
  heatmapQuery,
  incomeVsExpenseQuery,
  moversQuery,
  outlookHistoryQuery,
  payeesQuery,
  seasonalQuery,
  seriesQuery,
  summaryQuery,
  unnecessaryQuery,
  weeklySnapshotQuery,
} from './analytics.schema.js';
import * as analytics from './analytics.service.js';
import * as analyticsPage from './analytics.page.js';
import * as outlook from './analytics.outlook.js';
import * as reports from './analytics.reports.js';
import * as weeks from './analytics.weeks.js';

export const analyticsRouter = Router();

analyticsRouter.use(requireAuth, recurringCatchUp);

/** The whole analytics page in one round trip. */
analyticsRouter.get(
  '/page',
  validate({ query: summaryQuery }),
  asyncHandler(async (req, res) => {
    const q = req.query as { month?: string; currency?: string };
    res.json(await analyticsPage.page(req.user!, q.month, q.currency));
  }),
);

/** History the monthly outlook needs: completed months, a stable surprise
 * buffer, and repeating payees over a 90-day window. */
analyticsRouter.get(
  '/outlook-history',
  validate({ query: outlookHistoryQuery }),
  asyncHandler(async (req, res) => {
    const q = req.query as unknown as { currency?: string; months: number };
    res.json(await outlook.outlookHistory(req.user!, q.currency, q.months));
  }),
);

/** Month-of-year, weekday and year-on-year shape, from whole history. */
analyticsRouter.get(
  '/seasonal',
  validate({ query: seasonalQuery }),
  asyncHandler(async (req, res) => {
    const q = req.query as unknown as { currency?: string; weeks: number };
    res.json(await reports.seasonal(req.user!, q.currency ?? 'ETB', q.weeks));
  }),
);

/** Which categories moved most since last month, up and down. */
analyticsRouter.get(
  '/movers',
  validate({ query: moversQuery }),
  asyncHandler(async (req, res) => {
    const q = req.query as { month?: string; currency?: string };
    res.json(await reports.movers(req.user!, q.month, q.currency ?? 'ETB'));
  }),
);

/** Per-day spend for a month (or the last 30 days), with streak maths done. */
analyticsRouter.get(
  '/daily',
  validate({ query: dailySpendQuery }),
  asyncHandler(async (req, res) => {
    const q = req.query as { month?: string; currency?: string };
    res.json(await weeks.dailySpending(req.user!, q));
  }),
);

/** This week against last week, from the stored Sunday-boundary snapshots. */
analyticsRouter.get(
  '/weekly-snapshot',
  validate({ query: weeklySnapshotQuery }),
  asyncHandler(async (req, res) => {
    res.json(await weeks.weeklySnapshot(req.user!, req.query.currency as string | undefined));
  }),
);

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
