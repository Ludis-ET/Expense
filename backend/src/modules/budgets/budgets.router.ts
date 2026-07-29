import { Router } from 'express';
import { asyncHandler } from '../../core/http.js';
import { requireAuth } from '../../core/middleware/auth.js';
import { validate } from '../../core/middleware/validate.js';
import {
  adjustBudgetSchema,
  budgetIdParam,
  budgetSourcesQuery,
  createBudgetSchema,
  fundBudgetSchema,
  listBudgetsQuery,
  releaseBudgetSchema,
  updateBudgetSchema,
} from './budgets.schema.js';
import * as budgets from './budgets.service.js';

export const budgetsRouter = Router();

budgetsRouter.use(requireAuth);

budgetsRouter.get(
  '/',
  validate({ query: listBudgetsQuery }),
  asyncHandler(async (req, res) => {
    res.json(await budgets.list(req.user!, req.query as never));
  }),
);

/** Plans that still hold money - offered as "pay from" options on a transaction. */
budgetsRouter.get(
  '/sources',
  validate({ query: budgetSourcesQuery }),
  asyncHandler(async (req, res) => {
    res.json(await budgets.spendableSources(req.user!, req.query.currency as string | undefined));
  }),
);

budgetsRouter.get(
  '/:id',
  validate({ params: budgetIdParam }),
  asyncHandler(async (req, res) => {
    res.json(await budgets.getById(req.user!, req.params.id!));
  }),
);

budgetsRouter.post(
  '/',
  validate({ body: createBudgetSchema }),
  asyncHandler(async (req, res) => {
    res.status(201).json(await budgets.create(req.user!, req.body));
  }),
);

budgetsRouter.put(
  '/:id',
  validate({ params: budgetIdParam, body: updateBudgetSchema }),
  asyncHandler(async (req, res) => {
    res.json(await budgets.update(req.user!, req.params.id!, req.body));
  }),
);

/** Move money from an account into the plan's pot. */
budgetsRouter.post(
  '/:id/fund',
  validate({ params: budgetIdParam, body: fundBudgetSchema }),
  asyncHandler(async (req, res) => {
    res.json(await budgets.fund(req.user!, req.params.id!, req.body));
  }),
);

/** Give money in the pot back to the account it came from. */
budgetsRouter.post(
  '/:id/release',
  validate({ params: budgetIdParam, body: releaseBudgetSchema }),
  asyncHandler(async (req, res) => {
    res.json(await budgets.release(req.user!, req.params.id!, req.body));
  }),
);

/** Raise or cut the plan amount, tracked as a movement instead of an edit. */
budgetsRouter.post(
  '/:id/adjust',
  validate({ params: budgetIdParam, body: adjustBudgetSchema }),
  asyncHandler(async (req, res) => {
    res.json(await budgets.adjust(req.user!, req.params.id!, req.body));
  }),
);

budgetsRouter.post(
  '/:id/close',
  validate({ params: budgetIdParam }),
  asyncHandler(async (req, res) => {
    res.json(await budgets.close(req.user!, req.params.id!));
  }),
);

budgetsRouter.post(
  '/:id/reopen',
  validate({ params: budgetIdParam }),
  asyncHandler(async (req, res) => {
    res.json(await budgets.reopen(req.user!, req.params.id!));
  }),
);

budgetsRouter.delete(
  '/:id',
  validate({ params: budgetIdParam }),
  asyncHandler(async (req, res) => {
    await budgets.remove(req.user!, req.params.id!);
    res.status(204).end();
  }),
);
