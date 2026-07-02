import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import { budgetCategoryParam, budgetsMonthQuery, upsertBudgetSchema } from './budgets.schema.js';
import * as budgets from './budgets.service.js';

export const budgetsRouter = Router();

budgetsRouter.use(requireAuth);

budgetsRouter.get(
  '/',
  validate({ query: budgetsMonthQuery }),
  asyncHandler(async (req, res) => {
    res.json(await budgets.list(req.user!, req.query.month as string | undefined));
  }),
);

budgetsRouter.put(
  '/:categoryId',
  validate({ params: budgetCategoryParam, body: upsertBudgetSchema }),
  asyncHandler(async (req, res) => {
    res.json(await budgets.upsert(req.user!, req.params.categoryId!, req.body));
  }),
);

budgetsRouter.delete(
  '/:categoryId',
  validate({ params: budgetCategoryParam }),
  asyncHandler(async (req, res) => {
    await budgets.remove(req.user!, req.params.categoryId!);
    res.status(204).end();
  }),
);
